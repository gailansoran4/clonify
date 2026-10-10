import 'dart:convert';
import 'dart:io';

import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/utils/firebase_config_cache.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory project;
  setUp(() {
    project = Directory.systemTemp.createTempSync(
      'clonify_firebase_cache_test_',
    );
  });
  tearDown(() => project.deleteSync(recursive: true));

  void save(String clientId, String projectId, String packageName) {
    saveFirebaseConfiguration(
      clientId: clientId,
      firebaseProjectId: projectId,
      packageName: packageName,
      directory: project.path,
    );
  }

  bool restore(String clientId, String projectId, String packageName) {
    return restoreFirebaseConfiguration(
      clientId: clientId,
      firebaseProjectId: projectId,
      packageName: packageName,
      directory: project.path,
    );
  }

  String cachePath(String path) =>
      p.join(project.path, 'clonify/clones/customer/firebase', path);

  test('an absent cache returns false without creating project files', () {
    expect(restore('customer', 'project-a', 'com.customer.a'), isFalse);
    expect(project.listSync(), isEmpty);
  });

  test('switches two packages in the same Firebase project offline', () {
    writeFirebaseFixture(
      project.path,
      'project-a',
      'com.customer.a',
      appSuffix: 'aa11',
    );
    save('customer_a', 'project-a', 'com.customer.a');
    final customerA = firebaseOutputSnapshot(project.path);
    writeFirebaseFixture(
      project.path,
      'project-a',
      'com.customer.b',
      appSuffix: 'bb22',
    );
    save('customer_b', 'project-a', 'com.customer.b');
    final customerB = firebaseOutputSnapshot(project.path);

    expect(restore('customer_a', 'project-a', 'com.customer.a'), isTrue);
    expect(firebaseOutputSnapshot(project.path), customerA);
    expect(restore('customer_b', 'project-a', 'com.customer.b'), isTrue);
    expect(firebaseOutputSnapshot(project.path), customerB);
  });

  test('switches Firebase projects with different project numbers offline', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    save('customer_a', 'project-a', 'com.customer.a');
    final customerA = firebaseOutputSnapshot(project.path);
    writeFirebaseFixture(
      project.path,
      'project-b',
      'com.customer.b',
      sender: '987654',
      appSuffix: 'bb22',
    );
    save('customer_b', 'project-b', 'com.customer.b');

    expect(restore('customer_a', 'project-a', 'com.customer.a'), isTrue);
    expect(firebaseOutputSnapshot(project.path), customerA);
    expect(restore('customer_b', 'project-b', 'com.customer.b'), isTrue);
    assertFirebaseConfiguration(
      'project-b',
      'com.customer.b',
      directory: project.path,
    );
  });

  for (final changedField in ['project', 'package']) {
    test(
      'changed $changedField invalidates a cache before any output write',
      () {
        writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
        save('customer', 'project-a', 'com.customer.a');
        writeFirebaseFixture(
          project.path,
          'current-project',
          'com.current.app',
        );
        final before = firebaseOutputSnapshot(project.path);

        expect(
          () => restore(
            'customer',
            changedField == 'project' ? 'project-b' : 'project-a',
            changedField == 'package' ? 'com.customer.b' : 'com.customer.a',
          ),
          throwsA(isA<CustomException>()),
        );
        expect(firebaseOutputSnapshot(project.path), before);
      },
    );
  }

  for (final path in ['firebase.json', ...firebaseApplicationConfigPaths]) {
    test('a partial cache missing $path never mixes output files', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      save('customer', 'project-a', 'com.customer.a');
      File(cachePath(path)).deleteSync();
      writeFirebaseFixture(project.path, 'current-project', 'com.current.app');
      final before = firebaseOutputSnapshot(project.path);

      expect(
        () => restore('customer', 'project-a', 'com.customer.a'),
        throwsA(isA<CustomException>()),
      );
      expect(firebaseOutputSnapshot(project.path), before);
    });
  }

  test(
    'saves only Flutter metadata and preserves target deployment settings',
    () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final sourceMetadata = readFirebaseFixtureJson(
        project.path,
        'firebase.json',
      );
      sourceMetadata['hosting'] = {'public': 'build/web'};
      sourceMetadata['functions'] = {'source': 'functions'};
      sourceMetadata['firestore'] = {'rules': 'firestore.rules'};
      writeFirebaseFixtureJson(project.path, 'firebase.json', sourceMetadata);
      save('customer', 'project-a', 'com.customer.a');
      final cached = jsonDecode(
        File(cachePath('firebase.json')).readAsStringSync(),
      ) as Map;
      expect(cached.keys, ['flutter']);

      final targetMetadata = {
        'hosting': {'public': 'other/web'},
        'functions': [
          {'source': 'other-functions', 'codebase': 'main'},
        ],
        'firestore': {'rules': 'customer.rules'},
        'emulators': {
          'auth': {'port': 9099},
        },
      };
      writeFirebaseFixtureJson(project.path, 'firebase.json', targetMetadata);
      expect(restore('customer', 'project-a', 'com.customer.a'), isTrue);
      final restored = readFirebaseFixtureJson(project.path, 'firebase.json');
      expect(restored['flutter'], sourceMetadata['flutter']);
      for (final entry in targetMetadata.entries) {
        expect(restored[entry.key], entry.value);
      }
    },
  );

  test('rejects invalid target deployment JSON before copying any files', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    save('customer', 'project-a', 'com.customer.a');
    writeFirebaseFixture(project.path, 'current-project', 'com.current.app');
    File(p.join(project.path, 'firebase.json')).writeAsStringSync('{bad json');
    final before = firebaseOutputSnapshot(project.path);

    expect(
      () => restore('customer', 'project-a', 'com.customer.a'),
      throwsA(isA<CustomException>()),
    );
    expect(firebaseOutputSnapshot(project.path), before);
  });

  test(
    'does not replace a valid cache when generated files are inconsistent',
    () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      save('customer', 'project-a', 'com.customer.a');
      final cachedOptions = File(cachePath('lib/firebase_options.dart'))
          .readAsStringSync();
      writeFirebaseFixture(project.path, 'project-b', 'com.customer.b');
      final plist = File(
        p.join(project.path, 'ios/Runner/GoogleService-Info.plist'),
      );
      plist.writeAsStringSync(
        plist.readAsStringSync().replaceAll('project-b', 'project-a'),
      );

      expect(
        () => save('customer', 'project-b', 'com.customer.b'),
        throwsA(isA<CustomException>()),
      );
      expect(
        File(cachePath('lib/firebase_options.dart')).readAsStringSync(),
        cachedOptions,
      );
      expect(restore('customer', 'project-a', 'com.customer.a'), isTrue);
    },
  );

  test('can replace an existing cache with a newly validated project', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    save('customer', 'project-a', 'com.customer.a');
    writeFirebaseFixture(
      project.path,
      'project-b',
      'com.customer.b',
      sender: '987654',
    );
    save('customer', 'project-b', 'com.customer.b');
    expect(restore('customer', 'project-b', 'com.customer.b'), isTrue);
    expect(
      Directory(p.join(project.path, 'clonify/clones/customer'))
          .listSync()
          .map((file) => p.basename(file.path)),
      ['firebase'],
    );
  });

  test('refresh replaces partial and empty known cache files', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    save('customer', 'project-a', 'com.customer.a');
    File(cachePath('lib/firebase_options.dart')).writeAsStringSync('');
    File(cachePath('ios/Runner/GoogleService-Info.plist')).deleteSync();
    expect(
      () => restore('customer', 'project-a', 'com.customer.a'),
      throwsA(
        isA<CustomException>().having(
          (error) => error.message,
          'refresh guidance',
          contains('--refreshFirebase'),
        ),
      ),
    );
    save('customer', 'project-a', 'com.customer.a');
    expect(restore('customer', 'project-a', 'com.customer.a'), isTrue);
  });

  test('accepts native Android config with multiple registered packages', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    final android = readFirebaseFixtureJson(
      project.path,
      'android/app/google-services.json',
    );
    final clients = android['client'] as List;
    clients.add({
      'client_info': {
        'mobilesdk_app_id': '1:123456:android:cc33',
        'android_client_info': {'package_name': 'com.other.app'},
      },
      'api_key': [
        {'current_key': 'test-android-key'},
      ],
    });
    writeFirebaseFixtureJson(
      project.path,
      'android/app/google-services.json',
      android,
    );
    save('customer', 'project-a', 'com.customer.a');
    expect(restore('customer', 'project-a', 'com.customer.a'), isTrue);
  });

  for (final target in [
    'android metadata',
    'ios metadata',
    'dart metadata',
    'dart options',
  ]) {
    test('rejects an app ID mismatch in $target without output writes', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      save('customer', 'project-a', 'com.customer.a');
      final path = target == 'dart options'
          ? 'lib/firebase_options.dart'
          : 'firebase.json';
      final file = File(cachePath(path));
      if (target == 'dart options') {
        file.writeAsStringSync(
          file.readAsStringSync().replaceAll('android:aa11', 'android:dd44'),
        );
      } else {
        final metadata =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final platforms = metadata['flutter']['platforms'] as Map;
        if (target == 'dart metadata') {
          platforms['dart']['lib/firebase_options.dart']['configurations']['android'] =
              '1:123456:android:dd44';
        } else {
          final platform = target.startsWith('android') ? 'android' : 'ios';
          platforms[platform]['default']['appId'] = '1:123456:$platform:dd44';
        }
        file.writeAsStringSync(jsonEncode(metadata));
      }
      writeFirebaseFixture(project.path, 'current-project', 'com.current.app');
      final before = firebaseOutputSnapshot(project.path);
      expect(
        () => restore('customer', 'project-a', 'com.customer.a'),
        throwsA(isA<CustomException>()),
      );
      expect(firebaseOutputSnapshot(project.path), before);
    });
  }

  for (final path in ['firebase.json', 'android/app/google-services.json']) {
    test('rejects corrupt JSON at $path before output writes', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      save('customer', 'project-a', 'com.customer.a');
      File(cachePath(path)).writeAsStringSync('{broken');
      final before = firebaseOutputSnapshot(project.path);
      expect(
        () => restore('customer', 'project-a', 'com.customer.a'),
        throwsA(isA<CustomException>()),
      );
      expect(firebaseOutputSnapshot(project.path), before);
    });
  }

  for (final platform in ['android', 'ios', 'dart']) {
    test('rejects mismatched sender IDs in $platform configuration', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final path = platform == 'android'
          ? 'android/app/google-services.json'
          : platform == 'ios'
          ? 'ios/Runner/GoogleService-Info.plist'
          : 'lib/firebase_options.dart';
      final options = File(p.join(project.path, path));
      final content = options.readAsStringSync();
      options.writeAsStringSync(
        platform == 'android'
            ? content.replaceFirst(
                '"project_number": "123456"',
                '"project_number": "999999"',
              )
            : platform == 'ios'
            ? content.replaceFirst(
                '<key>GCM_SENDER_ID</key><string>123456</string>',
                '<key>GCM_SENDER_ID</key><string>999999</string>',
              )
            : content.replaceAll(
                "messagingSenderId: '123456'",
                "messagingSenderId: '999999'",
              ),
      );
      expect(
        () => save('customer', 'project-a', 'com.customer.a'),
        throwsA(isA<CustomException>()),
      );
      expect(Directory(p.join(project.path, 'clonify')).existsSync(), isFalse);
    });
  }

  test('rejects unexpected metadata output paths', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    final metadata = readFirebaseFixtureJson(project.path, 'firebase.json');
    metadata['flutter']['platforms']['ios']['default']['fileOutput'] =
        'ios/Other/GoogleService-Info.plist';
    writeFirebaseFixtureJson(project.path, 'firebase.json', metadata);
    expect(
      () => save('customer', 'project-a', 'com.customer.a'),
      throwsA(isA<CustomException>()),
    );
  });

  for (final invalid in [
    'unexpected',
    'private_key',
    'service_account',
    'deployment metadata',
    'symlink',
  ]) {
    test('rejects $invalid in the public Firebase cache', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      save('customer', 'project-a', 'com.customer.a');
      if (invalid == 'unexpected') {
        File(cachePath('credential.json')).writeAsStringSync('{}');
      } else if (invalid == 'symlink') {
        final cached = File(cachePath('lib/firebase_options.dart'));
        cached.deleteSync();
        Link(cached.path)
            .createSync(p.join(project.path, 'lib/firebase_options.dart'));
      } else {
        final file = File(cachePath('firebase.json'));
        final metadata =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        metadata[invalid == 'deployment metadata'
            ? 'hosting'
            : invalid] = invalid == 'service_account'
            ? {'type': 'service_account'}
            : 'invalid';
        file.writeAsStringSync(jsonEncode(metadata));
      }
      final before = firebaseOutputSnapshot(project.path);
      expect(
        () => restore('customer', 'project-a', 'com.customer.a'),
        throwsA(isA<CustomException>()),
      );
      expect(firebaseOutputSnapshot(project.path), before);
    });
  }

  test(
    'parses XML entities and rejects malformed and duplicate plist fields',
    () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final plist = File(
        p.join(project.path, 'ios/Runner/GoogleService-Info.plist'),
      );
      final original = plist.readAsStringSync();
      plist.writeAsStringSync(
        original.replaceAll('com.customer.a', 'com.customer.&#97;'),
      );
      assertFirebaseConfiguration(
        'project-a',
        'com.customer.a',
        directory: project.path,
      );
      for (final invalid in [
        original.replaceAll('com.customer.a', 'com.customer.&unknown;'),
        original.replaceAll(
          '</dict>',
          '<key>PROJECT_ID</key><string>project-a</string></dict>',
        ),
        original.replaceAll('</dict>', '<malformed></dict>'),
      ]) {
        plist.writeAsStringSync(invalid);
        expect(
          () => save('customer', 'project-a', 'com.customer.a'),
          throwsA(isA<CustomException>()),
        );
      }
    },
  );

  test('commented Dart options cannot validate missing active options', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    final options = File(p.join(project.path, 'lib/firebase_options.dart'));
    options.writeAsStringSync('/* ${options.readAsStringSync()} */');
    expect(
      () => save('customer', 'project-a', 'com.customer.a'),
      throwsA(isA<CustomException>()),
    );
  });

  test(
    'supports custom Firebase metadata paths without caching deployment JSON',
    () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final metadata = File(p.join(project.path, 'firebase.json'));
      metadata.renameSync(p.join(project.path, 'firebase-custom.json'));
      saveFirebaseConfiguration(
        clientId: 'customer',
        firebaseProjectId: 'project-a',
        packageName: 'com.customer.a',
        directory: project.path,
        firebaseSettingsFilePath: 'firebase-custom.json',
      );
      expect(
        restoreFirebaseConfiguration(
          clientId: 'customer',
          firebaseProjectId: 'project-a',
          packageName: 'com.customer.a',
          directory: project.path,
          firebaseSettingsFilePath: 'firebase-custom.json',
        ),
        isTrue,
      );
      expect(File(p.join(project.path, 'firebase.json')).existsSync(), isFalse);
    },
  );

  test('rejects client IDs which would escape the clone directory', () {
    writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
    expect(
      () => save('../outside', 'project-a', 'com.customer.a'),
      throwsA(isA<CustomException>()),
    );
    expect(
      () => restore('../outside', 'project-a', 'com.customer.a'),
      throwsA(isA<CustomException>()),
    );
  });

  group('syncFlutterFireMetadata', () {
    test('creates custom settings using only root Flutter metadata', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final metadata = readFirebaseFixtureJson(project.path, 'firebase.json');
      metadata['hosting'] = {'public': 'root-hosting'};
      writeFirebaseFixtureJson(project.path, 'firebase.json', metadata);
      final rootBefore = File(p.join(project.path, 'firebase.json'))
          .readAsStringSync();

      syncFlutterFireMetadata(
        directory: project.path,
        firebaseSettingsFilePath: 'settings/custom-firebase.json',
      );

      final configured = readFirebaseFixtureJson(
        project.path,
        'settings/custom-firebase.json',
      );
      expect(configured, {'flutter': metadata['flutter']});
      expect(
        File(p.join(project.path, 'firebase.json')).readAsStringSync(),
        rootBefore,
      );
      saveFirebaseConfiguration(
        clientId: 'customer',
        firebaseProjectId: 'project-a',
        packageName: 'com.customer.a',
        directory: project.path,
        firebaseSettingsFilePath: 'settings/custom-firebase.json',
      );
      expect(restore('customer', 'project-a', 'com.customer.a'), isTrue);
    });

    test('preserves custom deployment sections and replaces stale Flutter metadata', () {
      writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
      final expectedFlutter = readFirebaseFixtureJson(
        project.path,
        'firebase.json',
      )['flutter'];
      final configured = {
        'hosting': {'public': 'customer-hosting'},
        'functions': [
          {'source': 'customer-functions', 'codebase': 'main'},
        ],
        'firestore': {'rules': 'customer.rules'},
        'flutter': {'platforms': 'old-metadata'},
      };
      writeFirebaseFixtureJson(
        project.path,
        'firebase-custom.json',
        configured,
      );

      syncFlutterFireMetadata(
        directory: project.path,
        firebaseSettingsFilePath: 'firebase-custom.json',
      );

      expect(readFirebaseFixtureJson(project.path, 'firebase-custom.json'), {
        ...configured,
        'flutter': expectedFlutter,
      });
    });

    for (final invalid in [
      'malformed custom',
      'private custom',
      'private root',
      'malformed root',
      'missing Flutter',
    ]) {
      test('rejects $invalid without changing existing metadata files', () {
        writeFirebaseFixture(project.path, 'project-a', 'com.customer.a');
        writeFirebaseFixtureJson(project.path, 'firebase-custom.json', {
          'hosting': {'public': 'customer'},
        });
        final root = File(p.join(project.path, 'firebase.json'));
        final configured = File(p.join(project.path, 'firebase-custom.json'));
        if (invalid == 'malformed custom') {
          configured.writeAsStringSync('{bad-json');
        } else if (invalid == 'private custom') {
          configured.writeAsStringSync('{"private_key":"must-never-copy"}');
        } else if (invalid == 'private root') {
          final metadata = readFirebaseFixtureJson(
            project.path,
            'firebase.json',
          );
          metadata['credential'] = {'type': 'service_account'};
          writeFirebaseFixtureJson(project.path, 'firebase.json', metadata);
        } else if (invalid == 'malformed root') {
          root.writeAsStringSync('{bad-json');
        } else {
          root.writeAsStringSync('{"hosting":{"public":"root"}}');
        }
        final rootBefore = root.readAsStringSync();
        final customBefore = configured.readAsStringSync();

        expect(
          () => syncFlutterFireMetadata(
            directory: project.path,
            firebaseSettingsFilePath: 'firebase-custom.json',
          ),
          throwsA(isA<CustomException>()),
        );
        expect(root.readAsStringSync(), rootBefore);
        expect(configured.readAsStringSync(), customBefore);
      });
    }

    test('root settings are a no-op even when no metadata exists', () {
      syncFlutterFireMetadata(
        directory: project.path,
        firebaseSettingsFilePath: './firebase.json',
      );
      expect(project.listSync(), isEmpty);
      final root = File(p.join(project.path, 'firebase.json'))
        ..writeAsStringSync('{intentionally untouched');
      syncFlutterFireMetadata(
        directory: project.path,
        firebaseSettingsFilePath: root.path,
      );
      expect(root.readAsStringSync(), '{intentionally untouched');
    });
  });
}

