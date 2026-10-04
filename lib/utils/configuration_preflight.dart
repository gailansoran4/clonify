import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../constants.dart';
import '../custom_exceptions.dart';
import '../models/clonify_settings_model.dart';
import '../models/commands_calls_models/configure_command_model.dart';
import '../src/clonify_core.dart';
import 'clone_configure_validator.dart';
import 'clone_config_generator.dart';
import 'notification_icon_manager.dart';
import 'project_paths.dart';
import 'tool_paths.dart';
export 'tool_paths.dart' show findExecutable, assertToolAvailable;
export 'project_paths.dart' show assertProjectPath;
import 'file_tree_checkpoint.dart';
import 'firebase_config_cache.dart';
import 'firebase_credentials.dart';

/// Describes the selected source without opening a network connection.
enum FirebaseSetupMode { disabled, cached, active, online }

typedef ConfigurePlan = ({
  Map<String, dynamic> config,
  ClonifySettings settings,
  FirebaseSetupMode firebaseMode,
  List<String> warnings,
  List<String> assetFields,
  List<String> steps,
  Set<String> roots,
});

void assertClientId(String clientId) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(clientId)) {
    throw CustomException(
      'Invalid client ID. Use letters, numbers, underscores, or hyphens; never a path.',
    );
  }
}

Map<String, dynamic> readCloneProfile(String clientId) {
  assertClientId(clientId);
  final path = Constants.configFilePath(clientId);
  assertProjectPath(path);
  final file = File(path);
  if (!file.existsSync()) {
    throw CustomException(
      'Profile "$clientId" is missing $path. Create the profile or correct --clientId.',
    );
  }
  final Object? value;
  try {
    value = jsonDecode(file.readAsStringSync());
  } on FormatException {
    throw CustomException(
      'Invalid JSON in $path. Fix its JSON syntax before retrying.',
    );
  }
  if (value is! Map<String, dynamic>) {
    throw CustomException('$path must contain a JSON object.');
  }
  validateProfileFields(clientId, value);
  return value;
}

void validateProfileFields(String clientId, Map<String, dynamic> config) {
  assertClientId(clientId);
  for (final field in ['appName', 'packageName']) {
    if (trimmedConfigString(config[field]) == null) {
      throw CustomException(
        'Profile "$clientId": "$field" must be a non-empty string.',
      );
    }
  }
  const stringFields = [
    'clientId',
    'version',
    'baseUrl',
    'primaryColor',
    'launcherIcon',
    'splashScreen',
    'logo',
    'notificationIcon',
    'backgroundNotificationColor',
    'backgroundSplashColor',
    'firebaseProjectId',
    'firebaseServiceAccount',
    'shorebirdAppId',
    'backgroundGeolocationLicenseAndroid',
    'backgroundGeolocationLicenseIos',
    'androidKeystore',
    'androidKeyProperties',
  ];
  for (final field in stringFields) {
    if (config[field] != null && config[field] is! String) {
      throw CustomException('Profile "$clientId": "$field" must be a string.');
    }
  }
  if (config['clientId'] != null && config['clientId'] != clientId) {
    throw CustomException(
      'Profile "$clientId": clientId in config.json must match its folder.',
    );
  }
  // Older profiles may omit clientId/version; preserve their documented defaults.
  config['clientId'] = clientId;
  config['version'] ??= '1.0.0+1';
  if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(config['version'] as String)) {
    throw CustomException(
      'Profile "$clientId": version must use major.minor.patch+build (for example 1.0.0+1).',
    );
  }
  if (!RegExp(
    r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$',
  ).hasMatch(config['packageName'] as String)) {
    throw CustomException(
      'Profile "$clientId": packageName must be a valid application identifier, for example com.example.app.',
    );
  }
  if (RegExp(r'[\x00-\x1f]').hasMatch(config['appName'] as String)) {
    throw CustomException(
      'Profile "$clientId": appName cannot contain control characters.',
    );
  }
  for (final field in [
    'launcherIcon',
    'splashScreen',
    'logo',
    'notificationIcon',
  ]) {
    final value = config[field];
    if (value is String &&
        (value.isEmpty ||
            value == '.' ||
            value == '..' ||
            value.contains('/') ||
            value.contains('\\'))) {
      throw CustomException(
        'Profile "$clientId": "$field" must be a filename inside the profile assets folder.',
      );
    }
  }
  for (final field in [
    'primaryColor',
    'backgroundNotificationColor',
    'backgroundSplashColor',
  ]) {
    if (config[field] != null &&
        notificationColorHexFromPrimary(config[field] as String) == null) {
      throw CustomException(
        'Profile "$clientId": "$field" must be #RRGGBB or 0xAARRGGBB.',
      );
    }
  }
  final colors = config['colors'];
  if (colors != null) {
    if (colors is! List) {
      throw CustomException('Profile "$clientId": colors must be a list.');
    }
    final names = generatedReservedFields();
    for (final color in colors) {
      if (color is! Map ||
          color['name'] is! String ||
          !RegExp(
            r'^[a-zA-Z][a-zA-Z0-9_]*$',
          ).hasMatch(color['name'] as String) ||
          color['color'] is! String ||
          !RegExp(r'^[a-fA-F0-9]{6}$').hasMatch(color['color'] as String) ||
          names.contains(color['name'])) {
        throw CustomException(
          'Profile "$clientId": colors require unique Dart names and six-digit hex values.',
        );
      }
      assertGeneratedFieldName(color['name'] as String, names);
    }
  }
}

