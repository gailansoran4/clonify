import 'dart:convert';
import 'dart:io';

import 'profile_schema.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../custom_exceptions.dart';
import '../src/clonify_core.dart';
import 'android_signing_manager.dart';
import 'clone_config_generator.dart';
import 'clone_configure_validator.dart';
import 'configuration_preflight.dart';
import 'firebase_config_cache.dart';
import 'shorebird_manager.dart';

/// Verifies the profile against the files that Flutter will actually build.
/// Confirmation flags never bypass this check.
void assertProfileIdentity(
  String clientId,
  Map<String, dynamic> config, {
  required bool android,
  required bool ios,
  bool requireSelected = true,
  bool checkFirebase = true,
  bool checkShorebird = true,
  bool checkVersion = true,
}) {
  final settings = getClonifySettings();
  final package = androidPackageName(config);
  final iosPackage = iosPackageName(config);
  void mismatch(String message) => throw CustomException(
    '$message Run clonify configure --clientId $clientId before building or uploading.',
  );
  if (requireSelected) {
    final configured = File('clonify/active_profile.json');
    if (!configured.existsSync()) {
      mismatch(
        'This profile needs a verified configure with the current Clonify version.',
      );
    }
    final Object? receipt;
    try {
      receipt = jsonDecode(configured.readAsStringSync());
    } on FormatException {
      mismatch('The active profile record is invalid.');
      rethrow;
    }
    if (receipt is Map && receipt['clientId'] != clientId) {
      mismatch('The selected profile is not "$clientId".');
    }
    if (receipt is! Map ||
        receipt['clientId'] != clientId ||
        receipt['profile'] != profileFingerprint(config)) {
      mismatch(
        'The profile configuration changed after the last successful configure.',
      );
    }
  }
  assertBundleIdMatches(
    shorebirdArgs: [if (android) 'android', if (ios) 'ios'],
    expectedPackageName: package,
    expectedIosPackageName: iosPackage,
  );
  final generated = File('lib/generated/clone_configs.dart');
  if (!generated.existsSync()) {
    mismatch('Generated clone configuration is missing.');
  }
  final content = generated.readAsStringSync();
  for (final field in [
    'clientId',
    'androidPackageName',
    'iosPackageName',
    'appName',
    'version',
  ]) {
    final value = config[field]?.toString() ?? '';
    final encoded = dartString(value);
    if (!content.contains('static const String $field = $encoded;')) {
      mismatch('Generated $field does not match profile "$clientId".');
    }
  }
  if (checkVersion && readProjectPubspec()['version'] != config['version']) {
    mismatch('pubspec.yaml version does not match profile "$clientId".');
  }
  if (checkFirebase &&
      settings.firebaseEnabled &&
      trimmedConfigString(config['firebaseProjectId']) != null) {
    final project = trimmedConfigString(config['firebaseProjectId']);
    if (project == null) mismatch('The profile is missing firebaseProjectId.');
    assertFirebaseConfiguration(
      project!,
      package,
      iosPackageName: iosPackage,
      firebaseSettingsFilePath: settings.firebaseSettingsFilePath,
    );
  }
  if (checkShorebird &&
      settings.shorebirdEnabled &&
      trimmedConfigString(config['shorebirdAppId']) != null) {
    final appId = resolveShorebirdAppId(config);
    if (appId.isEmpty) mismatch('The profile is missing shorebirdAppId.');
    assertShorebirdAppIdMatches(appId);
  }
  if (android && androidSigningIsRequired(clientId, config)) {
    assertAndroidSigningSource(clientId, config);
    assertAndroidSigningOutputs(clientId, config);
    final name = resolveAndroidKeystoreFileName(config);
    if (fileDigest(p.join(cloneAndroidSigningDir(clientId), name)) !=
        fileDigest(p.join('android', name))) {
      mismatch('The active Android keystore belongs to a different profile.');
    }
    final source = parseAndroidKeyProperties(
      File(
        p.join(
          cloneAndroidSigningDir(clientId),
          resolveAndroidKeyPropertiesFileName(config),
        ),
      ).readAsStringSync(),
    );
    final active = parseAndroidKeyProperties(
      File('android/key.properties').readAsStringSync(),
    );
    for (final key in requiredAndroidKeyPropertyKeys) {
      if (source[key] != active[key]) {
        mismatch(
          'Android signing properties do not match profile "$clientId".',
        );
      }
    }
  }
}

String fileDigest(String path) =>
    sha256.convert(File(path).readAsBytesSync()).toString();

String buildReceiptPath(String clientId) =>
    '.dart_tool/clonify/builds/$clientId.json';

Map<String, dynamic> readBuildReceipts(String clientId) {
  final file = File(buildReceiptPath(clientId));
  if (!file.existsSync()) return {};
  try {
    final data = jsonDecode(file.readAsStringSync());
    if (data is Map<String, dynamic>) return data;
  } on FormatException {
    /* Treat a corrupt receipt as an unverified build. */
  }
  return {};
}

void writeBuildReceipts(String clientId, Map<String, dynamic> receipts) {
  final file = File(buildReceiptPath(clientId));
  file.parent.createSync(recursive: true);
  final staged = File('${file.path}.tmp');
  staged.writeAsStringSync(jsonEncode(receipts), flush: true);
  staged.renameSync(file.path);
}

String profileFingerprint(Map<String, dynamic> config) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  // Credential location is local tooling metadata, never part of an app build.
  final publicConfig = normalizeProfile(config)
    ..remove('firebaseServiceAccount');
  return sha256
      .convert(utf8.encode(jsonEncode(canonical(publicConfig))))
      .toString();
}

Future<void> recordBuild(
  String clientId,
  Map<String, dynamic> config,
  String platform,
  String artifact,
) async {
  requireFile(artifact);
  if (File(artifact).lengthSync() == 0) {
    throw CustomException('Build produced an empty artifact: $artifact');
  }
  final receipts = readBuildReceipts(clientId);
  receipts[platform] = {
    'clientId': clientId,
    'profile': profileFingerprint(config),
    'artifact': p.normalize(artifact),
    'sha256': await artifactDigest(artifact),
    'version': config['version'],
  };
  writeBuildReceipts(clientId, receipts);
}

Future<String> assertVerifiedBuild(
  String clientId,
  Map<String, dynamic> config,
  String platform,
) async {
  final receipt = readBuildReceipts(clientId)[platform];
  if (receipt is! Map ||
      receipt['clientId'] != clientId ||
      receipt['profile'] != profileFingerprint(config) ||
      receipt['artifact'] is! String ||
      receipt['sha256'] is! String) {
    throw CustomException(
      'No verified $platform build for "$clientId". Run clonify build for this profile before uploading.',
    );
  }
  final path = receipt['artifact'] as String;
  if (!p.isWithin(p.absolute('build'), p.absolute(path))) {
    throw CustomException(
      'Invalid build artifact path. Rebuild with clonify build.',
    );
  }
  requireFile(path);
  if (await artifactDigest(path) != receipt['sha256']) {
    throw CustomException(
      'Build artifact changed after building: $path. Rebuild this profile before uploading.',
    );
  }
  return path;
}

Future<String> artifactDigest(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

/// A successful configure binds all profile values (including custom values)
/// to the active project. Editing the profile requires configuring it again.
void recordConfiguredProfile(String clientId, Map<String, dynamic> config) {
  final file = File('clonify/active_profile.json');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(
    jsonEncode({
      'schema': 1,
      'clientId': clientId,
      'profile': profileFingerprint(config),
    }),
    flush: true,
  );
}
