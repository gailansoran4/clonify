// Clone Config Section
import 'dart:io';

import 'profile_schema.dart';
import 'configuration_preflight.dart';
import 'command_process.dart';
import 'clone_config_generator.dart';
import 'branding_generator.dart';
export 'clone_config_generator.dart' show generateCloneConfigFile;
import 'profile_identity.dart';
import 'project_lock.dart';

import 'package:chalkdart/chalk.dart';
import 'package:clonify/constants.dart';
import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/models/config_model.dart';
import 'package:clonify/models/commands_calls_models/configure_command_model.dart';
import 'package:clonify/utils/android_signing_manager.dart';
import 'package:clonify/utils/asset_manager.dart';
import 'package:clonify/utils/background_geolocation_license_manager.dart';
import 'package:clonify/utils/clone_configure_validator.dart';
import 'package:clonify/utils/clonify_helpers.dart';
import 'package:clonify/utils/notification_icon_manager.dart';
import 'package:clonify/utils/firebase_manager.dart';
import 'package:clonify/utils/file_tree_checkpoint.dart';
import 'package:clonify/utils/package_rename_plus_manager.dart';
import 'package:clonify/utils/shorebird_manager.dart';
import 'package:clonify/utils/tui_helpers.dart';
import 'package:yaml_edit/yaml_edit.dart';
// ignore: depend_on_referenced_packages
import 'package:yaml/yaml.dart' as yaml;

// import 'package:clonify/src/package_rename_plus/package_rename_plus.dart'
//     as package_rename;

/// Tracks created directories and files for cleanup on cancellation.
final List<String> _createdClonePaths = [];

/// Cleans up created clone files and directories.
void _cleanupCloneCreation() {
  for (final path in _createdClonePaths.reversed) {
    try {
      final entity = FileSystemEntity.typeSync(path);
      switch (entity) {
        case FileSystemEntityType.file:
          File(path).deleteSync();
          logger.i('🧹 Cleaned up file: $path');
          break;
        case FileSystemEntityType.directory:
          Directory(path).deleteSync(recursive: true);
          logger.i('🧹 Cleaned up directory: $path');
          break;
        default:
          break;
      }
    } catch (e) {
      logger.w('⚠️ Could not clean up $path: $e');
    }
  }
  _createdClonePaths.clear();
}