Map<dynamic, dynamic> readProjectPubspec() {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) {
    throw CustomException(
      'pubspec.yaml is missing. Run Clonify from the Flutter project root.',
    );
  }
  final Object? value;
  try {
    value = loadYaml(file.readAsStringSync());
  } on YamlException {
    throw CustomException(
      'Invalid YAML in pubspec.yaml. Fix it before retrying.',
    );
  }
  if (value is! Map) {
    throw CustomException('pubspec.yaml must contain a YAML map.');
  }
  return value;
}

bool hasProjectDependency(Map<dynamic, dynamic> pubspec, String package) =>
    (pubspec['dependencies'] is Map &&
        (pubspec['dependencies'] as Map).containsKey(package)) ||
    (pubspec['dev_dependencies'] is Map &&
        (pubspec['dev_dependencies'] as Map).containsKey(package));

/// Validates everything locally knowable before a configure transaction starts.
ConfigurePlan inspectConfigure(ConfigureCommandModel model) {
  final clientId = model.clientId;
  if (clientId == null) throw CustomException('Provide --clientId.');
  assertNoPendingRecovery();
  final config = readCloneProfile(clientId);
  final settings = getClonifySettings();
  final pubspec = readProjectPubspec();
  final errors = <String>[];
  final warnings = <String>[];
  void check(void Function() operation) {
    try {
      operation();
    } catch (error) {
      errors.add('$error');
    }
  }

  final assetFields = [
    if (settings.needsLauncherIcon || config['launcherIcon'] != null)
      'launcherIcon',
    if (settings.needsSplashScreen || config['splashScreen'] != null)
      'splashScreen',
    if (settings.needsLogo || config['logo'] != null) 'logo',
  ];
  check(() => assertConfigureReady(clientId, config, assetFields: assetFields));
  check(() {
    final names = generatedReservedFields();
    for (final item in config['colors'] as List? ?? []) {
      names.add((item as Map)['name'] as String);
    }
    for (final field in settings.customFields) {
      assertGeneratedFieldName(field.name, names);
      if (field.name == 'firebaseServiceAccount') {
        throw CustomException(
          'firebaseServiceAccount cannot be an app custom field.',
        );
      }
      final value = config[field.name];
      if (value == null) continue;
      final valid = switch (field.type) {
        'string' => value is String,
        'int' => value is int,
        'double' => value is num && value.isFinite,
        'bool' => value is bool,
        _ => false,
      };
      if (!valid) {
        throw CustomException(
          'Custom field ${field.name} must have type ${field.type}.',
        );
      }
    }
  });
  if (model.refreshFirebase && model.skipFirebaseConfigure) {
    errors.add(
      'Cannot combine --refreshFirebase with --skipFirebaseConfigure.',
    );
  }
  if (model.refreshFirebase && (model.isDebug || !settings.firebaseEnabled)) {
    errors.add('--refreshFirebase requires Firebase enabled and --no-isDebug.');
  }
  if (model.autoUpdate && model.skipVersionUpdate) {
    errors.add('Cannot combine --autoUpdate with --skipVersionUpdate.');
  }
  if (settings.updateAndroidInfo) {
    check(() => requireFile(Constants.androidMainManifestFilePath));
    check(() => assertAndroidSigningProjectReady());
  }
  if (settings.updateIOSInfo) {
    check(() => requireFile(Constants.iosInfoPlistFilePath));
    check(() => requireFile(Constants.iosProjectFilePath));
  }
  for (final requirement in [
    (package: 'flutter_launcher_icons', enabled: settings.needsLauncherIcon),
    (package: 'flutter_native_splash', enabled: settings.needsSplashScreen),
  ]) {
    if (requirement.enabled &&
        !hasProjectDependency(pubspec, requirement.package)) {
      errors.add(
        'Add ${requirement.package} to pubspec.yaml dev_dependencies, or disable the corresponding needs_* setting.',
      );
    } else if (!hasProjectDependency(pubspec, requirement.package)) {
      warnings.add(
        '${requirement.package} is absent; its generator will be skipped.',
      );
    }
  }
  if ([
    'flutter_launcher_icons',
    'flutter_native_splash',
    'intl_utils',
  ].any((name) => hasProjectDependency(pubspec, name))) {
    check(() => assertToolAvailable('dart'));
  }
  var firebaseMode = FirebaseSetupMode.disabled;
  if (settings.firebaseEnabled && !model.isDebug) {
    check(
      () => firebaseMode = inspectFirebase(
        config,
        clientId,
        settings,
        refresh: model.refreshFirebase,
        skip: model.skipFirebaseConfigure,
      ),
    );
  } else if (model.isDebug) {
    warnings.add(
      'Debug mode skips Firebase and Shorebird. Build/upload identity checks still apply.',
    );
  }
  if (settings.shorebirdEnabled &&
      !model.isDebug &&
      !model.skipShorebirdConfigure) {
    if (trimmedConfigString(config['shorebirdAppId']) == null) {
      errors.add(
        'Profile "$clientId" needs shorebirdAppId because Shorebird is enabled.',
      );
    }
    check(() => requireFile('shorebird.yaml'));
  }
  final roots = <String>{
    ...configureMutableRoots,
    if (settings.firebaseEnabled) settings.firebaseSettingsFilePath,
  };
  // intl_utils may generate an output directory selected in pubspec.yaml.
  final intl = pubspec['flutter_intl'];
  if (hasProjectDependency(pubspec, 'intl_utils') &&
      intl is Map &&
      intl['output_dir'] is String) {
    roots.add(intl['output_dir'] as String);
  }
  for (final root in roots) {
    check(() => assertProjectPath(root, allowSymlinks: false));
  }
  for (final field in [
    'launcherIcon',
    'splashScreen',
    'logo',
    'notificationIcon',
  ]) {
    if (config[field] is String) {
      check(
        () => assertProjectPath(
          p.join(
            'clonify',
            'clones',
            clientId,
            'assets',
            config[field] as String,
          ),
        ),
      );
    }
  }
  if (errors.isNotEmpty) {
    throw CustomException(
      'Preflight failed for "$clientId":\n${errors.map((e) => ' - $e').join('\n')}\nNo profile files were changed.',
    );
  }
  return (
    config: config,
    settings: settings,
    firebaseMode: firebaseMode,
    warnings: warnings,
    assetFields: assetFields,
    steps: [
      'Copy branding assets',
      'Update enabled native app names and identifiers',
      if (firebaseMode != FirebaseSetupMode.disabled)
        'Firebase: ${firebaseMode.name}',
      if (settings.shorebirdEnabled &&
          !model.isDebug &&
          !model.skipShorebirdConfigure)
        'Sync Shorebird app ID',
      'Apply version choices and run installed generators',
      'Generate clone configuration and native signing',
      'Verify outputs, then save selected profile',
    ],
    roots: roots,
  );
}

