import 'package:yaml/yaml.dart';

import '../custom_exceptions.dart';

import 'package:clonify/models/custom_field_model.dart';

/// Represents the global settings for the Clonify tool.
///
/// These settings are loaded from `clonify_settings.yaml` and define
/// project-wide configuration including Firebase, Fastlane, default colors,
/// and assets to be cloned for each client.
///
/// Example:
/// ```dart
/// final yaml = loadYaml(File('clonify_settings.yaml').readAsStringSync());
/// final settings = ClonifySettings.fromYaml(yaml);
/// ```
class ClonifySettings {
  /// Whether Firebase integration is enabled for this project.
  final bool firebaseEnabled;

  /// Path to the Firebase settings file relative to project root.
  final String firebaseSettingsFilePath;

  /// Whether Fastlane integration is enabled for app deployment.
  final bool fastlaneEnabled;

  /// Path to the Fastlane settings file relative to project root.
  final String fastlaneSettingsFilePath;

  /// Whether Shorebird integration is enabled for code-push app_id sync.
  final bool shorebirdEnabled;

  /// The company or organization name used across all clones.
  final String companyName;

  /// The default primary color in hex format (e.g., '#FF5733').
  final String defaultColor;

  /// Whether the app needs a launcher icon.
  final bool needsLauncherIcon;

  /// Whether the app needs a splash screen.
  final bool needsSplashScreen;

  /// Whether the app needs a logo asset.
  final bool needsLogo;

  /// Whether to update the Android info rename, splash screen and launcher icon.
  final bool updateAndroidInfo;

  /// Whether to update the iOS info rename, splash screen and launcher icon.
  final bool updateIOSInfo;

  /// List of custom fields that can be configured per clone.
  final List<CustomField> customFields;

  /// Creates a new [ClonifySettings] instance.
  ///
  /// Most parameters are required, with [splashScreenAsset] and [customFields]
  /// being optional.
  ClonifySettings({
    required this.firebaseEnabled,
    required this.firebaseSettingsFilePath,
    required this.fastlaneEnabled,
    required this.fastlaneSettingsFilePath,
    this.shorebirdEnabled = false,
    required this.companyName,
    required this.defaultColor,
    required this.needsLauncherIcon,
    required this.needsSplashScreen,
    required this.needsLogo,
    required this.updateAndroidInfo,
    required this.updateIOSInfo,
    this.customFields = const [],
  });

  /// Creates a [ClonifySettings] instance from a YAML map.
  ///
  /// Parses the YAML configuration file and creates a settings object.
  /// Provides default values for missing optional fields.
  ///
  /// Example:
  /// ```dart
  /// final yaml = loadYaml('''
  /// firebase:
  ///   enabled: true
  ///   settings_file: firebase_settings.yaml
  /// company_name: My Company
  /// default_color: '#FF5733'
  /// ''');
  /// final settings = ClonifySettings.fromYaml(yaml);
  /// ```
  factory ClonifySettings.fromYaml(YamlMap yaml) {
    Object? read(Map values, String key, Type type, Object? fallback) {
      final value = values[key];
      if (value == null) return fallback;
      if ((type == bool && value is! bool) ||
          (type == String && value is! String)) {
        throw CustomException(
          'clonify/clonify_settings.yaml: "$key" must be $type.',
        );
      }
      return value;
    }

    Map section(String name) {
      final value = yaml[name];
      if (value == null) return {};
      if (value is! Map) {
        throw CustomException(
          'clonify/clonify_settings.yaml: "$name" must be a map.',
        );
      }
      return value;
    }

    bool flag(String key, bool fallback) =>
        read(yaml, key, bool, fallback) as bool;
    String text(String key, String fallback) =>
        read(yaml, key, String, fallback) as String;
    final firebase = section('firebase');
    final fastlane = section('fastlane');
    final shorebird = section('shorebird');
    final rawFields = yaml[ClonifySettingsKeys.customFields];
    if (rawFields != null && rawFields is! List) {
      throw CustomException(
        'custom_fields must be a list in clonify/clonify_settings.yaml.',
      );
    }
    final fields = <CustomField>[];
    for (final item in (rawFields as List? ?? [])) {
      if (item is! Map || item['name'] is! String || item['type'] is! String) {
        throw CustomException(
          'Each custom field needs string name and type values.',
        );
      }
      final field = CustomField.fromYaml(item);
      if (!field.isValidType()) {
        throw CustomException(
          'Unsupported type for custom field ${field.name}.',
        );
      }
      fields.add(field);
    }
    return ClonifySettings(
      firebaseEnabled: read(firebase, 'enabled', bool, false) as bool,
      firebaseSettingsFilePath:
          read(firebase, 'settings_file', String, 'firebase.json') as String,
      fastlaneEnabled: read(fastlane, 'enabled', bool, false) as bool,
      fastlaneSettingsFilePath:
          read(fastlane, 'settings_file', String, '') as String,
      shorebirdEnabled: read(shorebird, 'enabled', bool, false) as bool,
      companyName: text(ClonifySettingsKeys.companyName, ''),
      defaultColor: text(ClonifySettingsKeys.defaultColor, '#FFFFFF'),
      needsLauncherIcon: flag(ClonifySettingsKeys.needsLauncherIcon, false),
      needsSplashScreen: flag(ClonifySettingsKeys.needsSplashScreen, false),
      needsLogo: flag(ClonifySettingsKeys.needsLogo, false),
      updateAndroidInfo: flag(ClonifySettingsKeys.updateAndroidInfo, true),
      updateIOSInfo: flag(ClonifySettingsKeys.updateIOSInfo, true),
      customFields: List.unmodifiable(fields),
    );
  }
}

class ClonifySettingsKeys {
  static const String firebase = 'firebase';
  static const String enabled = 'enabled';
  static const String settingsFile = 'settings_file';
  static const String fastlane = 'fastlane';
  static const String shorebird = 'shorebird';
  static const String companyName = 'company_name';
  static const String defaultColor = 'default_color';
  static const String needsLauncherIcon = 'needs_launcher_icon';
  static const String needsSplashScreen = 'needs_splash_screen';
  static const String needsLogo = 'needs_logo';
  static const String updateAndroidInfo = 'update_android_info';
  static const String updateIOSInfo = 'update_ios_info';
  static const String customFields = 'custom_fields';
}
