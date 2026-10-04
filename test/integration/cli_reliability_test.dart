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

  void success(ProcessResult result) =>
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  List<List<dynamic>> calls() => fixture
      .file('tool-calls.jsonl')
      .readAsLinesSync()
      .map((line) => jsonDecode(line) as List)
      .toList();

  test(
    'doctor and dry-run validate without project mutations or subprocesses',
    () async {
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
    'configure applies profile, awaits selected marker and preserves custom native source',
    () async {
      success(await fixture.run(configure));
      expect(
        fixture.file('clonify/last_client.txt').readAsStringSync(),
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
        'PRODUCT_BUNDLE_IDENTIFIER = com.unrelated.app;',
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
      final receipt =
          jsonDecode(
                fixture
                    .file('.dart_tool/clonify/builds/alpha.json')
                    .readAsStringSync(),
              )
              as Map;
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

  test(
    'read-only dry-run rejects incompatible flags and wrong profile field types',
    () async {
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
    },
  );

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

  test(
    'lock rejects a second mutation; SIGINT rolls back and kills generator children',
    () async {
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
    },
    skip: Platform.isWindows ? 'POSIX signal test' : false,
  );

  test(
    'SIGKILL leaves durable recovery; recover restores without settings validation',
    () async {
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
    },
    skip: Platform.isWindows ? 'POSIX signal test' : false,
  );
}
