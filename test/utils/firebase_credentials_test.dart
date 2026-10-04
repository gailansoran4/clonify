import 'dart:convert';
import 'dart:io';

import 'package:clonify/utils/firebase_credentials.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;
  late Directory project;
  late File credentialFile;
  late Map<String, dynamic> credential;

  setUp(() {
    root = Directory.systemTemp.createTempSync('clonify_credentials_test_');
    project = Directory(p.join(root.path, 'flutter_app'))..createSync();
    credential = {
      'type': 'service_account',
      'project_id': 'credential-owner-project',
      'client_email': 'test@example.iam.gserviceaccount.com',
      'private_key': 'PRIVATE_SENTINEL',
    };
    credentialFile = File(p.join(root.path, 'service-account.json'))
      ..writeAsStringSync(jsonEncode(credential));
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  group('resolveFirebaseServiceAccount', () {
    test('retains legacy login with no credential reference', () {
      expect(resolveFirebaseServiceAccount(environment: {}), isNull);
    });

    test('resolves an absolute file outside the Flutter project', () {
      expect(
        resolveFirebaseServiceAccount(
          reference: credentialFile.path,
          projectDirectory: project.path,
          environment: {},
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('resolves a portable environment reference', () {
      expect(
        resolveFirebaseServiceAccount(
          reference: 'env:CUSTOMER_FIREBASE',
          projectDirectory: project.path,
          environment: {'CUSTOMER_FIREBASE': credentialFile.path},
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('expands a home-relative credential reference', () {
      expect(
        resolveFirebaseServiceAccount(
          reference: '~/service-account.json',
          projectDirectory: project.path,
          environment: {'HOME': root.path},
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('uses Clonify environment credentials before ADC', () {
      expect(
        resolveFirebaseServiceAccount(
          projectDirectory: project.path,
          environment: {
            'CLONIFY_FIREBASE_SERVICE_ACCOUNT': credentialFile.path,
            'GOOGLE_APPLICATION_CREDENTIALS': '/does/not/exist.json',
          },
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('uses ADC when a clone does not specify credentials', () {
      expect(
        resolveFirebaseServiceAccount(
          projectDirectory: project.path,
          environment: {'GOOGLE_APPLICATION_CREDENTIALS': credentialFile.path},
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('a clone reference overrides environment defaults', () {
      expect(
        resolveFirebaseServiceAccount(
          reference: credentialFile.path,
          projectDirectory: project.path,
          environment: {
            'CLONIFY_FIREBASE_SERVICE_ACCOUNT': '/does/not/exist.json',
          },
        ),
        credentialFile.resolveSymbolicLinksSync(),
      );
    });

    test('rejects an unset environment reference instead of falling back', () {
      expect(
        () => resolveFirebaseServiceAccount(
          reference: 'env:MISSING_FIREBASE',
          projectDirectory: project.path,
          environment: {'GOOGLE_APPLICATION_CREDENTIALS': credentialFile.path},
        ),
        throwsFormatException,
      );
    });

    test('rejects invalid environment names and relative paths', () {
      for (final reference in [
        'env:',
        'env:BAD NAME',
        'service-account.json',
      ]) {
        expect(
          () => resolveFirebaseServiceAccount(
            reference: reference,
            projectDirectory: project.path,
            environment: {},
          ),
          throwsFormatException,
        );
      }
    });

    test('rejects a missing credential file', () {
      expect(
        () => resolveFirebaseServiceAccount(
          reference: p.join(root.path, 'missing.json'),
          projectDirectory: project.path,
          environment: {},
        ),
        throwsFormatException,
      );
    });

    test('rejects JSON embedded inside a clone configuration', () {
      expect(
        () => resolveFirebaseServiceAccount(
          reference: jsonEncode(credential),
          projectDirectory: project.path,
          environment: {},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'redacted error',
            isNot(contains('PRIVATE_SENTINEL')),
          ),
        ),
      );
    });

    test('rejects malformed JSON without displaying credential content', () {
      credentialFile.writeAsStringSync('{ PRIVATE_SENTINEL');
      expect(
        () => resolveFirebaseServiceAccount(
          reference: credentialFile.path,
          projectDirectory: project.path,
          environment: {},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.toString(),
            'redacted error',
            isNot(contains('PRIVATE_SENTINEL')),
          ),
        ),
      );
    });

    test('rejects API keys and user credentials', () {
      for (final json in [
        {'apiKey': 'PRIVATE_SENTINEL'},
        {'type': 'authorized_user', 'refresh_token': 'PRIVATE_SENTINEL'},
        ['PRIVATE_SENTINEL'],
      ]) {
        credentialFile.writeAsStringSync(jsonEncode(json));
        expect(
          () => resolveFirebaseServiceAccount(
            reference: credentialFile.path,
            projectDirectory: project.path,
            environment: {},
          ),
          throwsA(
            isA<FormatException>().having(
              (error) => error.toString(),
              'redacted error',
              isNot(contains('PRIVATE_SENTINEL')),
            ),
          ),
        );
      }
    });

    test('requires a nonempty client_email and private_key', () {
      for (final field in ['client_email', 'private_key']) {
        for (final value in [null, '', '  ', 5]) {
          credentialFile.writeAsStringSync(
            jsonEncode({...credential, field: value}),
          );
          expect(
            () => resolveFirebaseServiceAccount(
              reference: credentialFile.path,
              projectDirectory: project.path,
              environment: {},
            ),
            throwsFormatException,
          );
        }
      }
    });

    test('rejects credentials stored inside the active Flutter project', () {
      final inside = credentialFile.copySync(
        p.join(project.path, 'service-account.json'),
      );
      expect(
        () => resolveFirebaseServiceAccount(
          reference: inside.path,
          projectDirectory: project.path,
          environment: {},
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('outside the Flutter project'),
          ),
        ),
      );
    });

    test('rejects an external symlink to a credential inside the project', () {
      final inside = credentialFile.copySync(
        p.join(project.path, 'service-account.json'),
      );
      final link = Link(p.join(root.path, 'outside-link.json'))
        ..createSync(inside.path);
      expect(
        () => resolveFirebaseServiceAccount(
          reference: link.path,
          projectDirectory: project.path,
          environment: {},
        ),
        throwsFormatException,
      );
    });

    test('rejects an in-project symlink to an external credential', () {
      final link = Link(p.join(project.path, 'inside-link.json'))
        ..createSync(credentialFile.path);
      expect(
        () => resolveFirebaseServiceAccount(
          reference: link.path,
          projectDirectory: project.path,
          environment: {},
        ),
        throwsFormatException,
      );
    });
  });

  group('withFirebaseServiceAccount', () {
    test('retains inherited CLI login in legacy mode', () async {
      final result = await withFirebaseServiceAccount(
        credentialPath: null,
        operation: (environment) async {
          expect(environment, isNull);
          return 7;
        },
      );
      expect(result, 7);
    });

    test(
      'isolates saved login and token without modifying user config',
      () async {
        final originalConfig = Directory(p.join(root.path, 'user-config'))
          ..createSync();
        final savedLogin =
            File(
                p.join(
                  originalConfig.path,
                  'configstore',
                  'firebase-tools.json',
                ),
              )
              ..createSync(recursive: true)
              ..writeAsStringSync('{"user":{"email":"saved@example.com"}}');
        final originalContent = savedLogin.readAsStringSync();
        String? temporaryConfig;

        await withFirebaseServiceAccount(
          credentialPath: credentialFile.path,
          environment: {
            'XDG_CONFIG_HOME': originalConfig.path,
            'FIREBASE_TOKEN': 'OLD_TOKEN',
            'GOOGLE_APPLICATION_CREDENTIALS': 'old-credential.json',
            'UNRELATED_SETTING': 'keep',
          },
          operation: (environment) async {
            expect(
              environment!['GOOGLE_APPLICATION_CREDENTIALS'],
              credentialFile.path,
            );
            expect(environment['FIREBASE_TOKEN'], isEmpty);
            expect(environment['UNRELATED_SETTING'], 'keep');
            temporaryConfig = environment['XDG_CONFIG_HOME'];
            expect(temporaryConfig, isNot(originalConfig.path));
            expect(Directory(temporaryConfig!).existsSync(), isTrue);
            expect(
              File(
                p.join(temporaryConfig!, 'configstore', 'firebase-tools.json'),
              ).existsSync(),
              isFalse,
            );
            File(p.join(temporaryConfig!, 'configstore', 'firebase-tools.json'))
              ..createSync(recursive: true)
              ..writeAsStringSync('{}');
          },
        );

        expect(savedLogin.readAsStringSync(), originalContent);
        expect(Directory(temporaryConfig!).existsSync(), isFalse);
      },
    );

    test('cleans the isolated Configstore when a command fails', () async {
      String? temporaryConfig;
      await expectLater(
        withFirebaseServiceAccount<void>(
          credentialPath: credentialFile.path,
          environment: {},
          operation: (environment) async {
            temporaryConfig = environment!['XDG_CONFIG_HOME'];
            throw StateError('command failed');
          },
        ),
        throwsStateError,
      );
      expect(Directory(temporaryConfig!).existsSync(), isFalse);
    });

    test('uses a fresh Configstore for each operation', () async {
      final configDirectories = <String>[];
      for (var index = 0; index < 2; index++) {
        await withFirebaseServiceAccount(
          credentialPath: credentialFile.path,
          environment: {},
          operation: (environment) async {
            configDirectories.add(environment!['XDG_CONFIG_HOME']!);
          },
        );
      }
      expect(configDirectories[0], isNot(configDirectories[1]));
    });
  });
}