/// Prompts for clone basic information.
///
/// Returns a map with clone configuration or null if cancelled.
Map<String, String>? _promptCloneBasicInfo() {
  try {
    infoMessage('\n📦 Creating New Clone Configuration');
    infoMessage('Please provide the following information:\n');

    final clientId = promptUserTUI(
      '🆔 Enter Clone ID (used to identify your project)',
      '',
      validator: (value) {
        if (value.trim().isEmpty) {
          errorMessage('Clone ID cannot be empty');
          return false;
        }
        return true;
      },
    );

    final baseUrl = promptUserTUI(
      '🌐 Base URL (optional; Enter to skip)',
      '',
      validator: (value) {
        if (value.trim().isEmpty || value.trim() == 'no') {
          infoMessage('No base URL will be used');
          return true;
        }
        if (!Uri.parse(value).isAbsolute) {
          errorMessage('Invalid URL format. Must be an absolute URL.');
          return false;
        }
        return true;
      },
    );

    final primaryColor = promptUserTUI(
      '🎨 Primary color (optional; #RRGGBB or 0xAARRGGBB)',
      '',
      validator: (value) {
        return value.isEmpty || notificationColorHexFromPrimary(value) != null;
      },
    );

    final packageName = promptUserTUI(
      '📦 Android package name (e.g., com.example.app)',
      'com.${currentClonifySettings().companyName}.${clientId.toLowerCase().replaceAll(' ', '').replaceAll('-', '').replaceAll('_', '')}',
      validator: (value) {
        if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z][a-zA-Z0-9_]*)+$')
            .hasMatch(value)) {
          errorMessage('Invalid package name format. Use com.company.app');
          return false;
        }
        return true;
      },
    );

    final iosPackage = promptUserTUI(
      '🍎 iOS bundle ID (Enter to use the Android package name)',
      packageName,
      validator: (value) =>
          RegExp(r'^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$').hasMatch(value),
    );

    final appName = promptUserTUI(
      '📱 Enter the app name (e.g., My App)',
      toTitleCase(clientId),
      validator: (value) {
        if (value.isEmpty) {
          errorMessage('App name cannot be empty');
          return false;
        }
        return true;
      },
    );

    final version = promptUserTUI(
      '🔢 Enter the app version (e.g., 1.0.0+1)',
      '1.0.0+1',
      validator: (value) {
        if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value)) {
          errorMessage('Invalid version format. Use X.Y.Z+B (e.g., 1.0.0+1)');
          return false;
        }
        return true;
      },
    );

    String firebaseProjectId = '';
    if (currentClonifySettings().firebaseEnabled) {
      firebaseProjectId = promptUserTUI(
        '🔥 Firebase project ID (optional; Enter to skip)',
        '',
      );
    }

    String shorebirdAppId = '';
    if (currentClonifySettings().shorebirdEnabled) {
      shorebirdAppId = promptUserTUI(
        '🐦 Shorebird app ID (optional; Enter to skip)',
        '',
      );
    }

    // Prompt for custom fields if any are defined
    final configMap = <String, String>{
      'clientId': clientId,
      if (baseUrl.isNotEmpty && baseUrl != 'no') 'baseUrl': baseUrl,
      if (primaryColor.isNotEmpty) 'primaryColor': primaryColor,
      'androidPackageName': packageName,
      'iosPackageName': iosPackage,
      'appName': appName,
      'version': version,
      if (firebaseProjectId.isNotEmpty) 'firebaseProjectId': firebaseProjectId,
      if (shorebirdAppId.isNotEmpty) 'shorebirdAppId': shorebirdAppId,
    };

    {
      final launcherIcon = promptUserTUI(
        '🎯 Enter the launcher icon filename (e.g., icon.png)',
        'icon.png',
        validator: (value) {
          if (value.trim().isEmpty) {
            errorMessage('Launcher icon filename cannot be empty');
          } else if (!File('assets/images/$value').existsSync()) {
            errorMessage(
              'Launcher icon file does not exist at assets/images/$value',
            );
            return false;
          }
          return true;
        },
      );
      configMap['launcherIcon'] = launcherIcon;
    }

    {
      final splashScreen = promptUserTUI(
        '🎯 Enter the splash screen filename (e.g., splash.png)',
        'splash.png',
        validator: (value) {
          if (value.trim().isEmpty) {
            errorMessage('Splash screen filename cannot be empty');
          } else if (!File('assets/images/$value').existsSync()) {
            errorMessage(
              'Splash screen file does not exist at assets/images/$value',
            );
            return false;
          }
          return true;
        },
      );
      configMap['splashScreen'] = splashScreen;
      final backgroundSplashColor = promptUserTUI(
        '🎨 Enter the splash background color (e.g., 0xFFFFFFFF or #FFFFFF)',
        '0xFFFFFFFF',
      );
      configMap['backgroundSplashColor'] = backgroundSplashColor;
    }

    {
      final logo = promptUserTUI(
        '🎯 Enter the logo filename (e.g., logo.png)',
        'logo.png',
        validator: (value) {
          if (value.trim().isEmpty) {
            errorMessage('Logo filename cannot be empty');
          } else if (!File('assets/images/$value').existsSync()) {
            errorMessage('Logo file does not exist at assets/images/$value');
            return false;
          }
          return true;
        },
      );
      configMap['logo'] = logo;
    }

    if (currentClonifySettings().customFields.isNotEmpty) {
      infoMessage('\n⚙️  Custom Configuration Fields:');
      for (final field in currentClonifySettings().customFields) {
        final value = promptUserTUI(
          '🔧 ${snakeCaseField(field.name)} (${field.type}, optional; Enter to skip)',
          '',
          validator: (value) {
            if (value.trim().isEmpty) {
              return true;
            }
            switch (field.type) {
              case 'int':
                if (int.tryParse(value) == null) {
                  errorMessage('Must be a valid integer number');
                  return false;
                }
                return true;
              case 'double':
                if (double.tryParse(value) == null) {
                  errorMessage('Must be a valid decimal number');
                  return false;
                }
                return true;
              case 'bool':
                if (value.toLowerCase() != 'true' &&
                    value.toLowerCase() != 'false') {
                  errorMessage('Must be either "true" or "false"');
                  return false;
                }
                return true;
              case 'string':
              default:
                return true;
            }
          },
        );
        if (value.trim().isEmpty) continue;
        configMap['custom_${field.name}'] = value;
        successMessage('Set ${field.name} = $value');
      }
    }

    // Display configuration summary
    infoMessage('\n📋 Configuration Summary:');
    infoMessage('  🆔 Client ID: ${configMap['clientId']}');
    infoMessage('  🌐 Base URL: ${configMap['baseUrl']}');
    infoMessage('  🎨 Primary Color: ${configMap['primaryColor']}');
    infoMessage('  📦 Android: ${configMap['androidPackageName']}');
    infoMessage('  🍎 iOS: ${configMap['iosPackageName']}');
    infoMessage('  📱 App Name: ${configMap['appName']}');
    infoMessage('  🔢 Version: ${configMap['version']}');
    if (firebaseProjectId.isNotEmpty) {
      infoMessage('  🔥 Firebase: $firebaseProjectId');
    }
    if (shorebirdAppId.isNotEmpty) {
      infoMessage('  🐦 Shorebird: $shorebirdAppId');
    }

    return configMap;
  } catch (e) {
    rethrow;
  }
}

