import 'dart:async';
import 'dart:io';

import '../custom_exceptions.dart';
import 'project_paths.dart';

final Set<String> lockedProjects = {};

/// An OS lock is released even after a crash; never delete the lock file while
/// another process may have it open. The zone permits nested command helpers.
Future<T> withProjectLock<T>(Future<T> Function() body) async {
  final root = Directory.current.resolveSymbolicLinksSync();
  if (Zone.current[#clonifyLockedProject] == root) return body();
  if (lockedProjects.contains(root)) {
    throw CustomException(
      'Another Clonify operation is already running in $root.',
    );
  }
  final file = File('$root/.dart_tool/clonify/operation.lock');
  assertProjectPath(file.path);
  file.parent.createSync(recursive: true);
  final handle = file.openSync(mode: FileMode.append);
  try {
    try {
      handle.lockSync(FileLock.exclusive);
    } on FileSystemException {
      throw CustomException(
        'Another Clonify command is running in $root. Wait for it to finish.',
      );
    }
    lockedProjects.add(root);
    return await runZoned(body, zoneValues: {#clonifyLockedProject: root});
  } finally {
    lockedProjects.remove(root);
    handle.closeSync();
  }
}
