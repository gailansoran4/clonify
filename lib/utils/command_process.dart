import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../custom_exceptions.dart';
import 'tool_paths.dart';

/// A cancellation that must unwind file transactions before the CLI exits.
class CommandCancelled implements Exception {
  const CommandCancelled();

  @override
  String toString() => 'Command cancelled.';
}

/// Coordinates signals and subprocesses for one CLI invocation.
class CommandSession {
  bool cancelled = false;
  final Set<Process> children = {};
  final List<StreamSubscription<ProcessSignal>> subscriptions = [];

  void check() {
    if (cancelled) throw const CommandCancelled();
  }

  void cancel() {
    cancelled = true;
  }

  Future<T> run<T>(Future<T> Function() body) async {
    for (final signal in [
      ProcessSignal.sigint,
      if (!Platform.isWindows) ProcessSignal.sigterm,
    ]) {
      subscriptions.add(signal.watch().listen((_) => cancel()));
    }
    try {
      return await runZoned(body, zoneValues: {CommandSession: this});
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }
}

void checkCommandCancellation() {
  (Zone.current[CommandSession] as CommandSession?)?.check();
}

/// Executes argument arrays. Windows batch tools use cmd with checked arguments;
/// native executables need no shell. Failure messages omit argument values.
Future<ProcessResult> executeCommand(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  Duration timeout = const Duration(minutes: 30),
  bool inheritStdio = false,
  bool checkExitCode = true,
}) async {
  final session = Zone.current[CommandSession] as CommandSession?;
  session?.check();
  final resolved =
      findExecutable(
        executable,
        environment: {...Platform.environment, ...?environment},
      ) ??
      executable;
  final batch =
      Platform.isWindows &&
      (resolved.toLowerCase().endsWith('.bat') ||
          resolved.toLowerCase().endsWith('.cmd'));
  if (batch &&
      [
        resolved,
        ...arguments,
      ].any((value) => RegExp('["%&|<>^!\\r\\n]').hasMatch(value))) {
    throw CustomException(
      'Windows batch tools cannot safely accept shell metacharacters in their path or arguments. Use a tool and credential path without those characters.',
    );
  }
  final Process process;
  try {
    process = await Process.start(
      batch
          ? '${Platform.environment['SystemRoot'] ?? r'C:\Windows'}\\System32\\cmd.exe'
          : resolved,
      // CALL avoids cmd stripping the executable's opening quote when both
      // the tool path and a credential argument contain spaces.
      batch
          ? ['/d', '/v:off', '/c', 'call', resolved, ...arguments]
          : arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      mode: inheritStdio
          ? ProcessStartMode.inheritStdio
          : ProcessStartMode.normal,
    );
  } on ProcessException catch (error) {
    throw CustomException(
      'Could not start $executable in ${workingDirectory ?? Directory.current.path}: ${error.message}. Check its installation and executable permissions.',
    );
  }
  session?.children.add(process);
  // Captured commands cannot be answered interactively. EOF makes an unexpected
  // tool prompt fail promptly instead of blocking until the command timeout.
  if (!inheritStdio) await process.stdin.close();
  final output = inheritStdio
      ? Future.value('')
      : process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
  final errors = inheritStdio
      ? Future.value('')
      : process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .join();
  var timedOut = false;
  Timer? forceKill;
  void stop() {
    if (forceKill != null) return;
    if (Platform.isWindows) {
      try {
        Process.runSync('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } on ProcessException {
        /* Fall back to terminating the direct child. */
      }
    }
    final descendants = descendantProcesses(process.pid);
    for (final pid in descendants.reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
    process.kill(ProcessSignal.sigterm);
    forceKill = Timer(const Duration(seconds: 3), () {
      process.kill(ProcessSignal.sigkill);
    });
  }

  final timer = Timer(timeout, () {
    timedOut = true;
    stop();
  });
  final cancellation = Timer.periodic(const Duration(milliseconds: 100), (_) {
    if (session?.cancelled == true) stop();
  });
  try {
    final code = await process.exitCode;
    final stdout = await output.timeout(
      const Duration(seconds: 5),
      onTimeout: () => '',
    );
    final stderr = await errors.timeout(
      const Duration(seconds: 5),
      onTimeout: () => '',
    );
    session?.check();
    if (timedOut) {
      throw CustomException(
        '$executable timed out after ${timeout.inSeconds}s. Check the tool and retry.',
      );
    }
    if (checkExitCode && code != 0) {
      throw CustomException(
        '$executable failed (exit $code) in ${workingDirectory ?? Directory.current.path}. Fix this tool failure and retry.',
      );
    }
    return ProcessResult(process.pid, code, stdout, stderr);
  } finally {
    timer.cancel();
    cancellation.cancel();
    forceKill?.cancel();
    session?.children.remove(process);
  }
}

/// Find only descendants of this command, before their parent exits. Killing
/// them first prevents generators from continuing to write after rollback.
List<int> descendantProcesses(int parent) {
  if (Platform.isWindows) return [];
  try {
    final result = Process.runSync('/bin/ps', ['-axo', 'pid=,ppid=']);
    if (result.exitCode != 0) return [];
    final rows = (result.stdout as String)
        .split('\n')
        .map((line) => line.trim().split(RegExp(r'\s+')))
        .where((parts) => parts.length == 2)
        .toList();
    final descendants = <int>[];
    final parents = {parent};
    var changed = true;
    while (changed) {
      changed = false;
      for (final row in rows) {
        final pid = int.tryParse(row[0]);
        final ppid = int.tryParse(row[1]);
        if (pid != null && parents.contains(ppid) && parents.add(pid)) {
          descendants.add(pid);
          changed = true;
        }
      }
    }
    return descendants;
  } on ProcessException {
    return [];
  }
}