/// Creates the clone directory and config file.
///
/// Returns true if successful, false otherwise.
bool _createCloneStructure(Map<String, String> config) {
  try {
    final clientId = config['clientId']!;
    assertClientId(clientId);
    final cloneDir = Directory('./clonify/clones/$clientId');
    assertProjectPath(cloneDir.path);
    if (cloneDir.existsSync()) {
      throw CustomException(
        'Profile "$clientId" already exists. Choose a new client ID.',
      );
    }

    cloneDir.createSync(recursive: true);
    _createdClonePaths.add(cloneDir.path);

    // Build config JSON dynamically to include custom fields
    final configJson = <String, dynamic>{
      'clientId': config['clientId'],
      'androidPackageName': config['androidPackageName'],
      'iosPackageName': config['iosPackageName'],
      'appName': config['appName'],
      'baseUrl': config['baseUrl'],
      'primaryColor': config['primaryColor'],
      'firebaseProjectId': config['firebaseProjectId'],
      'shorebirdAppId': config['shorebirdAppId'],
      'version': config['version'],
      'launcherIcon': config['launcherIcon'],
      'splashScreen': config['splashScreen'],
      'backgroundSplashColor': config['backgroundSplashColor'] ?? '0xFFFFFFFF',
      'logo': config['logo'],
    };

    configJson.removeWhere((key, value) => value == null);

    // Add custom fields to config
    for (final key in config.keys) {
      if (key.startsWith('custom_')) {
        final fieldName = key.substring(7); // Remove 'custom_' prefix
        final field = currentClonifySettings().customFields.firstWhere(
          (item) => item.name == fieldName,
        );
        final value = config[key]!;
        configJson[fieldName] = switch (field.type) {
          'int' => int.parse(value),
          'double' => double.parse(value),
          'bool' => value.toLowerCase() == 'true',
          _ => value,
        };
      }
    }

    validateProfileFields(clientId, configJson);
    final configFile = File('${cloneDir.path}/config.json');
    configFile.writeAsStringSync(encodeProfile(configJson));
    _createdClonePaths.add(configFile.path);

    logger.i('✅ Config file created at: ${configFile.path}');
    createCloneAndroidSigningDirectory(clientId);
    logger.i(
      '✅ Android signing folder created at: ${cloneAndroidSigningDir(clientId)}',
    );
    return true;
  } catch (e) {
    rethrow;
  }
}

