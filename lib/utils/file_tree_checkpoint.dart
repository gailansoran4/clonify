import 'dart:io';
import 'dart:convert';

import '../custom_exceptions.dart';
import 'command_process.dart';
import 'project_lock.dart';
import 'project_paths.dart';

import 'package:clonify/utils/clonify_helpers.dart';
import 'package:path/path.dart' as p;

/// Local files `clonify configure` may change. On failure these are restored
/// so the project looks like the switch never ran.
const configureMutableRoots = <String>[
  'android',
  'ios',
  'macos',
  'web',
  'linux',
  'windows',
  'assets/images',
  'lib/generated',
  'lib/firebase_options.dart',
  'shorebird.yaml',
  'pubspec.yaml',
  'pubspec.lock',
  'l10n.yaml',
  '.flutter-plugins-dependencies',
  'package_rename_config.yaml',
  'flutter_launcher_icons.yaml',
  'flutter_native_splash.yaml',
  'firebase.json',
  '.firebaserc',
  'clonify',
];

const checkpointSkipDirectoryNames = <String>{
  '.gradle',
  'build',
  '.cxx',
  'captures',
  // Flutter regenerates this; it also contains package symlinks that
  // File.copySync cannot copy when they point at directories.
  'ephemeral',
};

/// Thrown after a failed configure has restored the previous project files.
class ConfigureRolledBackException implements Exception {
  ConfigureRolledBackException(
    this.cause, {
    this.restoreError,
    this.backupPath,
  });

  final Object cause;
  final Object? restoreError;
  final String? backupPath;

  String get message {
    if (restoreError == null) return 'Command failed: $cause';
    return 'Command failed: $cause\nCould not restore all previous files: $restoreError\nBackup retained at $backupPath. Run clonify recover after fixing the filesystem error.';
  }

  @override
  String toString() {
    if (restoreError == null) {
      return '$message\nRestored previous project files.';
    }
    return message;
  }
}

/// Snapshot of configure-owned files. Restore wipes a half-applied clone
/// (for example iOS already rewritten, Android signing then failed).
class FileTreeCheckpoint {
  FileTreeCheckpoint._(this.backupDir, this.entries);

  final Directory backupDir;
  final List<CheckpointEntry> entries;

  static FileTreeCheckpoint capture([
    Iterable<String> roots = configureMutableRoots,
    Directory? storage,
  ]) {
    final backupDir = (storage ?? Directory.systemTemp).createTempSync(
      'clonify_checkpoint_',
    );
    try {
      if (!Platform.isWindows) {
        final result = Process.runSync('chmod', ['700', backupDir.path]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Cannot protect backup directory',
            backupDir.path,
          );
        }
      }
      final paths = roots
          .map((root) => p.normalize(p.absolute(root)))
          .toSet()
          .toList();
      paths.removeWhere(
        (root) =>
            paths.any((other) => other != root && p.isWithin(other, root)),
      );
      final entries = <CheckpointEntry>[
        for (var index = 0; index < paths.length; index++)
          _captureRoot(backupDir, paths[index], '$index'),
      ];
      return FileTreeCheckpoint._(backupDir, entries);
    } catch (_) {
      backupDir.deleteSync(recursive: true);
      rethrow;
    }
  }

  void restore({bool discardAfterRestore = true}) {
    Object? firstError;
    StackTrace? firstStack;
    for (final entry in entries) {
      try {
        _restoreRoot(entry);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
    }
    if (discardAfterRestore) discard();
  }

  void discard() {
    if (backupDir.existsSync()) {
      backupDir.deleteSync(recursive: true);
    }
  }

  static CheckpointEntry _captureRoot(
    Directory backupDir,
    String root,
    String id,
  ) {
    final type = FileSystemEntity.typeSync(root, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return CheckpointEntry(root: root, existed: false, id: id);
    }
    final dest = p.join(backupDir.path, id, p.basename(root));
    _copyEntity(root, dest);
    return CheckpointEntry(
      root: root,
      existed: true,
      id: id,
      isDirectory: type == FileSystemEntityType.directory,
    );
  }

  void _restoreRoot(CheckpointEntry entry) {
    if (!entry.existed) {
      _deleteEntity(entry.root);
      return;
    }
    final backupPath = p.join(backupDir.path, entry.id, p.basename(entry.root));
    if (_isMissing(backupPath)) {
      throw StateError('Checkpoint backup missing for ${entry.root}');
    }

    final absoluteRoot = p.normalize(p.absolute(entry.root));
    final staged = '$absoluteRoot.clonify_restore_${entry.id}';
    _deleteEntity(staged);
    _copyEntity(backupPath, staged);

    final parked = _parkSkippedDirectories(entry.root);
    var restored = false;
    try {
      _deleteEntity(entry.root);
      _renameEntity(staged, entry.root);
      restored = true;
    } catch (error) {
      if (_isMissing(entry.root) && !_isMissing(staged)) {
        _copyEntity(staged, entry.root);
        restored = !_isMissing(entry.root);
      }
      if (!restored) rethrow;
    } finally {
      _unparkSkippedDirectories(entry.root, parked);
      _deleteEntity(staged);
    }
  }
}

