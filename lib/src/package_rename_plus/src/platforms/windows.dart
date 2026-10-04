part of '../../package_rename_plus.dart';

void _setWindowsConfigurations(dynamic windowsConfig) {
  try {
    if (windowsConfig == null) return;
    if (windowsConfig is! Map) throw _PackageRenameErrors.invalidWindowsConfig;

    final windowsConfigMap = Map<String, dynamic>.from(windowsConfig);

    _setWindowsAppName(windowsConfigMap[_appNameKey]);
    _setWindowsOrganization(windowsConfigMap[_organizationKey]);
    _setWindowsCopyrightNotice(windowsConfigMap[_copyrightKey]);
    _setWindowsExecutableName(windowsConfigMap[_executableKey]);
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows configuration failed.');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows configuration failed.');
    rethrow;
  } finally {
    if (windowsConfig != null) {
      PackageRenamePlusLogger.warning(_majorTaskDoneLine);
    }
  }
}

void _setWindowsAppName(dynamic appName) {
  try {
    if (appName == null) return;
    if (appName is! String) throw _PackageRenameErrors.invalidAppName;

    _setWindowsAppTitle(appName);
    _setWindowsProductDetails(appName);
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows App Name change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows App Name change failed!!!');
    rethrow;
  } finally {
    if (appName != null) {
      PackageRenamePlusLogger.warning(_minorTaskDoneLine);
    }
  }
}

void _setWindowsAppTitle(String appName) {
  try {
    final mainCppFile = File(_windowsMainCppFilePath);
    if (!mainCppFile.existsSync()) {
      throw _PackageRenameErrors.windowsMainCppNotFound;
    }

    final mainCppString = mainCppFile.readAsStringSync();

    final newAppTitleMainCppString = mainCppString
        .replaceAll(
          RegExp(r'window.CreateAndShow\(L"(.*)", origin, size\)'),
          'window.CreateAndShow(L"$appName", origin, size)',
        )
        // Implemented from Flutter 3.7 onwards
        .replaceAll(
          RegExp(r'window.Create\(L"(.*)", origin, size\)'),
          'window.Create(L"$appName", origin, size)',
        );

    mainCppFile.writeAsStringSync(newAppTitleMainCppString);

    PackageRenamePlusLogger.info(
      'Windows app title set to: `$appName` (main.cpp)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows App Title change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows App Title change failed!!!');
    rethrow;
  }
}

void _setWindowsProductDetails(String appName) {
  try {
    final runnerFile = File(_windowsRunnerFilePath);
    if (!runnerFile.existsSync()) {
      throw _PackageRenameErrors.windowsRunnerNotFound;
    }

    final runnerString = runnerFile.readAsStringSync();
    final newProductDetailsRunnerString = runnerString
        .replaceAll(
          RegExp(r'VALUE "FileDescription", "(.*)" "\\0"'),
          'VALUE "FileDescription", "$appName" "\\0"',
        )
        .replaceAll(
          RegExp(r'VALUE "InternalName", "(.*)" "\\0"'),
          'VALUE "InternalName", "$appName" "\\0"',
        )
        .replaceAll(
          RegExp(r'VALUE "ProductName", "(.*)" "\\0"'),
          'VALUE "ProductName", "$appName" "\\0"',
        );

    runnerFile.writeAsStringSync(newProductDetailsRunnerString);

    PackageRenamePlusLogger.info(
      'Windows file description set to: `$appName` (Runner.rc)',
    );
    PackageRenamePlusLogger.info(
      'Windows internal name set to: `$appName` (Runner.rc)',
    );
    PackageRenamePlusLogger.info(
      'Windows product name set to: `$appName` (Runner.rc)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Product Details change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Product Details change failed!!!');
    rethrow;
  }
}

void _setWindowsOrganization(dynamic organization) {
  try {
    if (organization == null) return;
    if (organization is! String) throw _PackageRenameErrors.invalidOrganization;

    final runnerFile = File(_windowsRunnerFilePath);
    if (!runnerFile.existsSync()) {
      throw _PackageRenameErrors.windowsRunnerNotFound;
    }

    final runnerString = runnerFile.readAsStringSync();
    final newOrganizationRunnerString = runnerString.replaceAll(
      RegExp(r'VALUE "CompanyName", "(.*)" "\\0"'),
      'VALUE "CompanyName", "$organization" "\\0"',
    );

    runnerFile.writeAsStringSync(newOrganizationRunnerString);

    PackageRenamePlusLogger.info(
      'Windows company name set to: `$organization` (Runner.rc)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Organization change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Organization change failed!!!');
    rethrow;
  } finally {
    if (organization != null) {
      PackageRenamePlusLogger.warning(_minorTaskDoneLine);
    }
  }
}

