// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import '../custom_exceptions.dart';
import 'clonify_helpers.dart';
import 'command_process.dart';
import 'firebase_config_cache.dart';
import 'firebase_credentials.dart';

/// Returns true when the active Firebase options target [packageName].
bool firebaseOptionsMatchPackage(String packageName) {
  final optionsFile = File('lib/firebase_options.dart');
  if (!optionsFile.existsSync()) return false;
  final content = optionsFile.readAsStringSync();
  return content.contains("iosBundleId: '$packageName'") ||
      content.contains('iosBundleId: "$packageName"');
}

/// Uses an existing Firebase project or creates it with the selected identity.
Future<void> createFirebaseProject({
  required String clientId,
  required String packageName,
  String? iosPackageName,
  required String firebaseProjectId,
  String? firebaseServiceAccount,
}) async {
  if (firebaseProjectId.isEmpty) return;
  final credentialPath = resolveFirebaseServiceAccount(
    reference: firebaseServiceAccount,
  );
  await withFirebaseServiceAccount<void>(
    credentialPath: credentialPath,
    operation: (environment) async {
      final projectsResult = await executeCommand(
        'firebase',
        ['projects:list', '--json'],
        environment: environment,
        checkExitCode: false,
      );
      if (projectsResult.exitCode != 0) {
        throw CustomException(
          'Cannot list Firebase projects. Check Firebase CLI installation '
          'and your selected credential permissions.',
        );
      }
      final Object? response;
      try {
        response = jsonDecode(projectsResult.stdout as String);
      } on FormatException {
        throw CustomException('Firebase returned an invalid project list.');
      }
      if (response is! Map ||
          response['status'] != 'success' ||
          response['result'] is! List) {
        throw CustomException('Firebase returned an invalid project list.');
      }
      final projects = response['result'] as List;
      if (projects.any(
        (project) =>
            project is Map && project['projectId'] == firebaseProjectId,
      )) {
        logger.i('✅ Using existing Firebase project: $firebaseProjectId');
        return;
      }
      final result = await executeCommand(
        'firebase',
        [
          'projects:create',
          firebaseProjectId,
          '--display-name',
          toTitleCase(clientId),
          '--json',
        ],
        environment: environment,
        checkExitCode: false,
      );
      if (result.exitCode != 0) {
        throw CustomException(
          'Cannot create Firebase project $firebaseProjectId. '
          'Create it first or grant project-creation permission '
          'to the selected identity.',
        );
      }
      logger.i('✅ Firebase project created: $firebaseProjectId');
    },
  );
}

/// Restores saved Firebase files or configures and caches a clone once.
///
/// A refresh runs FlutterFire online. Skipping online setup still requires
/// matching saved or active configuration, preventing another clone's files
/// from reaching a build. Private service-account credentials stay external.
Future<void> addFirebaseToApp({
  required String clientId,
  required String firebaseProjectId,
  required String packageName,
  String? iosPackageName,
  String? firebaseServiceAccount,
  bool skip = false,
  bool refresh = false,
  Future<ProcessResult> Function(List<String>, Map<String, String>?)?
  configureCommand,
}) async {
  if (firebaseProjectId.isEmpty) return;
  if (skip && refresh) {
    throw CustomException(
      'Cannot combine --refreshFirebase with --skipFirebaseConfigure.',
    );
  }
  final firebaseJsonPath = currentClonifySettings().firebaseSettingsFilePath;
  final optionsFile = File('lib/firebase_options.dart');
  final usesFunctionAccessor =
      optionsFile.existsSync() &&
      RegExp(r'static\s+FirebaseOptions\s+currentPlatform\s*\(')
          .hasMatch(optionsFile.readAsStringSync());

  void preserveAccessor() {
    if (!usesFunctionAccessor || !optionsFile.existsSync()) return;
    final options = optionsFile.readAsStringSync();
    final updated = options.replaceFirst(
      RegExp(r'static\s+FirebaseOptions\s+get\s+currentPlatform\b'),
      'static FirebaseOptions currentPlatform()',
    );
    if (updated != options) optionsFile.writeAsStringSync(updated);
  }

  if (!refresh) {
    if (restoreFirebaseConfiguration(
      clientId: clientId,
      firebaseProjectId: firebaseProjectId,
      packageName: packageName,
      iosPackageName: iosPackageName,
      firebaseSettingsFilePath: firebaseJsonPath,
    )) {
      preserveAccessor();
      logger.i('✅ Restored saved Firebase configuration for $clientId.');
      return;
    }
    var currentConfigurationMatches = false;
    try {
      assertFirebaseConfiguration(
        firebaseProjectId,
        packageName,
        iosPackageName: iosPackageName,
        firebaseSettingsFilePath: firebaseJsonPath,
      );
      currentConfigurationMatches = true;
    } on CustomException {
      // First setup or another clone is currently selected.
    }
    if (currentConfigurationMatches) {
      saveFirebaseConfiguration(
        clientId: clientId,
        firebaseProjectId: firebaseProjectId,
        packageName: packageName,
        iosPackageName: iosPackageName,
        firebaseSettingsFilePath: firebaseJsonPath,
      );
      logger.i('✅ Saved existing Firebase configuration for $clientId.');
      return;
    }
  }

  if (skip) {
    throw CustomException(
      'No matching saved Firebase configuration for $clientId. '
      'Run configure without --skipFirebaseConfigure once to set it up.',
    );
  }

  final credentialPath = resolveFirebaseServiceAccount(
    reference: firebaseServiceAccount,
  );
  logger.i(
    '🔥 Setting up Firebase project $firebaseProjectId for $clientId...',
  );
  await withFirebaseServiceAccount<void>(
    credentialPath: credentialPath,
    operation: (environment) async {
      final arguments = <String>[
        'configure',
        '--project',
        firebaseProjectId,
        '--yes',
        '--platforms',
        'android,ios',
        '--ios-bundle-id',
        iosPackageName ?? packageName,
        '--android-package-name',
        packageName,
        if (credentialPath != null) ...['--service-account', credentialPath],
      ];
      final ProcessResult result;
      try {
        result = await (configureCommand ?? runFlutterFireConfigure)(
          arguments,
          environment,
        );
      } on ProcessException {
        throw CustomException(
          'FlutterFire could not start. Install Firebase CLI and '
          'dart pub global activate flutterfire_cli once on this computer.',
        );
      }
      if (result.exitCode != 0) {
        throw CustomException(
          'FlutterFire configuration failed (exit ${result.exitCode}). '
          'Check access to project $firebaseProjectId and your Firebase tools. '
          'Saved configuration has not been replaced.',
        );
      }
    },
  );
  preserveAccessor();
  syncFlutterFireMetadata(firebaseSettingsFilePath: firebaseJsonPath);
  saveFirebaseConfiguration(
    clientId: clientId,
    firebaseProjectId: firebaseProjectId,
    packageName: packageName,
    iosPackageName: iosPackageName,
    firebaseSettingsFilePath: firebaseJsonPath,
  );
  logger.i('✅ Firebase configuration saved for $clientId.');
}

/// Runs FlutterFire without changing the developer's saved Firebase login.
Future<ProcessResult> runFlutterFireConfigure(
  List<String> arguments,
  Map<String, String>? environment,
) => executeCommand(
  'flutterfire',
  arguments,
  environment: environment,
  checkExitCode: false,
);