/// Handles the rename and Firebase setup process.
///
/// Returns true if successful, false otherwise.
Future<bool> _setupCloneServices(Map<String, String> config) async {
  try {
    final doRename = prompt(
      'Do you want to rename the app with ${config['appName']} and package with ${config['androidPackageName']} (Android), ${config['iosPackageName']} (iOS)? (y/n):',
    );

    if (doRename.toLowerCase() == 'y') {
      await runRenamePackage(
        appName: config['appName']!,
        packageName: config['androidPackageName']!,
        iosPackageName: config['iosPackageName']!,
      );
    } else {
      logger.i('🚀 Skipping renaming process...');
    }

    if (currentClonifySettings().firebaseEnabled) {
      await createFirebaseProject(
        clientId: config['clientId']!,
        packageName: config['androidPackageName']!,
        iosPackageName: config['iosPackageName']!,
        firebaseProjectId: config['firebaseProjectId'] ?? '',
      );
    }

    return true;
  } catch (e) {
    rethrow;
  }
}

/// Initiates the process of creating a new Flutter project clone.
///
/// This function guides the user through collecting basic clone information,
/// creating the necessary directory structure and configuration files,
/// and setting up associated services like package renaming and Firebase.
///
/// It includes robust cancellation support: if the user cancels at any stage
/// or an error occurs, any files or directories created during the process
/// will be automatically cleaned up to maintain a clean state.
///
/// Throws an [Exception] if an unhandled error occurs during the clone creation process.
Future<void> createClone() async {
  logger.i('🛠 Creating a new project clone...');

  try {
    // Step 1: Collect clone configuration
    final config = _promptCloneBasicInfo();
    if (config == null) {
      logger.w('⚠️ Clone creation cancelled by user');
      throw const CommandCancelled();
    }

    // Step 2: Create directory structure and config file
    assertClientId(config['clientId']!);
    for (final field in ['launcherIcon', 'splashScreen', 'logo']) {
      final asset = config[field];
      if (asset != null && asset.isNotEmpty) {
        assertProjectPath('assets/images/$asset');
        assertPngFile('assets/images/$asset', field);
      }
    }
    if (!_createCloneStructure(config)) {
      throw CustomException('Could not create profile files.');
    }

    if (!createCloneAssetsDirectory(config['clientId']!, [
      for (final field in ['launcherIcon', 'splashScreen', 'logo'])
        if (config[field]?.isNotEmpty ?? false) config[field]!,
    ])) {
      throw CustomException('Could not copy profile assets.');
    }

    // Remote registration is last; a created cloud project cannot be rolled back.
    if (!await _setupCloneServices(config)) {
      throw CustomException('Could not configure clone services.');
    }

    // Success!
    logger.i('🎉 Clone successfully created for ${config['clientId']}!');
    logger.i(
      '🚀 Run "clonify configure --clientId ${config['clientId']}" to generate this clone.',
    );

    // Clear tracking list on successful completion
    _createdClonePaths.clear();
  } catch (e) {
    logger.e('❌ Error during clone creation: $e');
    _cleanupCloneCreation();
    rethrow;
  }
}

/// Handles the initial setup steps (renaming and Firebase).
///
/// Returns true if successful, false otherwise.
Future<bool> _performInitialSetup(
  ConfigureCommandModel callModel,
  Map<String, dynamic> configJson,
) async {
  try {
    // Step 1: Copy clone branding assets into the project
    final assetsProgress = progressWithTUI('🎨 Replacing client assets...');
    if (Directory('clonify/clones/${callModel.clientId}/assets').existsSync()) {
      replaceAssets(callModel.clientId!);
    }
    assetsProgress?.complete('Assets replaced successfully');

    // Step 2: Rename app name and package
    final renameProgress = progressWithTUI(
      '📦 Renaming package to ${androidPackageName(configJson)} (Android), ${iosPackageName(configJson)} (iOS)...',
    );
    await runRenamePackage(
      appName: configJson['appName'],
      packageName: androidPackageName(configJson),
      iosPackageName: iosPackageName(configJson),
    );
    renameProgress?.complete('Package renamed successfully');

    return true;
  } catch (e) {
    if (e is CommandCancelled) rethrow;
    throw CustomException('Initial setup failed: $e');
  }
}

