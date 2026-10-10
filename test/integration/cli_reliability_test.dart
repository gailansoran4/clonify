import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clonify/utils/file_tree_checkpoint.dart';
import 'package:test/test.dart';

import '../support/cli_fixture.dart';
import '../support/firebase_fixture.dart';

void main() {
  final repository = Directory.current.path;
  late CliFixture fixture;
  late ({Directory directory, String cli, String tool}) executables;
  setUpAll(() async {
    executables = await compileTestTools(repository);
  });
  tearDownAll(() {
    executables.directory.deleteSync(recursive: true);
  });
  setUp(() {
    fixture = CliFixture(
      repository,
      cliExecutable: executables.cli,
      toolExecutable: executables.tool,
    );
  });
  tearDown(() {
    fixture.dispose();
  });

  const configure = ['configure', '--clientId', 'alpha', '--skipAll'];
  const buildAndroid = [
    'build',
    '--clientId',
    'alpha',
    '--skipAll',
    '--no-buildIpa',
  ];

  void success(ProcessResult result) => expect(
    result.exitCode,
    0,
    reason:
        '${result.stdout}\n${result.stderr}\n'
        '${fixture.file('tool-stderr.log').existsSync() ? fixture.file('tool-stderr.log').readAsStringSync() : ''}',
  );
  List<List<dynamic>> calls() => fixture
      .file('tool-calls.jsonl')
      .readAsLinesSync()
      .map((line) => jsonDecode(line) as List)
      .toList();

  test('create prompts separately for platform IDs and writes snake_case', () async {
    for (final name in ['icon.png', 'splash.png', 'logo.png']) {
      final source = fixture.file('clonify/clones/alpha/assets/$name');
      fixture.file('assets/images/$name').parent.createSync(recursive: true);
      source.copySync(fixture.file('assets/images/$name').path);
    }
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields:\n  - name: is_client_account\n    type: bool\n',
    );
    final process = await fixture.start(['create']);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    process.stdin.write(
      [
        'gamma',
        '',
        '',
        'com.example.gamma',
        'com.example.gamma.ios',
        'Gamma',
        '1.0.0+1',
        'icon.png',
        'splash.png',
        '',
        'logo.png',
        '',
        'n',
        '',
      ].join('\n'),
    );
    await process.stdin.close();
    expect(
      await process.exitCode.timeout(const Duration(seconds: 15)),
      0,
      reason: '${await output} ${await errors}',
    );
    final config = jsonDecode(
      fixture.file('clonify/clones/gamma/config.json').readAsStringSync(),
    ) as Map;
    expect(config['android_package_name'], 'com.example.gamma');
    expect(config['ios_package_name'], 'com.example.gamma.ios');
    expect(config.containsKey('base_url'), isFalse);
    expect(config.containsKey('is_client_account'), isFalse);
    expect(
      config.keys.where((key) => RegExp('[A-Z]').hasMatch(key as String)),
      isEmpty,
    );
    success(
      await fixture.run(['configure', '--client-id', 'gamma', '--skipAll']),
    );
  });

  test(
    'separate platform IDs survive configure, repeat, build and upload',
    () async {
      fixture.profile(
        'alpha',
        changes: {
          'androidPackageName': 'com.example.alpha.android',
          'iosPackageName': 'com.example.alpha.ios',
        },
      );
      fixture.write('ios/Runner.xcodeproj/project.pbxproj', '''
PRODUCT_BUNDLE_IDENTIFIER = com.old.ios;
PRODUCT_BUNDLE_IDENTIFIER = com.old.ios.RunnerTests;
PRODUCT_BUNDLE_IDENTIFIER = com.old.ios.NotificationExtension;
''');
      fixture.file('clonify/last_client.txt').deleteSync();
      success(await fixture.run(configure));
      success(await fixture.run(['configure', '--skipAll']));
      expect(fixture.file('clonify/last_client.txt').existsSync(), isFalse);
      expect(
        fixture.file('android/app/build.gradle.kts').readAsStringSync(),
        contains('com.example.alpha.android'),
      );
      final ios = fixture
          .file('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(ios, contains('com.example.alpha.ios;'));
      expect(ios, contains('com.example.alpha.ios.RunnerTests'));
      expect(ios, contains('com.example.alpha.ios.NotificationExtension'));
      success(
        await fixture.run([
          'build',
          '--skipAll',
          if (!Platform.isMacOS) '--no-buildIpa',
        ]),
      );
      success(
        await fixture.run([
          'upload',
          '--skipAll',
          if (!Platform.isMacOS) '--no-uploadIOS',
        ]),
      );
      expect(
        fixture.file('tool-upload-android').readAsStringSync(),
        contains('com.example.alpha.android'),
      );
      if (Platform.isMacOS) {
        expect(
          fixture.file('tool-upload-ios').readAsStringSync(),
          contains('com.example.alpha.ios'),
        );
      }
      final output = await fixture.run(['which']);
      success(output);
      expect(
        '${output.stdout}',
        contains('iOS Bundle ID: com.example.alpha.ios'),
      );
    },
  );

  test(
    'explicit selection ignores a stale text marker and corrupt active receipt',
    () async {
      fixture.write('clonify/last_client.txt', '../../wrong');
      fixture.write('clonify/active_profile.json', '{broken');
      success(
        await fixture.run(['configure', '--client-id', 'alpha', '--skipAll']),
      );
      success(await fixture.run(buildAndroid));
      expect(
        fixture.file('clonify/last_client.txt').readAsStringSync(),
        '../../wrong',
      );
    },
  );

  test(
    'one profile is inferred; multiple unconfigured profiles require selection',
    () async {
      fixture.file('clonify/last_client.txt').deleteSync();
      final ambiguous = await fixture.run(['configure', '--skipAll']);
      expect(ambiguous.exitCode, 1);
      expect('${ambiguous.stderr}', contains('--clientId'));
      fixture
          .file('clonify/clones/beta/config.json')
          .parent
          .deleteSync(recursive: true);
      success(await fixture.run(['configure', '--skipAll']));
      success(await fixture.run(['build', '--skipAll', '--no-buildIpa']));
    },
  );

  test('minimal snake_case profile configures without optional integrations or licenses', () async {
    fixture.write(
      'clonify/clones/alpha/config.json',
      jsonEncode({
        'client_id': 'alpha',
        'android_package_name': 'com.example.alpha',
        'ios_package_name': 'com.example.alpha.ios',
        'app_name': 'Alpha',
        'version': '2.1.0+42',
        'logo': 'logo.png',
        'launcher_icon': 'icon.png',
        'splash_screen': 'splash.png',
      }),
    );
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync().replaceAll('enabled: false', 'enabled: true')}\ncustom_fields:\n  - name: is_client_account\n    type: bool\n',
    );
    fixture.write(
      'android/app/src/main/AndroidManifest.xml',
      '<manifest><application android:label="Old"><meta-data android:name="com.transistorsoft.locationmanager.license" android:value="OLD" /></application></manifest>',
    );
    fixture.write(
      'ios/Runner/Info.plist',
      '<plist><dict><key>CFBundleDisplayName</key><string>Old</string><key>CFBundleName</key><string>Old</string><key>TSLocationManagerLicense</key><string>OLD</string></dict></plist>',
    );
    success(
      await fixture.run([
        'configure',
        '--client-id',
        'alpha',
        '--skipVersionUpdate',
      ]),
    );
    expect(
      fixture.file('pubspec.yaml').readAsStringSync(),
      contains('2.1.0+42'),
    );
    expect(
      fixture
          .file('android/app/src/main/AndroidManifest.xml')
          .readAsStringSync(),
      isNot(contains('locationmanager.license')),
    );
    expect(
      fixture.file('ios/Runner/Info.plist').readAsStringSync(),
      isNot(contains('TSLocationManagerLicense')),
    );
    expect(
      calls().any(
        (call) => ['flutterfire', 'firebase', 'shorebird'].contains(call.first),
      ),
      isFalse,
    );
    success(await fixture.run(['build', '--skipAll', '--no-buildIpa']));
  });

  test('custom fields and colors retain identity after canonical profile migration', () async {
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields:\n  - name: is_client_account\n    type: bool\n',
    );
    fixture.profile(
      'alpha',
      changes: {
        'isClientAccount': true,
        'colors': [
          {'name': 'accentColor', 'color': 'AABBCC'},
        ],
      },
    );
    success(await fixture.run(configure));
    final disk = jsonDecode(
      fixture.file('clonify/clones/alpha/config.json').readAsStringSync(),
    ) as Map;
    expect(disk['is_client_account'], true);
    expect(disk['colors'][0]['name'], 'accent_color');
    expect(disk.containsKey('packageName'), isFalse);
    final generated = fixture
        .file('lib/generated/clone_configs.dart')
        .readAsStringSync();
    expect(generated, contains('static const bool isClientAccount = true;'));
    expect(
      generated,
      contains('static const accentColor = Color(0xFFAABBCC);'),
    );
    success(await fixture.run(buildAndroid));
    success(await fixture.run(configure));
    success(await fixture.run(buildAndroid));
  });

  test(
    'Firebase online arguments, cache and restore use separate IDs',
    () async {
      fixture.write(
        'clonify/clonify_settings.yaml',
        fixture
            .file('clonify/clonify_settings.yaml')
            .readAsStringSync()
            .replaceFirst('enabled: false', 'enabled: true'),
      );
      fixture.profile(
        'alpha',
        changes: {
          'iosPackageName': 'com.example.alpha.ios',
          'firebaseProjectId': 'project-a',
        },
      );
      final fresh = firebaseManagerFixture(
        projectId: 'project-a',
        packageName: 'com.example.alpha',
        iosPackageName: 'com.example.alpha.ios',
      );
      fixture.write('tool-firebase-fixture.json', jsonEncode(fresh));
      success(
        await fixture.run([
          'configure',
          '--client-id',
          'alpha',
          '--skipVersionUpdate',
          '--refreshFirebase',
        ]),
      );
      final invocation = calls().singleWhere(
        (call) => call.first == 'flutterfire',
      );
      expect(
        invocation[invocation.indexOf('--android-package-name') + 1],
        'com.example.alpha',
      );
      expect(
        invocation[invocation.indexOf('--ios-bundle-id') + 1],
        'com.example.alpha.ios',
      );
      fixture.file('lib/firebase_options.dart').deleteSync();
      success(await fixture.run(configure));
      expect(
        calls().where((call) => call.first == 'flutterfire'),
        hasLength(1),
      );
      success(await fixture.run(buildAndroid));
      fixture.profile(
        'alpha',
        changes: {
          'iosPackageName': 'com.example.alpha.wrong',
          'firebaseProjectId': 'project-a',
        },
      );
      final before = fixture.snapshot();
      final result = await fixture.run(configure);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('iOS bundle ID'));
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'Shorebird validates the selected platform with independent IDs',
    () async {
      fixture.write(
        'clonify/clonify_settings.yaml',
        fixture
            .file('clonify/clonify_settings.yaml')
            .readAsStringSync()
            .replaceFirst(
              'shorebird:\n  enabled: false',
              'shorebird:\n  enabled: true',
            ),
      );
      fixture.profile(
        'alpha',
        changes: {
          'iosPackageName': 'com.example.alpha.ios',
          'shorebirdAppId': 'test-shorebird-app',
        },
      );
      fixture.write('shorebird.yaml', 'app_id: old\n');
      for (final platform in ['android', 'ios']) {
        success(
          await fixture.run([
            'shorebird',
            '--client-id',
            'alpha',
            '--',
            'release',
            platform,
          ]),
        );
      }
      expect(calls().where((call) => call.first == 'shorebird'), hasLength(2));
    },
  );

  test(
    'skipAll reuses the selected profile for configure, build and upload',
    () async {
      success(await fixture.run(configure));
      success(await fixture.run(['configure', '--skipAll']));
      success(await fixture.run(['build', '--skipAll', '--no-buildIpa']));
      success(await fixture.run(['upload', '--skipAll', '--no-uploadIOS']));
      expect(fixture.file('tool-upload-android').existsSync(), isTrue);
    },
  );

  test(
    'failed Shorebird operation restores the entire preceding configure',
    () async {
      fixture.write(
        'clonify/clonify_settings.yaml',
        fixture
            .file('clonify/clonify_settings.yaml')
            .readAsStringSync()
            .replaceFirst(
              'shorebird:\n  enabled: false',
              'shorebird:\n  enabled: true',
            ),
      );
      fixture.profile(
        'alpha',
        changes: {'shorebirdAppId': '0448f2f7-a408-4362-a6e7-257fe3079fb8'},
      );
      fixture.write('shorebird.yaml', 'app_id: previous\n');
      final before = fixture.snapshot();
      final result = await fixture.run(
        ['shorebird', '--clientId', 'alpha', '--', 'release', 'android'],
        env: {'CLONIFY_TEST_FAIL': 'shorebird'},
      );
      expect(result.exitCode, 1);
      expect(
        '${result.stdout}${result.stderr}',
        contains('may have published remotely'),
      );
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'end of input at upload confirmation retains cancellation exit code',
    () async {
      success(await fixture.run(configure));
      final before = fixture.snapshot();
      final process = await fixture.start(['upload', '--clientId', 'alpha']);
      final stdout = process.stdout.drain<void>();
      final stderr = process.stderr.drain<void>();
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 130);
      await stdout;
      await stderr;
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'doctor and dry-run validate without project mutations or subprocesses',
    () async {
      final help = await fixture.run(['configure', '--help']);
      success(help);
      expect('${help.stdout}', contains('--client-id'));
      expect('${help.stdout}', isNot(contains('\x1b[')));
      final before = fixture.snapshot();
      success(await fixture.run(['doctor']));
      success(await fixture.run([...configure, '--dry-run']));
      expect(fixture.snapshot(), before);
      expect(fixture.file('tool-calls.jsonl').existsSync(), isFalse);
      expect(
        fixture.file('.dart_tool/clonify/operation.lock').existsSync(),
        isFalse,
      );
    },
  );

  test('missing paths fail before any profile files change', () async {
    fixture.file('clonify/clones/alpha/assets/logo.png').deleteSync();
    final before = fixture.snapshot();
    final result = await fixture.run(configure);
    expect(result.exitCode, 1);
    expect('${result.stdout}${result.stderr}', contains('logo.png'));
    expect(fixture.snapshot(), before);
    expect(fixture.file('tool-calls.jsonl').existsSync(), isFalse);
  });

  test(
    'invalid profile JSON and traversal report actionable operational errors',
    () async {
      fixture.write('clonify/clones/alpha/config.json', '{broken');
      final result = await fixture.run(configure);
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('Invalid JSON'));
      final traversal = await fixture.run([
        'configure',
        '--clientId',
        '../alpha',
        '--skipAll',
      ]);
      expect(traversal.exitCode, 1);
      expect('${traversal.stderr}', contains('Invalid client ID'));
    },
  );

  test(
    'invalid flags are usage errors and help needs no project settings',
    () async {
      fixture.file('clonify/clonify_settings.yaml').deleteSync();
      expect((await fixture.run(['configure', '--unknown'])).exitCode, 64);
      for (final args in [
        ['--help'],
        ['configure', '--help'],
        ['doctor', '--help'],
        ['firebase', 'refresh', '--help'],
        ['recover', '--help'],
      ]) {
        success(await fixture.run(args));
      }
    },
  );

  test(
    'configure records active profile and preserves custom native source',
    () async {
      final configured = await fixture.run(configure);
      success(configured);
      expect('${configured.stdout}', isNot(contains('\x1b[')));
      expect(
        '${configured.stdout}',
        contains('Generated: lib/generated/clone_configs.dart'),
      );
      expect(
        jsonDecode(
          fixture.file('clonify/active_profile.json').readAsStringSync(),
        )['clientId'],
        'alpha',
      );
      expect(
        fixture.file('android/app/build.gradle.kts').readAsStringSync(),
        contains('com.example.alpha'),
      );
      expect(
        fixture.file('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('com.example.alpha.RunnerTests'),
      );
      expect(
        fixture
            .file(
              'android/app/src/main/kotlin/com/example/alpha/MainActivity.kt',
            )
            .readAsStringSync(),
        contains('KEEP CUSTOM NATIVE CODE'),
      );
      success(await fixture.run(configure));
      expect(
        fixture
            .file(
              'android/app/src/main/kotlin/com/example/alpha/MainActivity.kt',
            )
            .readAsStringSync(),
        contains('KEEP CUSTOM NATIVE CODE'),
      );
      expect(fixture.file(recoveryJournalPath).existsSync(), isFalse);
    },
  );

  for (final stage in [
    'flutter_launcher_icons',
    'flutter_native_splash:create',
    'intl_utils:generate',
  ]) {
    test(
      '$stage failure rolls back exact local file contents and selected profile',
      () async {
        final before = fixture.snapshot();
        final result = await fixture.run(
          configure,
          env: {'CLONIFY_TEST_FAIL': stage},
        );
        expect(result.exitCode, 1);
        expect('${result.stdout}${result.stderr}', contains('exit 7'));
        expect(fixture.snapshot(), before);
        expect(fixture.file(recoveryJournalPath).existsSync(), isFalse);
      },
    );
  }

  test(
    'native rename failure propagates and restores earlier platform edits',
    () async {
      fixture.write(
        'ios/Runner.xcodeproj/project.pbxproj',
        '// malformed Xcode project: missing bundle ID',
      );
      final before = fixture.snapshot();
      final result = await fixture.run(configure);
      expect(result.exitCode, 1);
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'build uses appbundle, runs sequentially and records verified artifacts',
    () async {
      success(await fixture.run(configure));
      success(await fixture.run([...buildAndroid, '--buildApk']));
      final builds = calls().where((call) => call.first == 'flutter').toList();
      expect(builds.map((call) => call[2]), ['apk', 'appbundle']);
      final receipt = jsonDecode(
        fixture.file('.dart_tool/clonify/builds/alpha.json').readAsStringSync(),
      ) as Map;
      expect(receipt.keys, containsAll(['apk', 'appbundle']));
      success(
        await fixture.run([
          'upload',
          '--clientId',
          'alpha',
          '--skipAll',
          '--no-uploadIOS',
        ]),
      );
      expect(fixture.file('tool-upload-android').existsSync(), isTrue);
    },
  );

  test('build/upload identity checks cannot be skipped with skipAll', () async {
    success(await fixture.run(configure));
    final result = await fixture.run([
      'build',
      '--clientId',
      'beta',
      '--skipAll',
      '--no-buildIpa',
    ]);
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('selected profile'));
    expect(calls().any((call) => call.first == 'flutter'), isFalse);
  });

  test(
    'failed build and stale success never produce upload receipts',
    () async {
      success(await fixture.run(configure));
      success(await fixture.run(buildAndroid));
      final failed = await fixture.run(
        buildAndroid,
        env: {'CLONIFY_TEST_FAIL': 'flutter build'},
      );
      expect(failed.exitCode, 1);
      final upload = await fixture.run([
        'upload',
        '--clientId',
        'alpha',
        '--skipAll',
        '--no-uploadIOS',
      ]);
      expect(upload.exitCode, 1);
      expect('${upload.stderr}', contains('No verified'));
      fixture
          .file('build/app/outputs/bundle/release/app-release.aab')
          .setLastModifiedSync(DateTime(2000));
      expect(
        (await fixture.run(
          buildAndroid,
          env: {'CLONIFY_TEST_STALE': '1'},
        )).exitCode,
        1,
      );
    },
  );

  test('modified artifacts fail validation before any upload', () async {
    success(await fixture.run(configure));
    success(await fixture.run(buildAndroid));
    fixture.write(
      'build/app/outputs/bundle/release/app-release.aab',
      'different customer',
    );
    final result = await fixture.run([
      'upload',
      '--clientId',
      'alpha',
      '--skipAll',
      '--no-uploadIOS',
    ]);
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('artifact changed'));
    expect(fixture.file('tool-upload-android').existsSync(), isFalse);
  });

  test('upload failure is awaited and restores the Fastfile', () async {
    success(await fixture.run(configure));
    success(await fixture.run(buildAndroid));
    final before = fixture.file('android/fastlane/Fastfile').readAsStringSync();
    final result = await fixture.run(
      ['upload', '--clientId', 'alpha', '--skipAll', '--no-uploadIOS'],
      env: {'CLONIFY_TEST_FAIL': 'fastlane'},
    );
    expect(result.exitCode, 1);
    expect(
      fixture.file('android/fastlane/Fastfile').readAsStringSync(),
      before,
    );
    expect('${result.stderr}', contains('Remote uploads are not rolled back'));
  });

  void enableFirebase({String credential = '/missing/credential.json'}) {
    fixture.write(
      'clonify/clonify_settings.yaml',
      fixture
          .file('clonify/clonify_settings.yaml')
          .readAsStringSync()
          .replaceFirst('enabled: false', 'enabled: true'),
    );
    fixture.profile(
      'alpha',
      changes: {
        'firebaseProjectId': 'project-a',
        'firebaseServiceAccount': credential,
      },
    );
    final cached = firebaseManagerFixture(
      projectId: 'project-a',
      packageName: 'com.example.alpha',
    );
    for (final entry in cached.entries) {
      fixture.write('clonify/clones/alpha/firebase/${entry.key}', entry.value);
    }
    fixture.write('tool-firebase-fixture.json', jsonEncode(cached));
  }

  test(
    'cached Firebase switches work with an unavailable credential and no login',
    () async {
      enableFirebase();
      success(await fixture.run(configure));
      expect(
        calls().any(
          (call) => call.first == 'firebase' || call.first == 'flutterfire',
        ),
        isFalse,
      );
      expect(
        fixture.file('lib/firebase_options.dart').readAsStringSync(),
        contains('project-a'),
      );
      success(await fixture.run(['doctor', '--clientId', 'alpha']));
    },
  );

  test('Firebase refresh validates credential before changing files', () async {
    enableFirebase();
    success(await fixture.run(configure));
    final before = fixture.snapshot();
    final result = await fixture.run([
      'firebase',
      'refresh',
      '--clientId',
      'alpha',
    ]);
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('credential'));
    expect(fixture.snapshot(), before);
  });

  test(
    'Firebase-only refresh updates cache and leaves branding/version unchanged',
    () async {
      final credential = File('${fixture.root.path}/account.json')
        ..writeAsStringSync(
          jsonEncode({
            'type': 'service_account',
            'project_id': 'project-a',
            'client_email': 'test@example.iam.gserviceaccount.com',
            'private_key': 'PRIVATE_TEST_SENTINEL',
          }),
        );
      enableFirebase(credential: credential.path);
      success(await fixture.run(configure));
      final generatedBefore = fixture
          .file('lib/generated/clone_configs.dart')
          .readAsBytesSync();
      final pubspecBefore = fixture.file('pubspec.yaml').readAsBytesSync();
      final fresh = firebaseManagerFixture(
        packageName: 'com.example.alpha',
        androidId: '1:123456789:android:abcd1234',
        iosId: '1:123456789:ios:dcba1234',
      );
      fixture.write('tool-firebase-fixture.json', jsonEncode(fresh));
      final result = await fixture.run([
        'firebase',
        'refresh',
        '--clientId',
        'alpha',
      ]);
      success(result);
      expect(
        fixture.file('lib/firebase_options.dart').readAsStringSync(),
        contains('android:abcd1234'),
      );
      expect(
        fixture
            .file('clonify/clones/alpha/firebase/lib/firebase_options.dart')
            .readAsStringSync(),
        contains('android:abcd1234'),
      );
      expect(
        fixture.file('lib/generated/clone_configs.dart').readAsBytesSync(),
        generatedBefore,
      );
      expect(fixture.file('pubspec.yaml').readAsBytesSync(), pubspecBefore);
      expect(
        '${result.stdout}${result.stderr}',
        isNot(contains('PRIVATE_TEST_SENTINEL')),
      );
    },
  );

  test(
    'failed Firebase-only refresh restores active files and previous cache',
    () async {
      final credential = File('${fixture.root.path}/account.json')
        ..writeAsStringSync(
          jsonEncode({
            'type': 'service_account',
            'project_id': 'project-a',
            'client_email': 'test@example.iam.gserviceaccount.com',
            'private_key': 'PRIVATE_TEST_SENTINEL',
          }),
        );
      enableFirebase(credential: credential.path);
      success(await fixture.run(configure));
      final before = fixture.snapshot();
      final result = await fixture.run(
        ['firebase', 'refresh', '--clientId', 'alpha'],
        env: {'CLONIFY_TEST_FAIL': 'flutterfire'},
      );
      expect(result.exitCode, 1);
      expect(fixture.snapshot(), before);
    },
  );

  test(
    'skipPubUpdate leaves pubspec unchanged and blocks a mismatched build',
    () async {
      fixture.profile('alpha', changes: {'version': '2.0.0+2'});
      success(await fixture.run([...configure, '--skipPubUpdate']));
      expect(
        fixture.file('pubspec.yaml').readAsStringSync(),
        contains('version: 1.0.0+1'),
      );
      expect((await fixture.run(buildAndroid)).exitCode, 1);
    },
  );

  test(
    'iOS-only build/upload and confirmation flag select the correct platform',
    () async {
      success(await fixture.run(configure));
      success(
        await fixture.run([
          'build',
          '--clientId',
          'alpha',
          '--skipAll',
          '--no-buildAab',
          '--buildIpa',
        ]),
      );
      success(
        await fixture.run([
          'upload',
          '--clientId',
          'alpha',
          '--skipIOSUploadCheck',
          '--no-uploadAndroid',
        ]),
      );
      expect(fixture.file('tool-upload-ios').existsSync(), isTrue);
      expect(fixture.file('tool-upload-android').existsSync(), isFalse);
    },
    skip: Platform.isMacOS ? false : 'IPA builds require macOS',
  );

  test('read-only dry-run rejects incompatible flags and wrong profile field types', () async {
    final before = fixture.snapshot();
    expect(
      (await fixture.run([
        ...configure,
        '--dry-run',
        '--refreshFirebase',
        '--skipFirebaseConfigure',
      ])).exitCode,
      1,
    );
    expect(fixture.snapshot(), before);
    fixture.profile('alpha', changes: {'version': 3});
    final result = await fixture.run([...configure, '--dry-run']);
    expect(result.exitCode, 1);
    expect('${result.stderr}', contains('must be a string'));
  });

  test(
    'end of input cancels interactive commands without changing files',
    () async {
      final before = fixture.snapshot();
      final process = await fixture.start(['create']);
      final stdout = process.stdout
          .transform(const SystemEncoding().decoder)
          .join();
      final stderr = process.stderr
          .transform(const SystemEncoding().decoder)
          .join();
      await process.stdin.close();
      expect(await process.exitCode.timeout(const Duration(seconds: 10)), 130);
      await stdout;
      await stderr;
      expect(fixture.snapshot(), before);
    },
  );

  Future<void> waitForFile(String path) async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!fixture.file(path).existsSync()) {
      if (DateTime.now().isAfter(deadline)) fail('Timed out waiting for $path');
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('lock rejects a second mutation; SIGINT rolls back and kills generator children', () async {
    final before = fixture.snapshot();
    final process = await fixture.start(
      configure,
      env: {'CLONIFY_TEST_WAIT': '1', 'CLONIFY_TEST_CHILD': '1'},
    );
    final output = process.stdout.drain<void>();
    final error = process.stderr.drain<void>();
    addTearDown(() {
      process.kill(ProcessSignal.sigkill);
    });
    await waitForFile('tool-ready');
    await waitForFile('tool-worker-ready');
    final second = await fixture.run(configure);
    expect(second.exitCode, 1);
    expect('${second.stderr}', contains('Another Clonify command'));
    process.kill(ProcessSignal.sigint);
    expect(await process.exitCode.timeout(const Duration(seconds: 10)), 130);
    await output;
    await error;
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(fixture.snapshot(), before);
    expect(fixture.file(recoveryJournalPath).existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'POSIX signal test' : false);

  test('SIGKILL leaves durable recovery; recover restores without settings validation', () async {
    final before = fixture.snapshot();
    final process = await fixture.start(
      configure,
      env: {'CLONIFY_TEST_WAIT': '1'},
    );
    unawaited(process.stdout.drain<void>());
    unawaited(process.stderr.drain<void>());
    addTearDown(() {
      process.kill(ProcessSignal.sigkill);
    });
    await waitForFile('tool-ready');
    // Kill the generator too: SIGKILL cannot run cancellation handlers.
    final generatorPid = int.parse(
      fixture.file('tool-ready').readAsStringSync(),
    );
    Process.killPid(generatorPid, ProcessSignal.sigkill);
    process.kill(ProcessSignal.sigkill);
    await process.exitCode;
    expect(fixture.file(recoveryJournalPath).existsSync(), isTrue);
    final blocked = await fixture.run(configure);
    expect(blocked.exitCode, 1);
    expect('${blocked.stderr}', contains('clonify recover'));
    fixture.write('clonify/clonify_settings.yaml', 'broken settings');
    success(await fixture.run(['recover']));
    expect(fixture.snapshot(), before);
    success(await fixture.run(['recover']));
  }, skip: Platform.isWindows ? 'POSIX signal test' : false);
}
