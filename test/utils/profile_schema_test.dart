import 'dart:convert';
import 'dart:io';

import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/models/commands_calls_models/configure_command_model.dart';
import 'package:clonify/models/config_model.dart';
import 'package:clonify/utils/clone_config_generator.dart';
import 'package:clonify/utils/configuration_preflight.dart';
import 'package:clonify/utils/profile_identity.dart';
import 'package:clonify/utils/profile_schema.dart';
import 'package:test/test.dart';

import '../support/cli_fixture.dart';

const minimalProfile = <String, dynamic>{
  'client_id': 'alpha',
  'android_package_name': 'com.example.alpha',
  'ios_package_name': 'com.example.alpha.ios',
  'app_name': 'Alpha',
  'version': '1.0.0+1',
  'logo': 'logo.png',
  'launcher_icon': 'icon.png',
  'splash_screen': 'splash.png',
};

void main() {
  final repository = Directory.current.path;
  late String previous;
  late CliFixture fixture;
  setUp(() {
    previous = Directory.current.path;
    fixture = CliFixture(repository);
    Directory.current = fixture.project;
    fixture.write(
      'clonify/clones/alpha/config.json',
      jsonEncode(minimalProfile),
    );
  });
  tearDown(() {
    Directory.current = previous;
    fixture.dispose();
  });

  test('only core fields suffice even when integrations are globally enabled', () {
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync().replaceAll('enabled: false', 'enabled: true')}\ncustom_fields:\n  - name: is_client_account\n    type: bool\n',
    );
    final plan = inspectConfigure(ConfigureCommandModel()..clientId = 'alpha');
    expect(plan.firebaseMode, FirebaseSetupMode.disabled);
    expect(plan.config['androidPackageName'], 'com.example.alpha');
    expect(plan.config['iosPackageName'], 'com.example.alpha.ios');
  });

  test(
    'direct generation rejects incomplete models before writing a file',
    () async {
      await expectLater(
        generateCloneConfigFile(CloneConfigModel.fromJson(<String, dynamic>{})),
        throwsA(isA<CustomException>()),
      );
      expect(
        fixture.file('lib/generated/clone_configs.dart').existsSync(),
        isFalse,
      );
    },
  );

  for (final field in minimalProfile.keys) {
    for (final invalid in [null, '', 123]) {
      test('core field $field rejects $invalid before any writes', () {
        final config = {...minimalProfile, field: invalid};
        fixture.write('clonify/clones/alpha/config.json', jsonEncode(config));
        final before = fixture.snapshot();
        expect(
          () => readCloneProfile('alpha'),
          throwsA(isA<CustomException>()),
        );
        expect(fixture.snapshot(), before);
      });
    }
  }

  test(
    'legacy package name and camelCase migrate to independent snake_case IDs',
    () {
      final legacy = {
        'clientId': 'alpha',
        'packageName': 'com.example.alpha',
        'appName': 'Alpha',
        'version': '1.0.0+1',
        'logo': 'logo.png',
        'launcherIcon': 'icon.png',
        'splashScreen': 'splash.png',
        'isClientAccount': true,
        'apiURL': 'https://example.com',
        'colors': [
          {'name': 'accentColor', 'color': 'FFAABB'},
        ],
      };
      final serialized = profileToJson(legacy);
      expect(serialized['android_package_name'], 'com.example.alpha');
      expect(serialized['ios_package_name'], 'com.example.alpha');
      expect(serialized['is_client_account'], true);
      expect(serialized.containsKey('package_name'), isFalse);
      expect(profileFingerprint(legacy), profileFingerprint(serialized));
      expect(profileToJson(serialized), serialized);
    },
  );

  test(
    'mixed duplicate aliases fail instead of silently overriding values',
    () {
      for (final entries in [
        {'app_name': 'First', 'appName': 'Second'},
        {'is_client_account': true, 'isClientAccount': true},
      ]) {
        expect(
          () => normalizeProfile(entries),
          throwsA(isA<CustomException>()),
        );
      }
    },
  );

  test('platform identifiers follow respective Android and iOS rules', () {
    fixture.write(
      'clonify/clones/alpha/config.json',
      jsonEncode({
        ...minimalProfile,
        'ios_package_name': 'com.example.alpha-ios',
      }),
    );
    expect(
      readCloneProfile('alpha')['iosPackageName'],
      'com.example.alpha-ios',
    );
    for (final entry in {
      'android_package_name': 'com.example.alpha-ios',
      'ios_package_name': 'com.example.alpha_ios',
    }.entries) {
      fixture.write(
        'clonify/clones/alpha/config.json',
        jsonEncode({...minimalProfile, entry.key: entry.value}),
      );
      expect(() => readCloneProfile('alpha'), throwsA(isA<CustomException>()));
    }
  });

  test('generator compiles primary constructor and round-trips tricky strings', () async {
    final values = [
      "It's café",
      r'$value ${injection}',
      r'\path\"quote',
      'one\ntwo\r\t\b\f\u0000',
      'عربي کوردی 🧪',
      "'\"\\\$",
    ];
    fixture.write(
      'clonify/clonify_settings.yaml',
      '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields:\n  - name: is_client_account\n    type: bool\n  - name: api_timeout\n    type: double\n  - name: optional_value\n    type: string\n',
    );
    fixture.write(
      'clonify/clones/alpha/config.json',
      jsonEncode({
        ...minimalProfile,
        'is_client_account': false,
        'api_timeout': 10,
        'firebase_service_account': 'env:NEVER_GENERATE_THIS',
      }),
    );
    await generateCloneConfigFile(
      CloneConfigModel.fromJson(readCloneProfile('alpha')),
    );
    final generated = fixture
        .file('lib/generated/clone_configs.dart')
        .readAsStringSync();
    expect(generated, contains('abstract class CloneConfigs() {'));
    expect(
      generated,
      contains("static const String androidPackageName = 'com.example.alpha';"),
    );
    expect(
      generated,
      contains("static const String iosPackageName = 'com.example.alpha.ios';"),
    );
    expect(generated, contains('static const bool isClientAccount = false;'));
    expect(generated, contains('static const double apiTimeout = 10.0;'));
    for (final absent in [
      'packageName =',
      'baseUrl =',
      'primaryColor =',
      'firebaseProjectId =',
      'optionalValue',
      "'null'",
      'NEVER_GENERATE_THIS',
    ]) {
      expect(generated, isNot(contains(absent)));
    }
    fixture.write(
      'verify.dart',
      "import 'dart:convert';\nimport 'lib/generated/clone_configs.dart';\n"
          'void main() { print(jsonEncode([CloneConfigs.clientId, ${values.map(dartString).join(',')} ])); }',
    );
    // Execute the generated source with the real SDK, not fixture tool stubs.
    final result = await Process.run(Platform.resolvedExecutable, [
      'verify.dart',
    ], workingDirectory: fixture.project.path);
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), ['alpha', ...values]);
  });

  for (final name in [
    'app_name',
    'android_package_name',
    'firebase_service_account',
    'class',
    'hash_code',
    'runtime_type',
  ]) {
    test('custom field $name cannot collide with generated or reserved fields', () {
      fixture.write(
        'clonify/clonify_settings.yaml',
        '${fixture.file('clonify/clonify_settings.yaml').readAsStringSync()}\ncustom_fields:\n  - name: $name\n    type: string\n',
      );
      expect(
        () => inspectConfigure(ConfigureCommandModel()..clientId = 'alpha'),
        throwsA(isA<CustomException>()),
      );
    });
  }
}