Future<void> configureProfileServices(
  ConfigureCommandModel callModel,
  Map<String, dynamic> configJson,
) async {
  if (callModel.isDebug) {
    return;
  }

  // Step 4: Sync Shorebird app_id (runs even with --skipAll unless explicitly skipped)
  if (currentClonifySettings().shorebirdEnabled) {
    final shorebirdAppId = resolveShorebirdAppId(configJson);
    if (shorebirdAppId.isEmpty) {
      logger.i(
        '>>| Skipping Shorebird configuration (no shorebirdAppId in clone config).',
      );
    } else {
      final shorebirdProgress = progressWithTUI(
        '🐦 Syncing Shorebird app_id to $shorebirdAppId...',
      );
      await configureShorebirdAppId(
        shorebirdAppId: shorebirdAppId,
        skip: callModel.skipShorebirdConfigure,
      );
      shorebirdProgress?.complete('Shorebird app_id synced successfully');
    }
  }

  // Step 3: Create Firebase project and enable FCM
  if (currentClonifySettings().firebaseEnabled) {
    final firebaseProjectId =
        (configJson['firebaseProjectId'] as String?) ?? '';
    if (firebaseProjectId.isEmpty) {
      logger.i(
        '>>| Skipping Firebase configuration (no firebaseProjectId in clone config).',
      );
    } else {
      final firebaseProgress = progressWithTUI(
        '🔥 Configuring Firebase for $firebaseProjectId...',
      );
      await addFirebaseToApp(
        clientId: callModel.clientId!,
        packageName: androidPackageName(configJson),
        iosPackageName: iosPackageName(configJson),
        firebaseProjectId: firebaseProjectId,
        firebaseServiceAccount: configJson['firebaseServiceAccount'] as String?,
        skip: callModel.skipFirebaseConfigure,
        refresh: callModel.refreshFirebase,
      );
      firebaseProgress?.complete('Firebase configured successfully');
    }
  }
}

/// Gets the current version from pubspec.yaml.
///
/// Returns the version string or null if an error occurs.
String? _getCurrentPubspecVersion() {
  const pubspecFilePath = './pubspec.yaml';
  try {
    final pubspecContent = File(pubspecFilePath).readAsStringSync();
    final pubspecMap = yaml.loadYaml(pubspecContent);
    return pubspecMap['version'] ?? 'Unknown Version';
  } catch (e) {
    logger.e('❌ Failed to read or parse $pubspecFilePath: $e');
    return null;
  }
}

/// Handles version management logic.
///
/// Returns the final version or null if process should be cancelled.
Future<String?> _handleVersionManagement(
  ConfigureCommandModel callModel,
  Map<String, dynamic> configJson,
) async {
  final yamlVersion = _getCurrentPubspecVersion();
  if (yamlVersion == null) return null;

  String configVersion = configJson['version'] ?? '';

  // Handle missing config version
  if (configVersion.isEmpty) {
    configVersion = promptUser(
      'Config file does not have a version parameter. Enter a new version or use the default (1.0.0+1):',
      '1.0.0+1',
      validator: (value) => RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value),
      skipValue: '1.0.0+1',
      skip: callModel.skipAll || callModel.skipVersionUpdate,
    );
    configJson['version'] = configVersion;
    await File('./clonify/clones/${callModel.clientId}/config.json')
        .writeAsString(encodeProfile(configJson));
  }

  // Sync pubspec version with config
  if (yamlVersion != configVersion && !callModel.skipPubUpdate) {
    final updateYamlVersionAnswer = prompt(
      'Version in pubspec.yaml ($yamlVersion) is different from config file ($configVersion). Do you want to update pubspec.yaml with the config version? (y/n):',
      skip:
          callModel.skipAll ||
          callModel.skipVersionUpdate ||
          !stdin.hasTerminal,
      skipValue: 'y',
    );

    if (updateYamlVersionAnswer.toLowerCase() == 'y') {
      await updateYamlVersionInPubspec(configVersion);
    }
  }

  // Handle version updates
  final changeVersionAnswer = prompt(
    'Do you want to update the version number ($configVersion)? (y/n):',
    skip:
        callModel.skipAll ||
        callModel.skipVersionUpdate ||
        callModel.autoUpdate,
    skipValue: callModel.autoUpdate ? 'y' : 'No',
  );

  if (changeVersionAnswer.toLowerCase() == 'y') {
    final newVersion = promptUser(
      'Enter the new version number:',
      configVersion,
      validator: (value) => RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value),
      skipValue: versionNumberIncrementor(configVersion),
      skip: callModel.autoUpdate,
    );
    if (!callModel.skipPubUpdate) await updateYamlVersionInPubspec(newVersion);
    configJson['version'] = newVersion;
    await File('./clonify/clones/${callModel.clientId}/config.json')
        .writeAsString(encodeProfile(configJson));
    return newVersion;
  }

  return configVersion;
}