class CheckpointEntry {
  CheckpointEntry({
    required this.root,
    required this.existed,
    required this.id,
    this.isDirectory = false,
  });

  final String root;
  final bool existed;
  final String id;
  final bool isDirectory;
}

const recoveryJournalPath = '.dart_tool/clonify/recovery.json';

/// Refuses to overwrite an interrupted operation's recovery record.
void assertNoPendingRecovery() {
  if (File(recoveryJournalPath).existsSync()) {
    throw CustomException(
      'An unfinished Clonify operation needs recovery. Run clonify recover before another command.',
    );
  }
}

void writeRecoveryJournal(FileTreeCheckpoint checkpoint, String state) {
  final journal = File(recoveryJournalPath);
  journal.parent.createSync(recursive: true);
  final data = {
    'schema': 1,
    'project': Directory.current.resolveSymbolicLinksSync(),
    'state': state,
    'backup': checkpoint.backupDir.absolute.path,
    'entries': [
      for (final entry in checkpoint.entries)
        {
          'root': entry.root,
          'existed': entry.existed,
          'id': entry.id,
          'isDirectory': entry.isDirectory,
        },
    ],
  };
  final staged = File('${journal.path}.tmp');
  staged.writeAsStringSync(jsonEncode(data), flush: true);
  staged.renameSync(journal.path);
}

/// Restores a durable checkpoint after an interrupted process. Committed
/// operations only need backup cleanup; their successful changes stay applied.
Future<bool> recoverProject() => withProjectLock(() async {
  final journal = File(recoveryJournalPath);
  if (!journal.existsSync()) return false;
  final Object? data;
  try {
    data = jsonDecode(journal.readAsStringSync());
  } on FormatException {
    throw CustomException(
      'Invalid recovery JSON at ${journal.path}. Backup retained.',
    );
  }
  final project = Directory.current.resolveSymbolicLinksSync();
  final storage = p.join(project, '.dart_tool', 'clonify', 'checkpoints');
  if (data is! Map ||
      data['schema'] != 1 ||
      data['project'] != project ||
      data['backup'] is! String ||
      !p.isWithin(storage, data['backup'] as String) ||
      data['entries'] is! List ||
      !['pending', 'committed'].contains(data['state'])) {
    throw CustomException(
      'Invalid recovery journal at ${journal.path}. Backup retained; inspect the journal before retrying.',
    );
  }
  final entries = <CheckpointEntry>[];
  for (final item in data['entries'] as List) {
    if (item is! Map ||
        item['root'] is! String ||
        !p.isWithin(project, item['root'] as String) ||
        isProtectedProjectPath(item['root'] as String) ||
        item['id'] is! String ||
        !RegExp(r'^\d+$').hasMatch(item['id'] as String) ||
        item['existed'] is! bool ||
        item['isDirectory'] is! bool) {
      throw CustomException('Invalid recovery entry. Backup retained.');
    }
    entries.add(
      CheckpointEntry(
        root: item['root'] as String,
        existed: item['existed'] as bool,
        id: item['id'] as String,
        isDirectory: item['isDirectory'] as bool,
      ),
    );
  }
  assertProjectPath(data['backup'] as String);
  for (final entry in entries) {
    assertProjectPath(entry.root);
  }
  final checkpoint = FileTreeCheckpoint._(
    Directory(data['backup'] as String),
    entries,
  );
  if (data['state'] == 'committed') {
    checkpoint.discard();
  } else {
    checkpoint.restore(discardAfterRestore: false);
    writeRecoveryJournal(checkpoint, 'committed');
    checkpoint.discard();
  }
  journal.deleteSync();
  return true;
});

