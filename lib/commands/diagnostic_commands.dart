import 'dart:io';

import '../utils/profile_schema.dart';

import 'package:args/command_runner.dart';

import '../custom_exceptions.dart';
import '../enums.dart';
import '../models/commands_calls_models/configure_command_model.dart';
import '../src/clonify_core.dart';
import '../utils/clonify_helpers.dart';
import '../utils/configuration_preflight.dart';
import '../utils/file_tree_checkpoint.dart';
import '../utils/firebase_manager.dart';
import '../utils/profile_identity.dart';
import '../utils/project_lock.dart';

void printConfigurePlan(ConfigurePlan plan, String clientId) {
  print('Profile: $clientId');
  print('Application: ${plan.config['appName']}');
  print('Android package: ${androidPackageName(plan.config)}');
  print('iOS bundle ID: ${iosPackageName(plan.config)}');
  print(
    'Firebase project: ${plan.config['firebaseProjectId'] ?? '(disabled)'}',
  );
  print('Firebase source: ${plan.firebaseMode.name}');
  for (final step in plan.steps) {
    print('  - $step');
  }
  for (final warning in plan.warnings) {
    print('Warning: $warning');
  }
  print(
    'Preflight passed. Online permissions, tool execution, and generated outputs are verified when the command runs.',
  );
}

/// Local diagnostics, without generators, writes, or cloud registrations.
class DoctorCommand extends Command<void> {
  DoctorCommand() {
    argParser.addClientIdOption(mandatory: false);
  }

  @override
  String get name => 'doctor';
  @override
  String get description =>
      'Validate settings and profile requirements without changing project files.';

  @override
  Future<void> run() async {
    if (!validatedClonifySettings()) {
      throw CustomException(
        'Fix clonify/clonify_settings.yaml before retrying doctor.',
      );
    }
    final provided = argResults?.clientId;
    final directory = Directory('clonify/clones');
    final clients = provided != null
        ? [provided]
        : directory.existsSync()
        ? directory
              .listSync(followLinks: false)
              .whereType<Directory>()
              .map(
                (dir) =>
                    dir.uri.pathSegments.where((part) => part.isNotEmpty).last,
              )
              .toList()
        : <String>[];
    clients.sort();
    if (clients.isEmpty) {
      throw CustomException(
        'No profiles found in clonify/clones. Run clonify create first.',
      );
    }
    final failures = <String>[];
    for (final client in clients) {
      try {
        final plan = inspectConfigure(
          ConfigureCommandModel()
            ..clientId = client
            ..skipAll = true,
        );
        printConfigurePlan(plan, client);
      } catch (error) {
        failures.add('$client: $error');
      }
    }
    if (failures.isNotEmpty) throw CustomException(failures.join('\n\n'));
  }
}

class RecoverCommand extends Command<void> {
  @override
  String get name => 'recover';
  @override
  String get description =>
      'Restore project files after an interrupted Clonify operation.';

  @override
  Future<void> run() async {
    final recovered = await recoverProject();
    print(
      recovered
          ? 'Recovery completed. Any remote Firebase registrations or uploads remain unchanged.'
          : 'No pending recovery.',
    );
  }
}

class FirebaseCommand extends Command<void> {
  FirebaseCommand() {
    addSubcommand(FirebaseRefreshCommand());
  }
  @override
  String get name => 'firebase';
  @override
  String get description =>
      'Manage saved Firebase configuration for a profile.';
}

class FirebaseRefreshCommand extends Command<void> {
  FirebaseRefreshCommand() {
    argParser.addClientIdOption(mandatory: false);
  }
  @override
  String get name => 'refresh';
  @override
  String get description =>
      'Fetch fresh Firebase app configuration for the active profile and replace its cache.';

  @override
  Future<void> run() => withProjectLock(() async {
    assertNoPendingRecovery();
    final clientId = argResults?.clientId ?? await getLastClientId();
    if (clientId == null) {
      throw CustomException('Provide --clientId or configure a profile first.');
    }
    final config = readCloneProfile(clientId);
    final settings = getClonifySettings();
    if (!settings.firebaseEnabled) {
      throw CustomException(
        'Enable Firebase in clonify/clonify_settings.yaml before refreshing.',
      );
    }
    assertProfileIdentity(
      clientId,
      config,
      android: true,
      ios: true,
      checkFirebase: false,
      checkShorebird: false,
      checkVersion: false,
    );
    inspectFirebase(config, clientId, settings, refresh: true);
    await runConfigureTransaction(() async {
      await addFirebaseToApp(
        clientId: clientId,
        firebaseProjectId: config['firebaseProjectId'] as String,
        packageName: androidPackageName(config),
        iosPackageName: iosPackageName(config),
        firebaseServiceAccount: config['firebaseServiceAccount'] as String?,
        refresh: true,
      );
      assertProfileIdentity(
        clientId,
        config,
        android: true,
        ios: true,
        checkShorebird: false,
        checkVersion: false,
      );
    }, roots: {...configureMutableRoots, settings.firebaseSettingsFilePath});
    print('Firebase configuration and cache refreshed for "$clientId".');
  });
}