Future<void> applyCloneNativeConfig(
  String clientId,
  Map<String, dynamic> configJson,
) async {
  await applyBackgroundGeolocationLicenses(configJson);
  await applyAndroidNotificationIcon(clientId, configJson);
  await applyAndroidReleaseSigning(clientId, configJson);
}

/// Configures an application clone based on a provided [ConfigureCommandModel].
///
/// Validates first, then applies every mutation inside an all-or-nothing
/// checkpoint. If Android fails after iOS (or any later step fails), previous
/// iOS/Android/project files are restored and a single error is reported.
/// [afterConfigure] runs within the same checkpoint for compound commands.
Future<Map<String, dynamic>?> configureApp(
  ConfigureCommandModel callModel, {
  Future<void> Function()? afterConfigure,
}) => withProjectLock(() async {
  logger.i('🚀 Configuring ${callModel.clientId}…');
  String? onlineProject;

  try {
    final plan = inspectConfigure(callModel);
    final configJson = plan.config;
    for (final warning in plan.warnings) {
      logger.w(warning);
    }

    return await runConfigureTransaction(() async {
      await _performInitialSetup(callModel, configJson);

      final finalVersion = await _handleVersionManagement(
        callModel,
        configJson,
      );
      if (finalVersion == null) {
        throw CustomException('Version update failed');
      }

      if (!await configureLauncherIconsAndSplashScreen(configJson)) {
        throw CustomException('Launcher icon or splash screen update failed');
      }

      await generateCloneConfigFile(CloneConfigModel.fromJson(configJson));
      await applyCloneNativeConfig(callModel.clientId!, configJson);
      assertConfigureFinished(
        callModel.clientId!,
        configJson,
        assetFields: plan.assetFields,
      );
      if (plan.firebaseMode == FirebaseSetupMode.online) {
        onlineProject = configJson['firebaseProjectId'] as String;
      }
      await configureProfileServices(callModel, configJson);
      assertProfileIdentity(
        callModel.clientId!,
        configJson,
        android: plan.settings.updateAndroidInfo,
        ios: plan.settings.updateIOSInfo,
        requireSelected: false,
        checkFirebase: !callModel.isDebug,
        checkShorebird: !callModel.isDebug && !callModel.skipShorebirdConfigure,
        checkVersion: !callModel.skipPubUpdate,
      );
      checkCommandCancellation();
      File(Constants.configFilePath(callModel.clientId!))
          .writeAsStringSync(encodeProfile(configJson));
      recordConfiguredProfile(callModel.clientId!, configJson);
      if (afterConfigure != null) await afterConfigure();
      logger.i('✅ Configure finished for ${callModel.clientId}');
      logger.i('Android: ${androidPackageName(configJson)}');
      logger.i('iOS: ${iosPackageName(configJson)}');
      logger.i('Version: ${configJson['version']}');
      logger.i('Generated: lib/generated/clone_configs.dart');
      return configJson;
    }, roots: plan.roots);
  } on ConfigureRolledBackException catch (error) {
    logger.e('❌ ${error.message}');
    if (onlineProject != null) {
      logger.w(
        'FlutterFire may have registered apps in $onlineProject. Local recovery does not remove cloud apps.',
      );
    }
    if (error.restoreError == null) {
      logger.i('↩️  Restored previous iOS, Android, and project files.');
    }
    rethrow;
  } catch (e) {
    logger.e('❌ Configure failed: $e');
    rethrow;
  }
});