void _setWindowsCopyrightNotice(dynamic notice) {
  try {
    if (notice == null) return;
    if (notice is! String) throw _PackageRenameErrors.invalidCopyrightNotice;

    final runnerFile = File(_windowsRunnerFilePath);
    if (!runnerFile.existsSync()) {
      throw _PackageRenameErrors.windowsRunnerNotFound;
    }

    final runnerString = runnerFile.readAsStringSync();
    final newCopyrightNoticeRunnerString = runnerString.replaceAll(
      RegExp(r'VALUE "LegalCopyright", "(.*)" "\\0"'),
      'VALUE "LegalCopyright", "$notice" "\\0"',
    );

    runnerFile.writeAsStringSync(newCopyrightNoticeRunnerString);

    PackageRenamePlusLogger.info(
      'Windows legal copyright set to: `$notice` (Runner.rc)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Copyright Notice change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Copyright Notice change failed!!!');
    rethrow;
  } finally {
    if (notice != null) {
      PackageRenamePlusLogger.warning(_minorTaskDoneLine);
    }
  }
}

void _setWindowsExecutableName(dynamic exeName) {
  try {
    if (exeName == null) return;
    if (exeName is! String) throw _PackageRenameErrors.invalidExecutableName;

    final validExeNameRegExp = RegExp(_desktopBinaryNameTemplate);
    if (!validExeNameRegExp.hasMatch(exeName)) {
      throw _PackageRenameErrors.invalidExecutableNameValue;
    }

    _setWindowsCMakeListsBinaryName(exeName);
    _setWindowsOriginalFilename(exeName);
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Executable Name change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Executable Name change failed!!!');
    rethrow;
  } finally {
    if (exeName != null) {
      PackageRenamePlusLogger.warning(_minorTaskDoneLine);
    }
  }
}

void _setWindowsCMakeListsBinaryName(String exeName) {
  try {
    final cmakeListsFile = File(_windowsCMakeListsFilePath);
    if (!cmakeListsFile.existsSync()) {
      throw _PackageRenameErrors.windowsCMakeListsNotFound;
    }

    final cmakeListsString = cmakeListsFile.readAsStringSync();
    final newBinaryNameCmakeListsString = cmakeListsString.replaceAll(
      RegExp(r'set\(BINARY_NAME "(.*?)"\)'),
      'set(BINARY_NAME "$exeName")',
    );

    cmakeListsFile.writeAsStringSync(newBinaryNameCmakeListsString);

    PackageRenamePlusLogger.info(
      'Windows binary name set to: `$exeName` (CMakeLists.txt)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Binary Name change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Binary Name change failed!!!');
    rethrow;
  }
}

void _setWindowsOriginalFilename(String exeName) {
  try {
    final runnerFile = File(_windowsRunnerFilePath);
    if (!runnerFile.existsSync()) {
      throw _PackageRenameErrors.windowsRunnerNotFound;
    }

    final runnerString = runnerFile.readAsStringSync();
    final newOriginalFilenameRunnerString = runnerString.replaceAll(
      RegExp(r'VALUE "OriginalFilename", "(.*?)" "\\0"'),
      'VALUE "OriginalFilename", "$exeName.exe" "\\0"',
    );

    runnerFile.writeAsStringSync(newOriginalFilenameRunnerString);

    PackageRenamePlusLogger.info(
      'Windows original filename set to: `$exeName.exe` (Runner.rc)',
    );
  } on _PackageRenameException catch (e) {
    PackageRenamePlusLogger.error('${e.message}ERR Code: ${e.code}');
    PackageRenamePlusLogger.error('Windows Original Filename change failed!!!');
    rethrow;
  } catch (e) {
    PackageRenamePlusLogger.warning(e.toString());
    PackageRenamePlusLogger.error('ERR Code: 255');
    PackageRenamePlusLogger.error('Windows Original Filename change failed!!!');
    rethrow;
  }
}
