import 'dart:convert';
import 'dart:io';

import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/utils/command_process.dart';
import 'package:clonify/utils/file_tree_checkpoint.dart';
import 'package:clonify/utils/clonify_helpers.dart';
import 'package:test/test.dart';

import '../silence_logs.dart';

void main() {
  silenceClonifyLogsForTests();
  late Directory root;
  late String previous;
  setUp(() {
    previous = Directory.current.path;
    root = Directory.systemTemp.createTempSync('clonify process café ');
    Directory.current = root;
  });
  tearDown(() {
    Directory.current = previous;
    root.deleteSync(recursive: true);
  });

  test(
    'literal arguments including shell syntax and Unicode never execute',
    () async {
      final script = File('echo.dart')
        ..writeAsStringSync(
          'import "dart:convert"; void main(List<String> args) { print(jsonEncode(args)); }',
        );
      final args = [
        'café with spaces',
        r'$(touch injected)',
        'a;b',
        "quotes'\"",
        r'$HOME',
        '',
      ];
      final result = await executeCommand(Platform.resolvedExecutable, [
        script.absolute.path,
        ...args,
      ], workingDirectory: root.path);
      expect(jsonDecode((result.stdout as String).trim()), args);
      expect(File('injected').existsSync(), isFalse);
    },
  );

  test('runCommand propagates a failed exit to its transaction', () async {
    File(
      'fail.dart',
    ).writeAsStringSync('import "dart:io"; void main() { exitCode = 9; }');
    File('pubspec.yaml').writeAsStringSync('old');
    await expectLater(
      runConfigureTransaction(() async {
        File('pubspec.yaml').writeAsStringSync('new');
        await runCommand(Platform.resolvedExecutable, [
          File('fail.dart').absolute.path,
        ], showLoading: false);
      }, roots: ['pubspec.yaml']),
      throwsA(
        isA<ConfigureRolledBackException>().having(
          (e) => '$e',
          'message',
          contains('exit 9'),
        ),
      ),
    );
    expect(File('pubspec.yaml').readAsStringSync(), 'old');
  });

  test('missing executables fail clearly without exposing arguments', () async {
    await expectLater(
      executeCommand('clonify-tool-that-does-not-exist', ['PRIVATE_SECRET']),
      throwsA(
        isA<CustomException>().having(
          (e) => e.message,
          'message',
          isNot(contains('PRIVATE_SECRET')),
        ),
      ),
    );
  });

  test('timeout terminates a tool and propagates failure', () async {
    File('wait.dart').writeAsStringSync(
      'import "dart:async"; Future<void> main() async { await Future<void>.delayed(Duration(seconds: 30)); }',
    );
    await expectLater(
      executeCommand(Platform.resolvedExecutable, [
        File('wait.dart').absolute.path,
      ], timeout: const Duration(milliseconds: 200)),
      throwsA(
        isA<CustomException>().having(
          (e) => e.message,
          'message',
          contains('timed out'),
        ),
      ),
    );
  });

  test('cancellation between stages restores files before returning', () async {
    File('pubspec.yaml').writeAsStringSync('old');
    final session = CommandSession();
    await expectLater(
      session.run(
        () => runConfigureTransaction(() async {
          File('pubspec.yaml').writeAsStringSync('new');
          session.cancel();
        }, roots: ['pubspec.yaml']),
      ),
      throwsA(isA<ConfigureRolledBackException>()),
    );
    expect(File('pubspec.yaml').readAsStringSync(), 'old');
  });

  test('failed restoration retains backup and recovery journal', () async {
    File('one').writeAsStringSync('before');
    File('two').writeAsStringSync('before two');
    String? backup;
    await expectLater(
      runConfigureTransaction(() async {
        final journal =
            jsonDecode(File(recoveryJournalPath).readAsStringSync()) as Map;
        backup = journal['backup'] as String;
        File('$backup/0/one').deleteSync();
        File('one').writeAsStringSync('after');
        File('two').writeAsStringSync('after two');
        throw StateError('failed later');
      }, roots: ['one', 'two']),
      throwsA(
        isA<ConfigureRolledBackException>().having(
          (e) => e.restoreError,
          'restoreError',
          isNotNull,
        ),
      ),
    );
    expect(File(recoveryJournalPath).existsSync(), isTrue);
    expect(Directory(backup!).existsSync(), isTrue);
    expect(File('two').readAsStringSync(), 'before two');
    File('$backup/0/one').writeAsStringSync('before');
    expect(await recoverProject(), isTrue);
    expect(File('one').readAsStringSync(), 'before');
    expect(Directory(backup!).existsSync(), isFalse);
  });

  test(
    'committed journal cleanup never rolls back successful changes',
    () async {
      File('one').writeAsStringSync('before');
      final storage = Directory('.dart_tool/clonify/checkpoints')
        ..createSync(recursive: true);
      final checkpoint = FileTreeCheckpoint.capture(['one'], storage);
      writeRecoveryJournal(checkpoint, 'committed');
      File('one').writeAsStringSync('after');
      expect(await recoverProject(), isTrue);
      expect(File('one').readAsStringSync(), 'after');
    },
  );

  test(
    'invalid recovery metadata cannot delete project or outside roots',
    () async {
      final journal = File(recoveryJournalPath)
        ..parent.createSync(recursive: true);
      journal.writeAsStringSync(
        jsonEncode({
          'schema': 1,
          'project': root.resolveSymbolicLinksSync(),
          'state': 'pending',
          'backup': root.parent.path,
          'entries': [],
        }),
      );
      await expectLater(recoverProject(), throwsA(isA<CustomException>()));
      expect(journal.existsSync(), isTrue);
    },
  );

  test('capture deduplicates overlapping roots and restores both contents', () {
    File('clonify/clones/a/config.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('before');
    final checkpoint = FileTreeCheckpoint.capture([
      'clonify',
      'clonify/clones/a',
    ]);
    expect(checkpoint.entries, hasLength(1));
    File('clonify/clones/a/config.json').writeAsStringSync('after');
    checkpoint.restore();
    expect(File('clonify/clones/a/config.json').readAsStringSync(), 'before');
  });
}
