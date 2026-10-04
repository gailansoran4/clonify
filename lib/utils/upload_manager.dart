import 'dart:io';

import '../custom_exceptions.dart';
import '../src/clonify_core.dart';
import 'clonify_helpers.dart';
import 'command_process.dart';
import 'configuration_preflight.dart';
import 'file_tree_checkpoint.dart';
import 'profile_identity.dart';
import 'project_lock.dart';

/// Verifies every requested upload before any publishing starts. Local Fastfile
/// edits roll back on failure; completed remote uploads cannot be undone here.
Future<void> uploadApps(
  String clientId, {
  bool skipAll = false,
  bool skipAndroidUploadCheck = false,
  bool skipIOSUploadCheck = false,
  bool uploadAndroid = true,
  bool uploadIOS = true,
}) => withProjectLock(() async {
  assertNoPendingRecovery();
  final config = readCloneProfile(clientId);
  if (!getClonifySettings().fastlaneEnabled) {
    throw CustomException(
      'Fastlane is disabled in clonify/clonify_settings.yaml. Enable it before uploading.',
    );
  }
  final android =
      uploadAndroid &&
      (skipAll ||
          skipAndroidUploadCheck ||
          prompt('Upload the Android AAB? (y/n):').toLowerCase() == 'y');
  final ios =
      uploadIOS &&
      (skipAll ||
          skipIOSUploadCheck ||
          prompt('Upload the iOS IPA? (y/n):').toLowerCase() == 'y');
  if (!android && !ios) throw const CommandCancelled();
  assertProfileIdentity(clientId, config, android: android, ios: ios);
  assertToolAvailable('fastlane');
  final uploads =
      <
        ({String platform, String artifact, String fastfile, String contents})
      >[];
  for (final platform in [if (android) 'android', if (ios) 'ios']) {
    final artifact = await assertVerifiedBuild(
      clientId,
      config,
      platform == 'android' ? 'appbundle' : 'ipa',
    );
    final fastfile = '$platform/fastlane/Fastfile';
    assertProjectPath(fastfile);
    requireFile(fastfile);
    final version = config['version'] as String;
    uploads.add((
      platform: platform,
      artifact: artifact,
      fastfile: fastfile,
      contents: renderFastlaneFile(
        fastlanePath: fastfile,
        bundleId: config['packageName'] as String,
        appVersion: version.split('+').first,
        appVersionCode: platform == 'android' ? version.split('+').last : null,
        artifact: File(artifact).absolute.path,
        platform: platform,
      ),
    ));
  }
  final completed = <String>[];
  try {
    await runConfigureTransaction(() async {
      for (final upload in uploads) {
        checkCommandCancellation();
        File(upload.fastfile).writeAsStringSync(upload.contents);
        logger.i(
          'Uploading verified ${upload.platform} artifact: ${upload.artifact}',
        );
        await executeCommand(
          'fastlane',
          ['upload'],
          workingDirectory: upload.platform,
          inheritStdio: true,
          environment: {
            if (upload.platform == 'ios')
              'CLONIFY_IPA_PATH': File(upload.artifact).absolute.path,
            if (upload.platform == 'android')
              'CLONIFY_AAB_PATH': File(upload.artifact).absolute.path,
          },
        );
        completed.add(upload.platform);
        logger.i('Uploaded ${upload.platform} for "$clientId".');
      }
    }, roots: configureMutableRoots);
  } catch (error) {
    final status = completed.isEmpty
        ? 'No upload was confirmed complete.'
        : 'Already uploaded: ${completed.join(', ')}.';
    throw CustomException(
      '$error\n$status An interrupted upload may have reached the store; check store status before retrying. Remote uploads are not rolled back.',
    );
  }
});

String renderFastlaneFile({
  required String fastlanePath,
  required String bundleId,
  required String appVersion,
  String? appVersionCode,
  String? artifact,
  String? platform,
}) {
  requireFile(fastlanePath);
  var content = File(fastlanePath).readAsStringSync();
  final values = {
    'bundleId': bundleId,
    'app_version': appVersion,
    if (appVersionCode != null) 'app_version_code': appVersionCode,
  };
  for (final entry in values.entries) {
    final pattern = RegExp(
      '^([ \\t]*)${entry.key}\\s*=\\s*["\\\'].*?["\\\']',
      multiLine: true,
    );
    if (!pattern.hasMatch(content)) {
      throw CustomException(
        '$fastlanePath is missing ${entry.key} = "...". Add the expected lane variable before uploading.',
      );
    }
    content = content.replaceAllMapped(
      pattern,
      (match) => '${match[1]}${entry.key} = ${rubyString(entry.value)}',
    );
  }
  if (artifact != null && platform != null) {
    final argument = platform == 'ios' ? 'ipa' : 'aab';
    // Bind the lane's explicit artifact parameter to the verified file. Refuse
    // opaque dynamic lanes, which could otherwise publish an unrelated build.
    final pattern = RegExp(
      '\\b$argument:\\s*(?:"[^"\\n]*"|\\\'[^\\\'\\n]*\\\')',
    );
    if (!pattern.hasMatch(content)) {
      throw CustomException(
        '$fastlanePath must pass a literal $argument: "path" to the upload action so Clonify can bind the verified artifact.',
      );
    }
    content = content.replaceAllMapped(
      pattern,
      (_) => '$argument: ${rubyString(artifact)}',
    );
  }
  return content;
}

String rubyString(String value) =>
    "'${value.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

Future<void> updateFastlaneFiles({
  required String fastlanePath,
  required String bundleId,
  required String appVersion,
  String? appVersionCode,
}) async {
  final contents = renderFastlaneFile(
    fastlanePath: fastlanePath,
    bundleId: bundleId,
    appVersion: appVersion,
    appVersionCode: appVersionCode,
  );
  File(fastlanePath).writeAsStringSync(contents);
}
