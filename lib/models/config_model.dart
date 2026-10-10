import 'color_model.dart';
import '../utils/profile_schema.dart';
import '../custom_exceptions.dart';

/// Represents the complete configuration for a Flutter project clone.
///
/// This model contains all the necessary information to configure a white-labeled
/// version of a Flutter application, including branding, colors, package details,
/// and server endpoints.
///
/// Example:
/// ```dart
/// final config = CloneConfigModel.fromJson({
///   'appName': 'MyApp',
///   'clientId': 'client-123',
///   'packageName': 'com.example.myapp',
///   'primaryColor': '#FF5733',
///   'baseUrl': 'https://api.example.com',
///   'version': '1.0.0+1'
/// });
/// ```
class CloneConfigModel {
  /// The display name of the application.
  late final String? appName;

  /// Unique identifier for this client configuration.
  late final String? clientId;

  /// The primary color for the app theme in hex format.
  late final String? primaryColor;

  /// The Android/iOS package name (e.g., 'com.example.app').
  late final String? androidPackageName;
  late final String? iosPackageName;

  @Deprecated('Use androidPackageName or iosPackageName.')
  String? get packageName => androidPackageName;

  /// The launcher icon filename.
  late final String? launcherIcon;

  /// The splash screen filename.
  late final String? splashScreen;

  /// The logo filename.
  late final String? logo;

  /// Optional Android status-bar notification icon filename under clone assets
  /// (white-on-transparent PNG, default `ic_notification.png`).
  late final String? notificationIcon;

  /// Optional Android notification icon tint / background color
  /// (`0xAARRGGBB` or `#RRGGBB`). Falls back to [primaryColor] when unset.
  late final String? backgroundNotificationColor;

  /// Optional splash screen background color (`0xAARRGGBB` or `#RRGGBB`).
  /// Falls back to `#FFFFFF` when unset.
  late final String? backgroundSplashColor;

  /// The Firebase project ID.
  late final String? firebaseProjectId;

  /// Credential reference (env:NAME or a path outside the Flutter project).
  /// This tooling-only value is never generated into the mobile app.
  late final String? firebaseServiceAccount;

  /// The Shorebird app ID used for code-push releases/patches.
  late final String? shorebirdAppId;

  /// Optional Transistorsoft Background Geolocation Android JWT license.
  late final String? backgroundGeolocationLicenseAndroid;

  /// Optional Transistorsoft Background Geolocation iOS JWT license.
  late final String? backgroundGeolocationLicenseIos;

  /// Optional Android keystore filename under `clonify/clones/{id}/android/`.
  late final String? androidKeystore;

  /// Optional Android `key.properties` filename under the clone android folder.
  late final String? androidKeyProperties;

  /// List of additional color configurations for the application.

  late final List<ColorModel>? colors;

  /// The base URL for API endpoints.
  late final String? baseUrl;

  /// The version string in format 'major.minor.patch+build' (e.g., '1.0.0+1').
  late final String version;

  /// Validates if the configuration has the minimum required fields.
  ///
  /// Returns true if both [appName] and [packageName] are non-empty strings.
  bool get isValid =>
      (appName?.isNotEmpty ?? false) &&
      (androidPackageName?.isNotEmpty ?? false) &&
      (iosPackageName?.isNotEmpty ?? false);

  /// Creates a [CloneConfigModel] instance from a JSON object.
  ///
  /// Parses the provided JSON and populates all configuration fields.
  /// If 'version' is not provided, defaults to '1.0.0+1'.
  ///
  /// Example:
  /// ```dart
  /// final json = {
  ///   'appName': 'MyApp',
  ///   'clientId': 'client-123',
  ///   'packageName': 'com.example.myapp'
  /// };
  /// final config = CloneConfigModel.fromJson(json);
  /// ```
  CloneConfigModel.fromJson(Object? source) {
    if (source is! Map<String, dynamic>) {
      throw CustomException('Clone configuration must be a JSON object.');
    }
    final config = normalizeProfile(source);
    String? text(String field) {
      final value = config[field];
      if (value != null && value is! String) {
        throw CustomException('Clone field "$field" must be a string.');
      }
      return value as String?;
    }

    clientId = text('clientId');
    appName = text('appName');
    primaryColor = text('primaryColor');
    androidPackageName = text('androidPackageName');
    iosPackageName = text('iosPackageName');
    baseUrl = text('baseUrl');
    version = text('version') ?? '1.0.0+1';
    launcherIcon = text('launcherIcon');
    splashScreen = text('splashScreen');
    logo = text('logo');
    notificationIcon = text('notificationIcon');
    backgroundNotificationColor = text('backgroundNotificationColor');
    backgroundSplashColor = text('backgroundSplashColor');
    firebaseProjectId = text('firebaseProjectId');
    firebaseServiceAccount = text('firebaseServiceAccount');
    shorebirdAppId = text('shorebirdAppId');
    backgroundGeolocationLicenseAndroid = text(
      'backgroundGeolocationLicenseAndroid',
    );
    backgroundGeolocationLicenseIos = text('backgroundGeolocationLicenseIos');
    androidKeystore = text('androidKeystore');
    androidKeyProperties = text('androidKeyProperties');
    final rawColors = config['colors'];
    if (rawColors != null && rawColors is! List) {
      throw CustomException('Clone field "colors" must be a list.');
    }
    colors = rawColors == null
        ? null
        : List<ColorModel>.unmodifiable(
            (rawColors as List).map((value) {
              if (value is! Map<String, dynamic>) {
                throw CustomException(
                  'Each clone color must be a JSON object.',
                );
              }
              return ColorModel.fromJson(value);
            }),
          );
  }
}