/// Updates the 'version' field in the `pubspec.yaml` file.
///
/// This function reads the `pubspec.yaml` file, updates its 'version' field
/// to the [newVersion] using `yaml_edit`, and then writes the modified
/// content back to the file.
///
/// [newVersion] The new version string to set in `pubspec.yaml`.
///
/// Throws a [FileSystemException] if the `pubspec.yaml` file cannot be read or written.
/// Throws a [YamlException] if the `pubspec.yaml` content is invalid.
Future<void> updateYamlVersionInPubspec(String newVersion) async {
  final pubspecFilePath = Constants.pubspecFilePath;
  final pubspecContent = File(pubspecFilePath).readAsStringSync();
  final yamlEditor = YamlEditor(pubspecContent);
  yamlEditor.update(['version'], newVersion);
  File(pubspecFilePath).writeAsStringSync(yamlEditor.toString());
  logger.i('✅ Updated version in ${Constants.pubspecFilePath} to $newVersion');
}

/// Cleans up a partial or broken clone by removing its associated directory.
///
/// This function deletes the entire directory corresponding to the specified
/// [clientId] within the `./clonify/clones/` path. This is useful for
/// removing incomplete or problematic clone setups.
///
/// [clientId] The ID of the client whose clone directory should be removed.
///
/// Throws a [FileSystemException] if the directory exists but cannot be deleted.
Future<void> cleanupPartialClone(String clientId) async {
  assertClientId(clientId);
  final cloneDir = Directory('./clonify/clones/$clientId');
  assertProjectPath(cloneDir.path);
  if (cloneDir.existsSync()) {
    cloneDir.deleteSync(recursive: true);
    logger.i('🧹 Partial clone cleaned up for $clientId.');
  }
}

/// Retrieves and displays the currently active application's name and bundle ID.
///
/// This function executes `dart run rename getAppName` and `dart run rename getBundleId`
/// to fetch the current application name and bundle ID of the Flutter project.
/// It then prints these details to the console.
///
/// Throws an [Exception] if there's an error executing the `rename` commands.
Future<void> getCurrentCloneConfig() async {
  //package_rename_config:
  // android:
  //   app_name: ChargerJO
  //   package_name: com.safeersoft.chargerjo

  try {
    final lastClientId = await getLastClientId();
    final configFile = File(Constants.packageRenameConfigFileName);
    if (!configFile.existsSync()) {
      throw FileSystemException(
        '❌ ${Constants.packageRenameConfigFileName} not found',
      );
    }
    final content = await configFile.readAsString();
    final yaml.YamlMap config = yaml.loadYaml(content);
    final androidAppName =
        config['package_rename_config']?['android']?['app_name'] ?? '';
    final androidPackageName =
        config['package_rename_config']?['android']?['package_name'] ?? '';
    final iosPackageName =
        config['package_rename_config']?['ios']?['package_name'] ?? '';
    final iosBundleName =
        config['package_rename_config']?['ios']?['bundle_name'] ?? '';

    logger.i('App Name: $androidAppName');
    logger.i('Android Package Name: $androidPackageName');
    logger.i('iOS Bundle Name: $iosBundleName');
    logger.i('iOS Bundle ID: $iosPackageName');
    logger.i('Client ID: $lastClientId');
  } catch (e) {
    logger.e('❌ Error getting current clone config: $e');
    rethrow;
  }
}

Future<Map<String, dynamic>> parseConfigFile(String clientId) async =>
    readCloneProfile(clientId);