Future<T> runConfigureTransaction<T>(
  Future<T> Function() body, {
  Iterable<String> roots = configureMutableRoots,
}) => withProjectLock(() async {
  assertNoPendingRecovery();
  checkCommandCancellation();
  final project = Directory.current.resolveSymbolicLinksSync();
  final paths = roots.where((root) => root.trim().isNotEmpty).toSet();
  for (final root in paths) {
    assertProjectPath(root, allowSymlinks: false);
    final absolute = p.normalize(p.absolute(root));
    if (!p.isWithin(project, absolute) || isProtectedProjectPath(absolute)) {
      throw CustomException(
        'Cannot snapshot path outside project files: $root',
      );
    }
  }
  final storage = Directory('.dart_tool/clonify/checkpoints')
    ..createSync(recursive: true);
  final checkpoint = FileTreeCheckpoint.capture(paths, storage);
  try {
    writeRecoveryJournal(checkpoint, 'pending');
  } catch (_) {
    checkpoint.discard();
    rethrow;
  }
  late final T result;
  try {
    result = await body();
    checkCommandCancellation();
    writeRecoveryJournal(checkpoint, 'committed');
  } catch (error) {
    try {
      checkpoint.restore(discardAfterRestore: false);
      writeRecoveryJournal(checkpoint, 'committed');
      checkpoint.discard();
      File(recoveryJournalPath).deleteSync();
    } catch (restoreError) {
      throw ConfigureRolledBackException(
        error,
        restoreError: restoreError,
        backupPath: checkpoint.backupDir.absolute.path,
      );
    }
    throw ConfigureRolledBackException(error);
  }
  try {
    checkpoint.discard();
    File(recoveryJournalPath).deleteSync();
  } catch (_) {
    logger.w(
      'Command succeeded, but backup cleanup needs attention. Run clonify recover to finish cleanup.',
    );
  }
  return result;
});

void _copyEntity(String sourcePath, String destPath) {
  final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.link) {
    File(destPath).parent.createSync(recursive: true);
    final existing = FileSystemEntity.typeSync(destPath, followLinks: false);
    if (existing != FileSystemEntityType.notFound) {
      _deleteEntity(destPath);
    }
    Link(destPath).createSync(Link(sourcePath).targetSync());
    return;
  }
  if (type == FileSystemEntityType.directory) {
    Directory(destPath).createSync(recursive: true);
    for (final child in Directory(sourcePath).listSync(followLinks: false)) {
      final name = p.basename(child.path);
      if (_skipCheckpointDirectory(child.path)) continue;
      _copyEntity(child.path, p.join(destPath, name));
    }
    return;
  }
  File(destPath).parent.createSync(recursive: true);
  File(sourcePath).copySync(destPath);
}

void _deleteEntity(String path) {
  final type = FileSystemEntity.typeSync(path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type == FileSystemEntityType.directory) {
    Directory(path).deleteSync(recursive: true);
    return;
  }
  if (type == FileSystemEntityType.link) {
    Link(path).deleteSync();
    return;
  }
  File(path).deleteSync();
}

void _renameEntity(String sourcePath, String destPath) {
  final type = FileSystemEntity.typeSync(sourcePath, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  File(destPath).parent.createSync(recursive: true);
  if (type == FileSystemEntityType.directory) {
    Directory(sourcePath).renameSync(destPath);
    return;
  }
  if (type == FileSystemEntityType.link) {
    Link(sourcePath).renameSync(destPath);
    return;
  }
  File(sourcePath).renameSync(destPath);
}

bool _isMissing(String path) {
  return FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.notFound;
}

List<({String relative, Directory hold})> _parkSkippedDirectories(String root) {
  final parked = <({String relative, Directory hold})>[];
  final type = FileSystemEntity.typeSync(root, followLinks: false);
  if (type != FileSystemEntityType.directory) return parked;

  void walk(Directory dir) {
    for (final child in dir.listSync(followLinks: false).toList()) {
      if (child is! Directory) continue;
      final name = p.basename(child.path);
      if (_skipCheckpointDirectory(child.path)) {
        final hold = Directory(
          p.dirname(p.absolute(root)),
        ).createTempSync('.clonify_park_');
        final moved = p.join(hold.path, name);
        child.renameSync(moved);
        parked.add((relative: p.relative(child.path, from: root), hold: hold));
      } else {
        walk(child);
      }
    }
  }

  walk(Directory(root));
  return parked;
}

void _unparkSkippedDirectories(
  String root,
  List<({String relative, Directory hold})> parked,
) {
  for (final item in parked) {
    final (:relative, :hold) = item;
    final name = p.basename(relative);
    final source = Directory(p.join(hold.path, name));
    if (!source.existsSync()) continue;
    final dest = Directory(p.join(root, relative));
    dest.parent.createSync(recursive: true);
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    source.renameSync(dest.path);
    hold.deleteSync(recursive: true);
  }
}

bool _skipCheckpointDirectory(String path) {
  final relative = p.relative(p.absolute(path), from: Directory.current.path);
  final segments = p.split(relative);
  return segments.isNotEmpty &&
      [
        'android',
        'ios',
        'macos',
        'linux',
        'windows',
        'web',
      ].contains(segments.first) &&
      checkpointSkipDirectoryNames.contains(p.basename(path));
}