FirebaseSetupMode inspectFirebase(
  Map<String, dynamic> config,
  String clientId,
  ClonifySettings settings, {
  bool refresh = false,
  bool skip = false,
}) {
  final project = trimmedConfigString(config['firebaseProjectId']);
  if (project == null) {
    throw CustomException(
      'Profile "$clientId" needs firebaseProjectId because Firebase is enabled.',
    );
  }
  final package = config['packageName'] as String;
  assertProjectPath(settings.firebaseSettingsFilePath);
  final metadataType = FileSystemEntity.typeSync(
    settings.firebaseSettingsFilePath,
    followLinks: false,
  );
  if (metadataType != FileSystemEntityType.notFound) {
    firebaseJsonObject(
      readFirebasePublicConfigFile(settings.firebaseSettingsFilePath),
      settings.firebaseSettingsFilePath,
    );
  }
  if (!refresh) {
    final cache = firebaseConfigurationCacheDirectory(clientId);
    if (FileSystemEntity.typeSync(cache.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      assertFirebaseCacheFiles(cache);
      final metadata = firebaseJsonObject(
        readFirebasePublicConfigFile(p.join(cache.path, 'firebase.json')),
        'cached firebase.json',
      );
      if (metadata.length != 1 || !metadata.containsKey('flutter')) {
        throw CustomException(
          'Firebase cache may contain only Flutter metadata. Run configure --refreshFirebase after correcting the cache.',
        );
      }
      assertFirebaseConfiguration(project, package, directory: cache.path);
      return FirebaseSetupMode.cached;
    }
    try {
      assertFirebaseConfiguration(
        project,
        package,
        firebaseSettingsFilePath: settings.firebaseSettingsFilePath,
      );
      return FirebaseSetupMode.active;
    } on CustomException {
      /* The selected profile needs first-time setup. */
    }
  }
  if (skip) {
    throw CustomException(
      'No matching saved Firebase configuration for "$clientId". Configure it once without --skipFirebaseConfigure.',
    );
  }
  resolveFirebaseServiceAccount(
    reference: config['firebaseServiceAccount'] as String?,
  );
  assertToolAvailable('firebase');
  assertToolAvailable('flutterfire');
  requireFile(Constants.androidMainManifestFilePath);
  requireFile(Constants.iosProjectFilePath);
  return FirebaseSetupMode.online;
}

void requireFile(String path) {
  if (!File(path).existsSync()) {
    throw CustomException(
      'Required file is missing: $path. Restore it before retrying.',
    );
  }
}

Set<String> generatedReservedFields() => {
  'baseUrl',
  'packageName',
  'appName',
  'logo',
  'launcherIcon',
  'splashScreen',
  'firebaseProjectId',
  'firebaseServiceAccount',
  'shorebirdAppId',
  'clientId',
  'version',
  'primaryColor',
  'backgroundNotificationColor',
};
