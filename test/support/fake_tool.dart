import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final root = Platform.environment['CLONIFY_TEST_ROOT']!;
  void write(String path, String content) => File('$root/$path')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(content);
  if (arguments.first == 'worker') {
    write('tool-worker-ready', '$pid');
    await Future<void>.delayed(const Duration(seconds: 3));
    write(
      'ios/Runner/orphan-write.txt',
      'must never be written after cancellation',
    );
    return;
  }
  final command = arguments.join(' ');
  File('$root/tool-calls.jsonl')
      .writeAsStringSync('${jsonEncode(arguments)}\n', mode: FileMode.append);
  if (Platform.environment['CLONIFY_TEST_WAIT'] == '1' &&
      arguments.first == 'dart') {
    write('ios/Runner/partial-generator.txt', 'partial');
    if (Platform.environment['CLONIFY_TEST_CHILD'] == '1') {
      await Process.start(Platform.resolvedExecutable, [
        if (Platform.script.path.endsWith('.dart'))
          Platform.script.toFilePath(),
        'worker',
      ]);
    }
    write('tool-ready', '$pid');
    await Future<void>.delayed(const Duration(seconds: 30));
  }
  if (Platform.environment['CLONIFY_TEST_FAIL'] case final String fail
      when command.contains(fail)) {
    write('ios/Runner/partial-generator.txt', 'partial');
    stderr.writeln('Simulated tool failure');
    exitCode = 7;
    return;
  }
  if (arguments.first == 'dart') {
    if (command.contains('flutter_launcher_icons')) {
      write('android/app/src/main/res/mipmap/icon.png', 'new icons');
    }
    if (command.contains('flutter_native_splash')) {
      write('ios/Runner/Base.lproj/LaunchScreen.storyboard', 'new splash');
    }
    if (command.contains('intl_utils')) {
      write('lib/generated/l10n.dart', '// new localization');
    }
  } else if (arguments.first == 'flutter') {
    final target = arguments[2];
    if (Platform.environment['CLONIFY_TEST_STALE'] == '1') return;
    switch (target) {
      case 'appbundle':
        write(
          'build/app/outputs/bundle/release/app-release.aab',
          'AAB $command',
        );
      case 'apk':
        write('build/app/outputs/flutter-apk/app-release.apk', 'APK $command');
      case 'ipa':
        write('build/ios/ipa/App.ipa', 'IPA $command');
    }
  } else if (arguments.first == 'fastlane') {
    final contents = File('fastlane/Fastfile').readAsStringSync();
    if (!contents.contains('com.example.alpha') ||
        !contents.replaceAll(r'\', '/').contains('build/')) {
      stderr.writeln('Fastfile must be updated before upload');
      exitCode = 8;
      return;
    }
    write(
      'tool-upload-${Directory.current.path.split(Platform.pathSeparator).last}',
      contents,
    );
  } else if (arguments.first == 'flutterfire') {
    final fixture = jsonDecode(
      File('$root/tool-firebase-fixture.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final entry in fixture.entries) {
      write(entry.key, entry.value as String);
    }
  }
}
