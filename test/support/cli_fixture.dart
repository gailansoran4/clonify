import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Runs the real entry point with small temporary Flutter projects and fake
/// external tools. No real Firebase accounts, stores, or Flutter builds run.
class CliFixture {
  CliFixture(this.repository, {this.cliExecutable, this.toolExecutable}) {
    root = Directory.systemTemp.createTempSync('clonify CLI café ');
    project = Directory(p.join(root.path, 'project with spaces'))..createSync();
    bin = Directory(p.join(root.path, 'fake tools'))..createSync();
    for (final tool in [
      'dart',
      'flutter',
      'flutterfire',
      'firebase',
      'fastlane',
      'shorebird',
    ]) {
      final executable = toolExecutable ?? Platform.resolvedExecutable;
      final script = p.join(repository, 'test/support/fake_tool.dart');
      final file = File(
        p.join(bin.path, Platform.isWindows ? '$tool.cmd' : tool),
      );
      if (Platform.isWindows) {
        file.writeAsStringSync(
          '@echo off\r\n"$executable" ${toolExecutable == null ? '"$script" ' : ''}"$tool" %*\r\n',
        );
      } else {
        String quote(String text) => "'${text.replaceAll("'", "'\\''")}'";
        file.writeAsStringSync(
          '#!/bin/sh\nexec ${quote(executable)} ${toolExecutable == null ? '${quote(script)} ' : ''}${quote(tool)} "\$@"\n',
        );
        Process.runSync('chmod', ['+x', file.path]);
      }
    }
    write('pubspec.yaml', '''
name: fixture_app
version: 1.0.0+1
environment:
  sdk: ^3.8.1
dependencies:
  flutter:
    sdk: flutter
dev_dependencies:
  flutter_launcher_icons: any
  flutter_native_splash: any
  intl_utils: any
''');
    write('clonify/clonify_settings.yaml', '''
firebase:
  enabled: false
  settings_file: firebase.json
fastlane:
  enabled: true
  settings_file: fastlane
shorebird:
  enabled: false
company_name: example
default_color: '#FFFFFF'
needs_launcher_icon: true
needs_splash_screen: true
needs_logo: true
update_android_info: true
update_ios_info: true
''');
    write('android/app/build.gradle.kts', '''
android {
  namespace = "com.old.app"
  defaultConfig {
    applicationId = "com.old.app"
  }
}
''');
    write(
      'android/app/src/main/AndroidManifest.xml',
      '<manifest package="com.old.app"><application android:label="Old App" /></manifest>',
    );
    write(
      'android/app/src/main/kotlin/com/old/app/MainActivity.kt',
      'package com.old.app\n// KEEP CUSTOM NATIVE CODE\nclass MainActivity {}\n',
    );
    write(
      'ios/Runner/Info.plist',
      '<plist><dict><key>CFBundleDisplayName</key><string>Old App</string><key>CFBundleName</key><string>Old</string></dict></plist>',
    );
    write('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = com.old.app;
PRODUCT_BUNDLE_IDENTIFIER = com.old.app;
PRODUCT_BUNDLE_IDENTIFIER = com.old.app.RunnerTests;
INFOPLIST_KEY_CFBundleDisplayName = "Old App";
''');
    write('android/fastlane/Fastfile', '''
bundleId = "com.old.app"
app_version = "1.0.0"
app_version_code = "1"
lane :upload do
  upload_to_play_store(aab: "old.aab")
end
''');
    write('ios/fastlane/Fastfile', '''
bundleId = "com.old.app"
app_version = "1.0.0"
lane :upload do
  upload_to_testflight(ipa: "old.ipa")
end
''');
    profile('alpha');
    profile('beta');
    write('clonify/last_client.txt', 'before');
  }

  final String repository;
  final String? cliExecutable;
  final String? toolExecutable;
  late final Directory root;
  late final Directory project;
  late final Directory bin;

  File file(String path) => File(p.join(project.path, path));
  void write(String path, String value) => file(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(value);

  void profile(String id, {Map<String, dynamic> changes = const {}}) {
    final config = {
      'clientId': id,
      'appName': 'App $id',
      'packageName': 'com.example.$id',
      'version': '1.0.0+1',
      'baseUrl': 'https://example.com',
      'primaryColor': '0xFF123456',
      'launcherIcon': 'icon.png',
      'splashScreen': 'splash.png',
      'logo': 'logo.png',
      ...changes,
    };
    write('clonify/clones/$id/config.json', jsonEncode(config));
    for (final name in ['icon.png', 'splash.png', 'logo.png']) {
      file('clonify/clones/$id/assets/$name')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync([
          0x89,
          0x50,
          0x4e,
          0x47,
          13,
          10,
          26,
          10,
          id.codeUnitAt(0),
        ]);
    }
  }

  List<String> arguments(List<String> args) => [
    if (cliExecutable == null) ...[
      '--packages=${p.join(repository, '.dart_tool/package_config.json')}',
      p.join(repository, 'bin/clonify.dart'),
    ],
    '--no-tui',
    ...args,
  ];

  Map<String, String> environment(Map<String, String> extra) => {
    'PATH':
        '${bin.path}${Platform.isWindows ? ';' : ':'}${Platform.environment['PATH']}',
    'CLONIFY_TEST_ROOT': project.path,
    'CLONIFY_TEST_REAL_DART': Platform.resolvedExecutable,
    ...extra,
  };

  Future<ProcessResult> run(
    List<String> args, {
    Map<String, String> env = const {},
  }) => Process.run(
    cliExecutable ?? Platform.resolvedExecutable,
    arguments(args),
    workingDirectory: project.path,
    environment: environment(env),
  );

  Future<Process> start(
    List<String> args, {
    Map<String, String> env = const {},
  }) => Process.start(
    cliExecutable ?? Platform.resolvedExecutable,
    arguments(args),
    workingDirectory: project.path,
    environment: environment(env),
  );

  Map<String, String> snapshot() => {
    for (final item
        in project
            .listSync(recursive: true, followLinks: false)
            .whereType<File>())
      if (!p.relative(item.path, from: project.path).startsWith('.dart_tool') &&
          !p.basename(item.path).startsWith('tool-'))
        p.relative(item.path, from: project.path): base64Encode(
          item.readAsBytesSync(),
        ),
  };

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

Future<({Directory directory, String cli, String tool})> compileTestTools(
  String repository,
) async {
  final directory = Directory.systemTemp.createTempSync(
    'clonify_compiled_tests_',
  );
  final suffix = Platform.isWindows ? '.exe' : '';
  final cli = p.join(directory.path, 'clonify$suffix');
  final tool = p.join(directory.path, 'fake-tool$suffix');
  try {
    for (final target in [
      (source: 'bin/clonify.dart', output: cli),
      (source: 'test/support/fake_tool.dart', output: tool),
    ]) {
      final result = await Process.run(Platform.resolvedExecutable, [
        'compile',
        'exe',
        target.source,
        '-o',
        target.output,
      ], workingDirectory: repository);
      if (result.exitCode != 0) {
        throw StateError(
          'Test executable compilation failed: ${result.stdout} ${result.stderr}',
        );
      }
    }
    return (directory: directory, cli: cli, tool: tool);
  } catch (_) {
    directory.deleteSync(recursive: true);
    rethrow;
  }
}
