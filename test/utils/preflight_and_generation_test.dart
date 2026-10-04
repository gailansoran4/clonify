import 'dart:convert';
import 'dart:io';

import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/models/commands_calls_models/configure_command_model.dart';
import 'package:clonify/models/config_model.dart';
import 'package:clonify/models/clonify_settings_model.dart';
import 'package:clonify/utils/clone_config_generator.dart';
import 'package:clonify/utils/configuration_preflight.dart';
import 'package:clonify/utils/file_tree_checkpoint.dart';
import 'package:clonify/utils/profile_identity.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../support/cli_fixture.dart';
import '../silence_logs.dart';

void main() {
  silenceClonifyLogsForTests();
  final repository = Directory.current.path;
  late String previous;
  late CliFixture fixture;
  setUp(() {
    previous = Directory.current.path;
    fixture = CliFixture(repository);
    Directory.current = fixture.project;
  });
  tearDown(() {
    Directory.current = previous;
    fixture.dispose();
  });

  for (final input in [
    '',
    '..',
    '../alpha',
    '/tmp/alpha',
    r'foo\bar',
    'alpha/beta',
  ]) {
    test(
      'rejects unsafe profile ID "$input"',
      () => expect(
        () => readCloneProfile(input),
        throwsA(isA<CustomException>()),
      ),
    );
  }

  for (final entry in {
    'version': 42,
    'firebaseServiceAccount': true,
    'colors': 'blue',
    'launcherIcon': '../icon.png',
    'primaryColor': 'not a color',
    'packageName': 'bad id',
  }.entries) {
    test('validates ${entry.key} before writes', () {
      fixture.profile('alpha', changes: {entry.key: entry.value});
      expect(() => readCloneProfile('alpha'), throwsA(isA<CustomException>()));
    });
  }

  test('typed model rejects wrong types without a runtime cast exception', () {
    expect(
      () => CloneConfigModel.fromJson({'packageName': 5}),
      throwsA(isA<CustomException>()),
    );
    expect(
      () => CloneConfigModel.fromJson([]),
      throwsA(isA<CustomException>()),
    );
  });

  test('settings validate optional booleans and custom field types', () {
    final settings =
        loadYaml(
              fixture.file('clonify/clonify_settings.yaml').readAsStringSync(),
            )
            as YamlMap;
    final malformed =
        loadYaml(
              '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields: [wrong]\n',
            )
            as YamlMap;
    expect(ClonifySettings.fromYaml(settings).firebaseEnabled, isFalse);
    expect(
      () => ClonifySettings.fromYaml(malformed),
      throwsA(isA<CustomException>()),
    );
    expect(
      () =>
          ClonifySettings.fromYaml(loadYaml('update_ios_info: yes') as YamlMap),
      throwsA(isA<CustomException>()),
    );
  });

  test(
    'generated strings escape quotes, dollar interpolation, and Unicode',
    () async {
      fixture.profile(
        'alpha',
        changes: {
          'appName': 'Café "Alpha" \$value',
          'baseUrl': 'https://example.com/\$customer',
        },
      );
      final config = readCloneProfile('alpha');
      await generateCloneConfigFile(CloneConfigModel.fromJson(config));
      final output = fixture
          .file('lib/generated/clone_configs.dart')
          .readAsStringSync();
      expect(output, contains(r'Café \"Alpha\" \$value'));
      expect(output, contains(r'https://example.com/\$customer'));
    },
  );

  test('custom field type errors and duplicate names fail preflight', () {
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields:\n  - name: timeout\n    type: int\n',
    );
    fixture.profile('alpha', changes: {'timeout': 'five'});
    expect(
      () => inspectConfigure(ConfigureCommandModel()..clientId = 'alpha'),
      throwsA(
        isA<CustomException>().having(
          (e) => e.message,
          'message',
          contains('timeout must have type int'),
        ),
      ),
    );
    fixture.profile(
      'alpha',
      changes: {
        'colors': [
          {'name': 'appName', 'color': '123456'},
        ],
      },
    );
    expect(() => readCloneProfile('alpha'), throwsA(isA<CustomException>()));
  });

  test(
    'optional disabled services and missing optional assets stay optional',
    () {
      fixture.write('pubspec.yaml', 'name: fixture\nversion: 1.0.0+1\n');
      fixture.write(
        'clonify/clonify_settings.yaml',
        fixture
            .file('clonify/clonify_settings.yaml')
            .readAsStringSync()
            .replaceAll(
              'needs_launcher_icon: true',
              'needs_launcher_icon: false',
            )
            .replaceAll(
              'needs_splash_screen: true',
              'needs_splash_screen: false',
            )
            .replaceAll('needs_logo: true', 'needs_logo: false'),
      );
      fixture.profile(
        'alpha',
        changes: {'launcherIcon': null, 'splashScreen': null, 'logo': null},
      );
      Directory('clonify/clones/alpha/assets').deleteSync(recursive: true);
      final plan = inspectConfigure(
        ConfigureCommandModel()..clientId = 'alpha',
      );
      expect(plan.assetFields, isEmpty);
      expect(plan.firebaseMode, FirebaseSetupMode.disabled);
    },
  );

  test(
    'symlink escapes and reserved checkpoint paths fail before mutation',
    () async {
      final external = Directory('${fixture.root.path}/external')..createSync();
      Link('escaped').createSync(external.path);
      expect(
        () => assertProjectPath('escaped/file.json'),
        throwsA(isA<CustomException>()),
      );
      await expectLater(
        runConfigureTransaction(() async {}, roots: ['.dart_tool']),
        throwsA(isA<CustomException>()),
      );
      await expectLater(
        runConfigureTransaction(() async {}, roots: ['.git']),
        throwsA(isA<CustomException>()),
      );
    },
    skip: Platform.isWindows
        ? 'Creating symlinks requires Windows developer mode'
        : false,
  );

  test(
    'configuration fingerprint is stable and excludes credential locations',
    () {
      final config = readCloneProfile('alpha');
      final reverse = Map<String, dynamic>.fromEntries(
        config.entries.toList().reversed,
      );
      expect(profileFingerprint(config), profileFingerprint(reverse));
      expect(
        profileFingerprint({
          ...config,
          'firebaseServiceAccount': '/other/account.json',
        }),
        profileFingerprint(config),
      );
      expect(
        profileFingerprint({...config, 'baseUrl': 'https://other.example'}),
        isNot(profileFingerprint(config)),
      );
    },
  );

  test('recorded build detects changed bytes and profile values', () async {
    final config = readCloneProfile('alpha');
    fixture.write('build/example.aab', 'build bytes');
    await recordBuild('alpha', config, 'appbundle', 'build/example.aab');
    expect(
      await assertVerifiedBuild('alpha', config, 'appbundle'),
      File('build/example.aab').path.replaceAll('/', Platform.pathSeparator),
    );
    final receipt =
        jsonDecode(File(buildReceiptPath('alpha')).readAsStringSync()) as Map;
    expect(receipt['appbundle']['sha256'], hasLength(64));
    fixture.write('build/example.aab', 'other bytes');
    await expectLater(
      assertVerifiedBuild('alpha', config, 'appbundle'),
      throwsA(isA<CustomException>()),
    );
  });
}