/// Lists all currently available Clonify project clones.
///
/// This function scans the `./clonify/clones` directory, reads the `config.json`
/// file for each found client, and then prints a formatted table displaying
/// the Client ID, App Name, Firebase Project ID, and Version for each clone.
///
/// If no clones are found or if there are errors parsing configuration files,
/// appropriate messages are logged.
Future<void> listClients() async {
  infoMessage('\n📋 Available Clones');

  final dir = Directory('./clonify/clones');
  if (!dir.existsSync()) {
    warningMessage('No clones directory found.');
    infoMessage(
      'Run "clonify init" to initialize, then "clonify create" to create your first clone.',
    );
    return;
  }

  // Get last active client
  final lastClientId = await getLastClientId();

  // Column Widths (adjust as needed)
  int clientIdWidth = 15;
  int appNameWidth = 20;
  int firebaseProjectIdWidth = 30;
  const int versionWidth = 12;

  final List<Map<String, String>> clientsData = [];

  for (final entity in dir.listSync()) {
    if (entity is Directory) {
      final configFile = File('${entity.path}/config.json');
      if (configFile.existsSync()) {
        try {
          final content = readCloneProfile(
            entity.uri.pathSegments.where((part) => part.isNotEmpty).last,
          );
          final clientId = content['clientId'] ?? '';
          final appName = content['appName'] ?? '';
          final firebaseProjectId = content['firebaseProjectId'] ?? '';
          final version = content['version']?.toString() ?? 'N/A';

          // Adjust column widths
          clientIdWidth = clientId.length > clientIdWidth
              ? clientId.length
              : clientIdWidth;
          appNameWidth = appName.length > appNameWidth
              ? appName.length
              : appNameWidth;
          firebaseProjectIdWidth =
              firebaseProjectId.length > firebaseProjectIdWidth
              ? firebaseProjectId.length
              : firebaseProjectIdWidth;

          clientsData.add({
            'clientId': clientId,
            'appName': appName,
            'firebaseProjectId': firebaseProjectId,
            'version': version,
          });
        } catch (e) {
          errorMessage('Error parsing config file: $e');
        }
      }
    }
  }

  if (clientsData.isEmpty) {
    warningMessage('No clones found.');
    infoMessage('Create your first clone with: clonify create');
    return;
  }

  // Print styled table header
  if (isTUIEnabled()) {
    final chalk = Chalk();
    final headerLine =
        '+${'─' * (clientIdWidth + appNameWidth + firebaseProjectIdWidth + versionWidth + 10)}+';
    print(chalk.cyan(headerLine));

    final header =
        '| '
        '${'🆔 Client ID'.padRight(clientIdWidth + 2)}| '
        '${'📱 App Name'.padRight(appNameWidth + 2)}| '
        '${'🔥 Firebase'.padRight(firebaseProjectIdWidth + 2)}| '
        '${'🔢 Version'.padRight(versionWidth + 2)}|';
    print(chalk.cyan.bold(header));
    print(chalk.cyan(headerLine));
  } else {
    // Basic table for non-TUI mode
    final headerLine =
        '+${'─' * (clientIdWidth + appNameWidth + firebaseProjectIdWidth + versionWidth + 7)}+';
    logger.i('\n$headerLine');
    logger.i(
      '| ${'Client ID'.padRight(clientIdWidth)}|'
      ' ${'App Name'.padRight(appNameWidth)}|'
      ' ${'Firebase Project ID'.padRight(firebaseProjectIdWidth)}|'
      ' ${'Version'.padRight(versionWidth)}|',
    );
    logger.i(headerLine);
  }

  // Print table rows with highlighting for active client
  for (final client in clientsData) {
    final isActive = client['clientId'] == lastClientId;
    final row =
        '| '
        '${client['clientId']!.padRight(clientIdWidth)}| '
        '${client['appName']!.padRight(appNameWidth)}| '
        '${(client['firebaseProjectId'] ?? '').padRight(firebaseProjectIdWidth)}| '
        '${client['version']!.padRight(versionWidth)}|';

    if (isTUIEnabled()) {
      final chalk = Chalk();
      if (isActive) {
        print(chalk.green.bold('▶ ${row.substring(2)}'));
      } else {
        print(chalk.white('  $row'));
      }
    } else {
      if (isActive) {
        logger.i('▶ $row');
      } else {
        logger.i(row);
      }
    }
  }

  // Print table footer
  if (isTUIEnabled()) {
    final chalk = Chalk();
    final footerLine =
        '+${'─' * (clientIdWidth + appNameWidth + firebaseProjectIdWidth + versionWidth + 10)}+';
    print(chalk.cyan(footerLine));
  } else {
    final footerLine =
        '+${'─' * (clientIdWidth + appNameWidth + firebaseProjectIdWidth + versionWidth + 7)}+';
    logger.i(footerLine);
  }

  // Display summary
  final totalClones = clientsData.length;
  if (isTUIEnabled()) {
    print('');
    if (lastClientId != null) {
      successMessage('📌 Active Clone: $lastClientId');
    }
    infoMessage('📊 Total Clones: $totalClones');
  } else {
    logger.i('');
    if (lastClientId != null) {
      logger.i('Active client: $lastClientId');
    }
    logger.i('Total clients: $totalClones');
  }
}
