import 'dart:io';

import 'package:path/path.dart' as p;

import '../custom_exceptions.dart';

/// Expresses paths relative to the resolved project root without following
/// links inside the project. Windows temporary directories can use 8.3 aliases.
String projectAbsolutePath(String path) {
  final lexicalRoot = p.normalize(Directory.current.absolute.path);
  final absolute = p.normalize(p.absolute(path));
  if (p.equals(lexicalRoot, absolute) || p.isWithin(lexicalRoot, absolute)) {
    return p.normalize(
      p.join(
        Directory.current.resolveSymbolicLinksSync(),
        p.relative(absolute, from: lexicalRoot),
      ),
    );
  }
  return absolute;
}

/// Keeps managed paths in this project and rejects symlink escapes before writes.
void assertProjectPath(String path, {bool allowSymlinks = true}) {
  final root = Directory.current.resolveSymbolicLinksSync();
  final absolute = projectAbsolutePath(path);
  if (!p.isWithin(root, absolute)) {
    throw CustomException('Path must be inside this project: $path');
  }
  if (!allowSymlinks) {
    var candidate = absolute;
    while (candidate != root && p.isWithin(root, candidate)) {
      if (FileSystemEntity.typeSync(candidate, followLinks: false) ==
          FileSystemEntityType.link) {
        throw CustomException(
          'Managed output path must not be a symlink: $path',
        );
      }
      candidate = p.dirname(candidate);
    }
  }
  var ancestor = absolute;
  while (FileSystemEntity.typeSync(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    ancestor = p.dirname(ancestor);
  }
  final resolved =
      FileSystemEntity.typeSync(ancestor) == FileSystemEntityType.directory
      ? Directory(ancestor).resolveSymbolicLinksSync()
      : File(ancestor).resolveSymbolicLinksSync();
  if (resolved != root && !p.isWithin(root, resolved)) {
    throw CustomException('Path resolves outside this project: $path');
  }
}

bool isProtectedProjectPath(String path) {
  final root = Directory.current.resolveSymbolicLinksSync();
  final relative = p.relative(projectAbsolutePath(path), from: root);
  final segments = p.split(relative);
  return segments.isEmpty || ['.git', '.dart_tool'].contains(segments.first);
}
