import 'dart:io';

import 'package:path/path.dart' as p;

import '../custom_exceptions.dart';

String? findExecutable(String executable, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  final extensions = Platform.isWindows
      ? ['', ...(env['PATHEXT'] ?? '.EXE;.CMD;.BAT').split(';')]
      : [''];
  final directories =
      p.isAbsolute(executable) || executable.contains(p.separator)
      ? ['']
      : (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':');
  for (final directory in directories) {
    for (final extension in extensions) {
      final path = directory.isEmpty
          ? '$executable$extension'
          : p.join(directory, '$executable$extension');
      final file = File(path);
      if (file.existsSync() &&
          (Platform.isWindows || file.statSync().mode & 0x49 != 0)) {
        return p.absolute(path);
      }
    }
  }
  return null;
}

void assertToolAvailable(String executable) {
  if (findExecutable(executable) == null) {
    throw CustomException(
      'Required tool "$executable" was not found on PATH. Install it or fix PATH before retrying.',
    );
  }
}
