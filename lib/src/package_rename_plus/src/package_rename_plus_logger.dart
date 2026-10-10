import 'package:clonify/utils/tui_helpers.dart';

class PackageRenamePlusLogger {
  // (🟥 Red)
  static const _red = '\x1B[31m';
  // (🟩 Green)
  static const _green = '\x1B[32m';
  // (🟨 Yellow)
  static const _yellow = '\x1B[33m';
  // (🟧 Orange)
  static const _orange = '\x1B[38;5;214m';

  static void error(String message) {
    print(_colored(message: message, colorCode: _red));
  }

  static void warning(String message) {
    print(_colored(message: message, colorCode: _yellow));
  }

  static void info(String message) {
    print(_colored(message: message, colorCode: _green));
  }

  static void debug(String message) {
    print(_colored(message: message, colorCode: _orange));
  }

  static String _colored({
    required String message,
    String colorCode = _orange,
  }) {
    if (!isTUIEnabled()) return message;
    return message
        .split('\n')
        .map((line) => '$colorCode$line\x1B[0m') // Apply color per line
        .join('\n');
  }
}
