import 'dart:io';

import '../constants.dart';
import '../custom_exceptions.dart';
import '../models/commands_calls_models/build_command_model.dart';
import 'clonify_helpers.dart';
import 'command_process.dart';
import 'configuration_preflight.dart';
import 'file_tree_checkpoint.dart';
import 'profile_identity.dart';
import 'project_lock.dart';

/// Builds selected platforms serially. Failed or stale outputs never receive
/// upload receipts, even when an older artifact is still present on disk.
Future<void> buildApps(BuildCommandModel model) => withProjectLock(() async {
  assertNoPendingRecovery();
  final clientId = model.clientId;
  if (clientId == null) throw CustomException('Provide --clientId.');
  final config = readCloneProfile(clientId);
  if (!model.buildApk && !model.buildAab && !model.buildIpa) {
    throw CustomException('Select at least one build platform.');
  }
  if (model.buildIpa && !Platform.isMacOS) {
    throw CustomException(
      'Building an IPA requires macOS and Xcode. Use --no-buildIpa on this computer.',
    );
  }
  assertProfileIdentity(
    clientId,
    config,
    android: model.buildApk || model.buildAab,
    ios: model.buildIpa,
  );
  assertToolAvailable('flutter');
  if (!model.skipAll &&
      !model.skipBuildCheck &&
      prompt(
            'Build ${config['appName']} (${config['androidPackageName']} / ${config['iosPackageName']}) ${config['version']}? (y/n):',
          ).toLowerCase() !=
          'y') {
    throw const CommandCancelled();
  }
  final targets = [
    if (model.buildApk) 'apk',
    if (model.buildAab) 'appbundle',
    if (model.buildIpa) 'ipa',
  ];
  // Invalidate all requested receipts before starting, including later targets
  // if an earlier target fails.
  final receipts = readBuildReceipts(clientId);
  for (final target in targets) {
    receipts.remove(target);
  }
  writeBuildReceipts(clientId, receipts);
  try {
    await runConfigureTransaction(() async {
      for (final target in targets) {
        final started = DateTime.now();
        await runCommand('flutter', [
          'build',
          target,
          '--release',
          '--build-name=${(config['version'] as String).split('+').first}',
          '--build-number=${(config['version'] as String).split('+').last}',
        ]);
        final artifact = switch (target) {
          'apk' => 'build/app/outputs/flutter-apk/app-release.apk',
          'appbundle' => Constants.aabPath,
          _ => findFreshIpa(started),
        };
        requireFile(artifact);
        if (File(artifact)
            .lastModifiedSync()
            .isBefore(started.subtract(const Duration(seconds: 2)))) {
          throw CustomException(
            '$target returned success but did not produce a fresh artifact at $artifact. Rebuild before uploading.',
          );
        }
        assertProfileIdentity(
          clientId,
          config,
          android: target != 'ipa',
          ios: target == 'ipa',
        );
        await recordBuild(clientId, config, target, artifact);
        logger.i('Verified $target for "$clientId": $artifact');
      }
    });
  } catch (_) {
    final failedReceipts = readBuildReceipts(clientId);
    for (final target in targets) {
      failedReceipts.remove(target);
    }
    writeBuildReceipts(clientId, failedReceipts);
    rethrow;
  }
  logger.i('All selected builds completed for "$clientId".');
});

String findFreshIpa(DateTime started) {
  final directory = Directory('build/ios/ipa');
  final candidates = directory.existsSync()
      ? directory
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.ipa') &&
                  !file.lastModifiedSync().isBefore(
                    started.subtract(const Duration(seconds: 2)),
                  ),
            )
            .toList()
      : <File>[];
  if (candidates.length != 1) {
    throw CustomException(
      'Expected one freshly exported IPA in build/ios/ipa; found ${candidates.length}. Check Xcode export settings and rebuild.',
    );
  }
  return candidates.single.path;
}
