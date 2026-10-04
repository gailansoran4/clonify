import 'dart:convert';
import 'dart:io';

import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/utils/file_tree_checkpoint.dart';
import 'package:clonify/utils/firebase_config_cache.dart';
import 'package:clonify/utils/firebase_manager.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../silence_logs.dart';
import '../support/firebase_fixture.dart';

void main() {
  silenceClonifyLogsForTests();

  late Directory root;
  late Directory project;
  late File credentialFile;
  late String originalDirectory;
  final logs = <String>[];
  void captureLog(LogEvent event) => logs.add(event.message.toString());

  setUp(() {
    originalDirectory = Directory.current.path;
    root = Directory.systemTemp.createTempSync('clonify_firebase_manager_');
    project = Directory(p.join(root.path, 'flutter_app'))..createSync();
    credentialFile = File(p.join(root.path, 'service-account.json'))
      ..writeAsStringSync(
        jsonEncode({
          'type': 'service_account',
          'project_id': 'different-credential-owner-project',
          'client_email': 'test@example.iam.gserviceaccount.com',
          'private_key': 'PRIVATE_SENTINEL',
        }),
      );
    Directory.current = project;
    File('clonify/clonify_settings.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
firebase:
  enabled: true
  settings_file: firebase.json
fastlane:
  enabled: false
  settings_file: ''
''');
    logs.clear();
    Logger.addLogListener(captureLog);
  });

  tearDown(() {
    Logger.removeLogListener(captureLog);
    Directory.current = originalDirectory;
    root.deleteSync(recursive: true);
  });

  test(
    'first setup isolates credentials and subsequent switches are offline',
    () async {
      var commandCalls = 0;
      String? isolatedConfigDirectory;
      final fixture = firebaseManagerFixture();

      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: credentialFile.path,
        configureCommand: (arguments, environment) async {
          commandCalls++;
          expect(arguments, [
            'configure',
            '--project',
            'project-a',
            '--yes',
            '--platforms',
            'android,ios',
            '--ios-bundle-id',
            'com.test.clienta',
            '--android-package-name',
            'com.test.clienta',
            '--service-account',
            credentialFile.resolveSymbolicLinksSync(),
          ]);
          expect(
            environment!['GOOGLE_APPLICATION_CREDENTIALS'],
            credentialFile.resolveSymbolicLinksSync(),
          );
          expect(environment['FIREBASE_TOKEN'], isEmpty);
          isolatedConfigDirectory = environment['XDG_CONFIG_HOME'];
          expect(Directory(isolatedConfigDirectory!).existsSync(), isTrue);
          expect(
            File(
              p.join(
                isolatedConfigDirectory!,
                'configstore',
                'firebase-tools.json',
              ),
            ).existsSync(),
            isFalse,
          );
          writeFirebaseManagerFixture(fixture);
          return ProcessResult(1, 0, '', '');
        },
      );

      final cache = firebaseConfigurationCacheDirectory('client_a');
      expect(cache.existsSync(), isTrue);
      expect(Directory(isolatedConfigDirectory!).existsSync(), isFalse);
      expect(commandCalls, 1);
      expect(
        firebaseManagerFileContents(directory: cache.path).values.join(),
        isNot(contains('PRIVATE_SENTINEL')),
      );

      writeFirebaseManagerFixture(
        firebaseManagerFixture(projectId: 'project-b'),
      );
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
        configureCommand: (arguments, environment) async {
          commandCalls++;
          throw StateError('cached switches must not run a command');
        },
      );

      expect(commandCalls, 1);
      assertFirebaseConfiguration('project-a', 'com.test.clienta');
      for (final path in firebaseApplicationConfigPaths) {
        expect(File(path).readAsStringSync(), fixture[path]);
      }
    },
  );

  test(
    'refresh preserves the existing currentPlatform function in its cache',
    () async {
      final existing = firebaseManagerFixture();
      existing['lib/firebase_options.dart'] =
          existing['lib/firebase_options.dart']!.replaceFirst(
            'class DefaultFirebaseOptions {',
            'class DefaultFirebaseOptions {\n'
                '  static FirebaseOptions currentPlatform() { return android; }',
          );
      writeFirebaseManagerFixture(existing);

      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: credentialFile.path,
        refresh: true,
        configureCommand: (arguments, environment) async {
          final generated = firebaseManagerFixture();
          generated['lib/firebase_options.dart'] =
              generated['lib/firebase_options.dart']!.replaceFirst(
                'class DefaultFirebaseOptions {',
                'class DefaultFirebaseOptions {\n'
                    '  static FirebaseOptions get currentPlatform { return android; }',
              );
          writeFirebaseManagerFixture(generated);
          return ProcessResult(1, 0, '', '');
        },
      );

      final options = File('lib/firebase_options.dart').readAsStringSync();
      expect(options, contains('static FirebaseOptions currentPlatform()'));
      expect(options, isNot(contains('get currentPlatform')));
      final cache = firebaseConfigurationCacheDirectory('client_a');
      expect(
        File(
          p.join(cache.path, 'lib/firebase_options.dart'),
        ).readAsStringSync(),
        options,
      );

      File('lib/firebase_options.dart').deleteSync();
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
        skip: true,
        configureCommand: (arguments, environment) async {
          throw StateError('restoring the function accessor must be offline');
        },
      );
      expect(File('lib/firebase_options.dart').readAsStringSync(), options);
    },
  );

  test(
    'failed forced refresh preserves the cache and transaction restores files',
    () async {
      writeFirebaseManagerFixture(firebaseManagerFixture());
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        skip: true,
      );
      final cache = firebaseConfigurationCacheDirectory('client_a');
      final oldCache = firebaseManagerFileContents(directory: cache.path);
      final oldOutputs = firebaseManagerFileContents();
      logs.clear();

      await expectLater(
        runConfigureTransaction(() async {
          await addFirebaseToApp(
            clientId: 'client_a',
            firebaseProjectId: 'project-a',
            packageName: 'com.test.clienta',
            firebaseServiceAccount: credentialFile.path,
            refresh: true,
            configureCommand: (arguments, environment) async {
              writeFirebaseManagerFixture(
                firebaseManagerFixture(projectId: 'half-written-project'),
              );
              return ProcessResult(1, 2, '', 'failed refresh');
            },
          );
        }),
        throwsA(
          isA<ConfigureRolledBackException>().having(
            (error) => error.toString(),
            'failure',
            contains('FlutterFire configuration failed (exit 2)'),
          ),
        ),
      );

      expect(firebaseManagerFileContents(), oldOutputs);
      expect(firebaseManagerFileContents(directory: cache.path), oldCache);
      expect(
        logs.any((line) => line.contains('✅ Firebase configuration saved')),
        isFalse,
      );
    },
  );

  test(
    'nonzero FlutterFire exit cannot report success or create a cache',
    () async {
      await expectLater(
        addFirebaseToApp(
          clientId: 'new_client',
          firebaseProjectId: 'project-a',
          packageName: 'com.test.clienta',
          firebaseServiceAccount: credentialFile.path,
          configureCommand: (arguments, environment) async {
            writeFirebaseManagerFixture(firebaseManagerFixture());
            return ProcessResult(1, 7, 'PRIVATE_SENTINEL', 'PRIVATE_SENTINEL');
          },
        ),
        throwsA(
          isA<CustomException>()
              .having(
                (error) => error.message,
                'exit status',
                contains('exit 7'),
              )
              .having(
                (error) => error.message,
                'redacted output',
                isNot(contains('PRIVATE_SENTINEL')),
              ),
        ),
      );

      expect(
        firebaseConfigurationCacheDirectory('new_client').existsSync(),
        isFalse,
      );
      expect(logs.any((line) => line.contains('✅')), isFalse);
    },
  );

  test(
    'successful exit with incomplete outputs cannot create a cache',
    () async {
      await expectLater(
        addFirebaseToApp(
          clientId: 'new_client',
          firebaseProjectId: 'project-a',
          packageName: 'com.test.clienta',
          firebaseServiceAccount: credentialFile.path,
          configureCommand: (arguments, environment) async {
            final fixture = firebaseManagerFixture()
              ..remove('ios/Runner/GoogleService-Info.plist');
            writeFirebaseManagerFixture(fixture);
            return ProcessResult(1, 0, '', '');
          },
        ),
        throwsA(isA<CustomException>()),
      );
      expect(
        firebaseConfigurationCacheDirectory('new_client').existsSync(),
        isFalse,
      );
      expect(logs.any((line) => line.contains('✅')), isFalse);
    },
  );

  test(
    'skip accepts matching current files and restores matching cache offline',
    () async {
      var commandCalls = 0;
      Future<ProcessResult> failOnline(
        List<String> arguments,
        Map<String, String>? environment,
      ) async {
        commandCalls++;
        throw StateError('skip must never run online');
      }

      writeFirebaseManagerFixture(firebaseManagerFixture());
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
        skip: true,
        configureCommand: failOnline,
      );
      expect(
        firebaseConfigurationCacheDirectory('client_a').existsSync(),
        isTrue,
      );

      for (final path in [...firebaseApplicationConfigPaths, 'firebase.json']) {
        File(path).deleteSync();
      }
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
        skip: true,
        configureCommand: failOnline,
      );

      expect(commandCalls, 0);
      assertFirebaseConfiguration('project-a', 'com.test.clienta');
    },
  );

  test(
    'skip rejects missing or mismatched configuration before any online call',
    () async {
      var commandCalls = 0;
      for (final hasWrongConfiguration in [false, true]) {
        if (hasWrongConfiguration) {
          writeFirebaseManagerFixture(
            firebaseManagerFixture(projectId: 'wrong-project'),
          );
        }
        await expectLater(
          addFirebaseToApp(
            clientId: 'client_a',
            firebaseProjectId: 'project-a',
            packageName: 'com.test.clienta',
            firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
            skip: true,
            configureCommand: (arguments, environment) async {
              commandCalls++;
              return ProcessResult(1, 0, '', '');
            },
          ),
          throwsA(isA<CustomException>()),
        );
      }

      expect(commandCalls, 0);
      expect(
        firebaseConfigurationCacheDirectory('client_a').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'refresh and skip reject together even when configuration matches',
    () async {
      writeFirebaseManagerFixture(firebaseManagerFixture());
      var commandCalls = 0;

      await expectLater(
        addFirebaseToApp(
          clientId: 'client_a',
          firebaseProjectId: 'project-a',
          packageName: 'com.test.clienta',
          refresh: true,
          skip: true,
          configureCommand: (arguments, environment) async {
            commandCalls++;
            return ProcessResult(1, 0, '', '');
          },
        ),
        throwsA(
          isA<CustomException>().having(
            (error) => error.message,
            'flags',
            contains('Cannot combine'),
          ),
        ),
      );

      expect(commandCalls, 0);
      expect(
        firebaseConfigurationCacheDirectory('client_a').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'two customer packages in one project restore their own app IDs offline',
    () async {
      final clientA = firebaseManagerFixture();
      final clientB = firebaseManagerFixture(
        packageName: 'com.test.clientb',
        androidId: '1:123456789:android:aaa2',
        iosId: '1:123456789:ios:bbb2',
      );
      writeFirebaseManagerFixture(clientA);
      await addFirebaseToApp(
        clientId: 'client_a',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clienta',
        skip: true,
      );
      writeFirebaseManagerFixture(clientB);
      await addFirebaseToApp(
        clientId: 'client_b',
        firebaseProjectId: 'project-a',
        packageName: 'com.test.clientb',
        skip: true,
      );

      for (final client in [
        (
          clientId: 'client_a',
          packageName: 'com.test.clienta',
          fixture: clientA,
        ),
        (
          clientId: 'client_b',
          packageName: 'com.test.clientb',
          fixture: clientB,
        ),
      ]) {
        final (:clientId, :packageName, :fixture) = client;
        await addFirebaseToApp(
          clientId: clientId,
          firebaseProjectId: 'project-a',
          packageName: packageName,
          firebaseServiceAccount: 'env:MISSING_CREDENTIAL_REFERENCE',
          skip: true,
          configureCommand: (arguments, environment) async {
            throw StateError('cached customer switches must be offline');
          },
        );
        assertFirebaseConfiguration('project-a', packageName);
        for (final path in firebaseApplicationConfigPaths) {
          expect(File(path).readAsStringSync(), fixture[path]);
        }
      }
    },
  );
}

void writeFirebaseManagerFixture(Map<String, String> fixture) {
  for (final entry in fixture.entries) {
    File(entry.key)
      ..createSync(recursive: true)
      ..writeAsStringSync(entry.value);
  }
}

Map<String, String> firebaseManagerFileContents({String directory = '.'}) {
  return {
    for (final path in [...firebaseApplicationConfigPaths, 'firebase.json'])
      path: File(p.join(directory, path)).readAsStringSync(),
  };
}