Map<String, String> firebaseOutputSnapshot(String directory) {
  return {
    for (final path in ['firebase.json', ...firebaseApplicationConfigPaths])
      path: File(p.join(directory, path)).readAsStringSync(),
  };
}

Map<String, dynamic> readFirebaseFixtureJson(String directory, String path) {
  return jsonDecode(File(p.join(directory, path)).readAsStringSync())
      as Map<String, dynamic>;
}

void writeFirebaseFixtureJson(
  String directory,
  String path,
  Map<String, dynamic> value,
) {
  File(p.join(directory, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(value)}\n',
    );
}

void writeFirebaseFixture(
  String directory,
  String projectId,
  String packageName, {
  String sender = '123456',
  String appSuffix = 'aa11',
}) {
  final androidAppId = '1:$sender:android:$appSuffix';
  final iosAppId = '1:$sender:ios:bb$appSuffix';
  writeFirebaseFixtureJson(directory, 'firebase.json', {
    'flutter': {
      'platforms': {
        'android': {
          'default': {
            'projectId': projectId,
            'appId': androidAppId,
            'fileOutput': 'android/app/google-services.json',
          },
        },
        'ios': {
          'default': {
            'projectId': projectId,
            'appId': iosAppId,
            'uploadDebugSymbols': true,
            'fileOutput': 'ios/Runner/GoogleService-Info.plist',
          },
        },
        'dart': {
          'lib/firebase_options.dart': {
            'projectId': projectId,
            'configurations': {'android': androidAppId, 'ios': iosAppId},
          },
        },
      },
    },
  });
  writeFirebaseFixtureJson(directory, 'android/app/google-services.json', {
    'project_info': {'project_id': projectId, 'project_number': sender},
    'client': [
      {
        'client_info': {
          'mobilesdk_app_id': androidAppId,
          'android_client_info': {'package_name': packageName},
        },
        'api_key': [
          {'current_key': 'test-android-key'},
        ],
      },
    ],
    'configuration_version': '1',
  });
  File(p.join(directory, 'ios/Runner/GoogleService-Info.plist'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>PROJECT_ID</key><string>$projectId</string>
<key>BUNDLE_ID</key><string>$packageName</string>
<key>GCM_SENDER_ID</key><string>$sender</string>
<key>GOOGLE_APP_ID</key><string>$iosAppId</string>
<key>API_KEY</key><string>test-ios-key</string>
<key>IS_GCM_ENABLED</key><true/>
<key>IS_ADS_ENABLED</key><false></false>
</dict></plist>
''');
  File(p.join(directory, 'lib/firebase_options.dart'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''import 'package:firebase_core/firebase_core.dart';
class DefaultFirebaseOptions {
  static FirebaseOptions currentPlatform() => android;
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'test-android-key',
    appId: '$androidAppId',
    messagingSenderId: '$sender',
    projectId: '$projectId',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'test-ios-key',
    appId: '$iosAppId',
    messagingSenderId: '$sender',
    projectId: '$projectId',
    iosBundleId: '$packageName',
  );
}
''');
}
