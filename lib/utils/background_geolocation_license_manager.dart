import 'dart:io';

import 'package:clonify/constants.dart';
import 'package:clonify/custom_exceptions.dart';
import 'package:clonify/utils/clonify_helpers.dart';

const backgroundGeolocationLicenseAndroidKey =
    'backgroundGeolocationLicenseAndroid';
const backgroundGeolocationLicenseIosKey = 'backgroundGeolocationLicenseIos';

const androidLicenseMetaName = 'com.transistorsoft.locationmanager.license';
const iosLicensePlistKey = 'TSLocationManagerLicense';

/// Writes flutter_background_geolocation JWT licenses into native project files
/// when present on the active clone config.
///
/// Android → `android/app/src/main/AndroidManifest.xml`
/// iOS → `ios/Runner/Info.plist`
Future<void> applyBackgroundGeolocationLicenses(
  Map<String, dynamic> configJson,
) async {
  final androidLicense =
      (configJson[backgroundGeolocationLicenseAndroidKey] as String?)?.trim();
  final iosLicense = (configJson[backgroundGeolocationLicenseIosKey] as String?)
      ?.trim();

  for (final entry in {
    backgroundGeolocationLicenseAndroidKey: androidLicense,
    backgroundGeolocationLicenseIosKey: iosLicense,
  }.entries) {
    if (configJson[entry.key] != null && (entry.value?.isEmpty ?? true)) {
      throw CustomException(
        '${entry.key} must be a non-empty JWT when provided.',
      );
    }
  }
  if (androidLicense != null && androidLicense.isNotEmpty) {
    await applyAndroidBackgroundGeolocationLicense(androidLicense);
  } else {
    removeNativeLicense(
      Constants.androidMainManifestFilePath,
      RegExp(
        r'<meta-data\b[^>]*android:name="com\.transistorsoft\.locationmanager\.license"[^>]*/>',
        multiLine: true,
      ),
    );
  }
  if (iosLicense != null && iosLicense.isNotEmpty) {
    await applyIosBackgroundGeolocationLicense(iosLicense);
  } else {
    removeNativeLicense(
      Constants.iosInfoPlistFilePath,
      RegExp(
        r'<key>TSLocationManagerLicense</key>\s*<string>[^<]*</string>',
        multiLine: true,
      ),
    );
  }
}

Future<void> applyAndroidBackgroundGeolocationLicense(String license) async {
  final file = File(Constants.androidMainManifestFilePath);
  if (!file.existsSync()) {
    throw CustomException(
      '${Constants.androidMainManifestFilePath} not found; cannot apply backgroundGeolocationLicenseAndroid',
    );
  }

  var content = await file.readAsString();
  final metaRegex = RegExp(
    r'<meta-data\s+android:name="com\.transistorsoft\.locationmanager\.license"[^/]*/>',
    multiLine: true,
  );
  final metaBlock =
      '''
        <meta-data
            android:name="$androidLicenseMetaName"
            android:value="$license" />''';

  if (metaRegex.hasMatch(content)) {
    content = content.replaceFirst(metaRegex, metaBlock.trim());
  } else if (content.contains('</application>')) {
    content = content.replaceFirst(
      '</application>',
      '$metaBlock\n    </application>',
    );
  } else {
    throw CustomException(
      'Could not locate </application> in AndroidManifest.xml',
    );
  }

  await file.writeAsString(content);
  logger.i('✅ Background Geolocation Android license applied');
}

Future<void> applyIosBackgroundGeolocationLicense(String license) async {
  final file = File(Constants.iosInfoPlistFilePath);
  if (!file.existsSync()) {
    throw CustomException(
      '${Constants.iosInfoPlistFilePath} not found; cannot apply backgroundGeolocationLicenseIos',
    );
  }

  var content = await file.readAsString();
  final keyRegex = RegExp(
    r'<key>TSLocationManagerLicense</key>\s*<string>[^<]*</string>',
    multiLine: true,
  );
  final keyBlock =
      '<key>$iosLicensePlistKey</key>\n\t\t<string>$license</string>';

  if (keyRegex.hasMatch(content)) {
    content = content.replaceFirst(keyRegex, keyBlock);
  } else if (content.contains('</dict>')) {
    content = content.replaceFirst('</dict>', '\t\t$keyBlock\n\t</dict>');
  } else {
    throw CustomException('Could not locate </dict> in Info.plist');
  }

  await file.writeAsString(content);
  logger.i('✅ Background Geolocation iOS license applied');
}

void removeNativeLicense(String path, RegExp pattern) {
  final file = File(path);
  if (!file.existsSync()) return;
  final content = file.readAsStringSync();
  final updated = content.replaceAll(pattern, '');
  if (content != updated) file.writeAsStringSync(updated);
}
