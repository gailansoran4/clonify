part of '../../package_rename_plus.dart';

void _setIOSConfigurations(dynamic iosConfig) {
  try {
    if (iosConfig == null) return;
    if (iosConfig is! Map) throw _PackageRenameErrors.invalidIOSConfig;

    final iosConfigMap = Map<String, dynamic>.from(iosConfig);

    _setIOSDisplayName(iosConfigMap[_appNameKey]);
    _setIOSBundleName(iosConfigMap[_bundleNameKey]);
    _setIOSPackageName(
      oldPackageName: iosConfigMap[_overrideOldPackageKey],
      packageName: iosConfigMap[_packageNameKey],
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('iOS configuration failed.');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('iOS configuration failed.');
    rethrow;
  } finally {
    if (iosConfig != null) PackageRenamePlusLogger.warning(_majorTaskDoneLine);
  }
}

void _setIOSDisplayName(dynamic appName) {
  try {
    if (appName == null) return;
    if (appName is! String) throw _PackageRenameErrors.invalidAppName;

    final iosInfoPlistFile = File(_iosInfoPlistFilePath);
    if (!iosInfoPlistFile.existsSync()) {
      throw _PackageRenameErrors.iosInfoPlistNotFound;
    }

    final iosInfoPlistString = iosInfoPlistFile.readAsStringSync();
    final newDisplayNameIOSInfoPlistString = iosInfoPlistString.replaceAll(
      RegExp(r'<key>CFBundleDisplayName</key>\s*<string>(.*?)</string>'),
      '<key>CFBundleDisplayName</key>\n\t<string>${_xmlText(appName)}</string>',
    );

    iosInfoPlistFile.writeAsStringSync(newDisplayNameIOSInfoPlistString);

    final iosProjectFile = File(_iosProjectFilePath);
    if (iosProjectFile.existsSync()) {
      final iosProjectString = iosProjectFile.readAsStringSync();
      final updatedProjectString = iosProjectString.replaceAll(
        RegExp(r'INFOPLIST_KEY_CFBundleDisplayName = ".*?";'),
        'INFOPLIST_KEY_CFBundleDisplayName = ${jsonEncode(appName)};',
      );
      iosProjectFile.writeAsStringSync(updatedProjectString);
      PackageRenamePlusLogger.info(
        'iOS display name set to: `$appName` (project.pbxproj)',
      );
    }

    PackageRenamePlusLogger.info(
      'iOS display name set to: `$appName` (Info.plist)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('iOS Display Name change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('iOS Display Name change failed!!!');
    rethrow;
  } finally {
    if (appName != null) PackageRenamePlusLogger.warning(_minorTaskDoneLine);
  }
}

void _setIOSBundleName(dynamic bundleName) {
  try {
    if (bundleName == null) return;
    if (bundleName is! String) throw _PackageRenameErrors.invalidBundleName;

    if (bundleName.length > 15) {
      PackageRenamePlusLogger.warning(
        'Bundle name is too long. Maximum length should be 15 characters.',
      );
    }

    final iosInfoPlistFile = File(_iosInfoPlistFilePath);
    if (!iosInfoPlistFile.existsSync()) {
      throw _PackageRenameErrors.iosInfoPlistNotFound;
    }

    final iosInfoPlistString = iosInfoPlistFile.readAsStringSync();
    final newBundleNameIOSInfoPlistString = iosInfoPlistString.replaceAll(
      RegExp(r'<key>CFBundleName</key>\s*<string>(.*?)</string>'),
      '<key>CFBundleName</key>\n\t<string>${_xmlText(bundleName)}</string>',
    );

    iosInfoPlistFile.writeAsStringSync(newBundleNameIOSInfoPlistString);

    PackageRenamePlusLogger.info(
      'iOS bundle name set to: `$bundleName` (Info.plist)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('iOS Bundle Name change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('iOS Bundle Name change failed!!!');
    rethrow;
  } finally {
    if (bundleName != null) PackageRenamePlusLogger.warning(_minorTaskDoneLine);
  }
}

void _setIOSPackageName({dynamic oldPackageName, dynamic packageName}) {
  try {
    if (packageName == null) return;
    if (packageName is! String) throw _PackageRenameErrors.invalidPackageName;

    final iosProjectFile = File(_iosProjectFilePath);
    if (!iosProjectFile.existsSync()) {
      throw _PackageRenameErrors.iosProjectFileNotFound;
    }

    final iosProjectString = iosProjectFile.readAsStringSync();
    final newBundleIDIOSProjectString = iosProjectString.replaceAllMapped(
      RegExp(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*"?([^;"\s]+)"?;'),
      (match) {
        final current = match[1]!;
        if (oldPackageName is String) {
          if (current == oldPackageName) {
            return 'PRODUCT_BUNDLE_IDENTIFIER = $packageName;';
          }
          if (current.startsWith('$oldPackageName.')) {
            return 'PRODUCT_BUNDLE_IDENTIFIER = $packageName${current.substring(oldPackageName.length)};';
          }
          return match[0]!;
        }
        if (current.endsWith('.RunnerTests')) {
          return 'PRODUCT_BUNDLE_IDENTIFIER = $packageName.RunnerTests;';
        }
        return 'PRODUCT_BUNDLE_IDENTIFIER = $packageName;';
      },
    );

    iosProjectFile.writeAsStringSync(newBundleIDIOSProjectString);

    PackageRenamePlusLogger.info(
      'iOS bundle identifier set to: `$packageName` (project.pbxproj)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('iOS Bundle Identifier change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('iOS Bundle Identifier change failed!!!');
    rethrow;
  } finally {
    if (packageName != null) {
      PackageRenamePlusLogger.warning(_minorTaskDoneLine);
    }
  }
}
