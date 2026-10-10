import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../custom_exceptions.dart';

const firebaseApplicationConfigPaths = <String>[
  'lib/firebase_options.dart',
  'android/app/google-services.json',
  'ios/Runner/GoogleService-Info.plist',
];

/// Checks all Android, iOS, and Dart app settings before a clone is accepted.
void assertFirebaseConfiguration(
  String projectId,
  String packageName, {
  String? iosPackageName,
  String directory = '.',
  String firebaseSettingsFilePath = 'firebase.json',
}) {
  readFirebaseConfiguration(
    projectId,
    packageName,
    iosPackageName: iosPackageName,
    directory: directory,
    firebaseSettingsFilePath: firebaseSettingsFilePath,
  );
}

/// FlutterFire writes root firebase.json. Merge its Flutter metadata into the
/// configured settings file before validation, keeping deployment settings.
void syncFlutterFireMetadata({
  String directory = '.',
  required String firebaseSettingsFilePath,
}) {
  final canonicalPath = p.normalize(
    p.absolute(p.join(directory, 'firebase.json')),
  );
  final configuredPath = p.normalize(
    p.absolute(firebaseConfigurationPath(directory, firebaseSettingsFilePath)),
  );
  if (canonicalPath == configuredPath) return;

  final source = firebaseJsonObject(
    readFirebasePublicConfigFile(canonicalPath),
    'firebase.json',
  );
  final flutter = firebaseObject(source['flutter'], 'flutter');
  final target = File(configuredPath);
  final metadata =
      FileSystemEntity.typeSync(configuredPath, followLinks: false) ==
          FileSystemEntityType.notFound
      ? <String, dynamic>{}
      : firebaseJsonObject(
          readFirebasePublicConfigFile(configuredPath),
          'configured Firebase settings',
        );
  metadata['flutter'] = flutter;
  final text = const JsonEncoder.withIndent('  ').convert(metadata);
  target.parent.createSync(recursive: true);
  target.writeAsStringSync('$text\n');
}

/// Restores public app settings without a Firebase login. A missing cache
/// returns false; an incomplete or mismatched cache fails before any writes.
bool restoreFirebaseConfiguration({
  required String clientId,
  required String firebaseProjectId,
  required String packageName,
  String? iosPackageName,
  String directory = '.',
  String firebaseSettingsFilePath = 'firebase.json',
  String clonesDirectory = 'clonify/clones',
}) {
  final cache = firebaseConfigurationCacheDirectory(
    clientId,
    directory: directory,
    clonesDirectory: clonesDirectory,
  );
  if (FileSystemEntity.typeSync(cache.path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    return false;
  }
  late final ({Map<String, String> contents, Map<String, dynamic> flutter})
  configuration;
  try {
    assertFirebaseCacheFiles(cache);
    configuration = readFirebaseConfiguration(
      firebaseProjectId,
      packageName,
      iosPackageName: iosPackageName,
      directory: cache.path,
    );
    final cachedMetadata = firebaseJsonObject(
      readFirebasePublicConfigFile(p.join(cache.path, 'firebase.json')),
      'cached firebase.json',
    );
    if (cachedMetadata.length != 1 || !cachedMetadata.containsKey('flutter')) {
      throw CustomException(
        'Firebase cache may contain only Flutter metadata.',
      );
    }
  } on CustomException catch (error) {
    throw CustomException(
      '${error.message} Re-run clonify configure --clientId $clientId '
      '--refreshFirebase after fixing any unsafe cache files.',
    );
  }
  final (:contents, :flutter) = configuration;

  // Parse the destination first so bad deployment JSON cannot cause a partial
  // restore. The configure transaction handles filesystem write failures.
  final targetMetadata = File(
    firebaseConfigurationPath(directory, firebaseSettingsFilePath),
  );
  final metadata = targetMetadata.existsSync()
      ? firebaseJsonObject(
          targetMetadata.readAsStringSync(),
          targetMetadata.path,
        )
      : <String, dynamic>{};
  metadata['flutter'] = flutter;
  final metadataText = const JsonEncoder.withIndent('  ').convert(metadata);

  for (final entry in contents.entries) {
    final destination = File(p.join(directory, entry.key));
    destination.parent.createSync(recursive: true);
    destination.writeAsStringSync(entry.value);
  }
  targetMetadata.parent.createSync(recursive: true);
  targetMetadata.writeAsStringSync('$metadataText\n');
  return true;
}

/// Saves only validated public app settings. Staging and renaming prevent an
/// interrupted save from replacing a good cache with half a configuration.
void saveFirebaseConfiguration({
  required String clientId,
  required String firebaseProjectId,
  required String packageName,
  String? iosPackageName,
  String directory = '.',
  String firebaseSettingsFilePath = 'firebase.json',
  String clonesDirectory = 'clonify/clones',
}) {
  final (:contents, :flutter) = readFirebaseConfiguration(
    firebaseProjectId,
    packageName,
    iosPackageName: iosPackageName,
    directory: directory,
    firebaseSettingsFilePath: firebaseSettingsFilePath,
  );
  final cache = firebaseConfigurationCacheDirectory(
    clientId,
    directory: directory,
    clonesDirectory: clonesDirectory,
  );
  final cacheType = FileSystemEntity.typeSync(cache.path, followLinks: false);
  if (cacheType != FileSystemEntityType.notFound) {
    assertFirebaseCacheFiles(cache);
  }
  cache.parent.createSync(recursive: true);
  final staged = cache.parent.createTempSync('.firebase-stage-');
  Directory? previous;
  var installed = false;
  try {
    for (final entry in contents.entries) {
      File(p.join(staged.path, entry.key))
        ..createSync(recursive: true)
        ..writeAsStringSync(entry.value);
    }
    File(p.join(staged.path, 'firebase.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'flutter': flutter})}\n',
    );
    if (cache.existsSync()) {
      final backup = cache.parent.createTempSync('.firebase-previous-');
      backup.deleteSync();
      previous = cache.renameSync(backup.path);
    }
    try {
      staged.renameSync(cache.path);
      installed = true;
    } catch (_) {
      previous?.renameSync(cache.path);
      previous = null;
      rethrow;
    }
  } finally {
    if (staged.existsSync()) staged.deleteSync(recursive: true);
    if (installed && (previous?.existsSync() ?? false)) {
      previous!.deleteSync(recursive: true);
    }
  }
}

Directory firebaseConfigurationCacheDirectory(
  String clientId, {
  String directory = '.',
  String clonesDirectory = 'clonify/clones',
}) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]*$').hasMatch(clientId)) {
    throw CustomException('Invalid Firebase cache client ID.');
  }
  return Directory(
    p.join(
      firebaseConfigurationPath(directory, clonesDirectory),
      clientId,
      'firebase',
    ),
  );
}

String firebaseConfigurationPath(String directory, String path) {
  return p.isAbsolute(path) ? path : p.join(directory, path);
}

void assertFirebaseCacheFiles(Directory cache) {
  if (FileSystemEntity.typeSync(cache.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw CustomException('Firebase cache must be a regular directory.');
  }
  final allowedFiles = {
    'firebase.json',
    ...firebaseApplicationConfigPaths.map(p.normalize),
  };
  final allowedDirectories = {
    for (final file in firebaseApplicationConfigPaths)
      ...p
          .split(p.dirname(file))
          .asMap()
          .entries
          .map(
            (entry) => p.joinAll(p.split(p.dirname(file)).take(entry.key + 1)),
          ),
  };
  for (final entity in cache.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: cache.path);
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.directory &&
        allowedDirectories.contains(relative)) {
      continue;
    }
    if (type == FileSystemEntityType.file && allowedFiles.contains(relative)) {
      readFirebasePublicConfigFile(entity.path, allowEmpty: true);
      continue;
    }
    throw CustomException(
      'Unexpected file or link in Firebase cache: $relative',
    );
  }
}

({Map<String, String> contents, Map<String, dynamic> flutter})
readFirebaseConfiguration(
  String projectId,
  String packageName, {
  String? iosPackageName,
  String directory = '.',
  String firebaseSettingsFilePath = 'firebase.json',
}) {
  if (projectId.trim().isEmpty || packageName.trim().isEmpty) {
    throw CustomException('Firebase project ID and package name are required.');
  }
  final contents = {
    for (final path in firebaseApplicationConfigPaths)
      path: readFirebasePublicConfigFile(p.join(directory, path)),
  };
  final android = firebaseJsonObject(
    contents['android/app/google-services.json']!,
    'google-services.json',
  );
  final projectInfo = firebaseObject(android['project_info'], 'project_info');
  assertFirebaseSetting(
    projectInfo['project_id'],
    projectId,
    'Android project',
  );
  final sender = firebaseString(
    projectInfo['project_number'],
    'project_number',
  );
  if (!RegExp(r'^\d+$').hasMatch(sender)) {
    throw CustomException('Firebase project_number must contain digits.');
  }
  final clients = android['client'];
  if (clients is! List || clients.isEmpty) {
    throw CustomException('google-services.json has no Android clients.');
  }
  Map<String, dynamic>? selectedAndroid;
  for (final value in clients) {
    final client = firebaseObject(value, 'Android client');
    final info = firebaseObject(client['client_info'], 'client_info');
    assertFirebaseAppId(info['mobilesdk_app_id'], 'android', sender);
    final native = firebaseObject(
      info['android_client_info'],
      'android_client_info',
    );
    final nativePackage = firebaseString(
      native['package_name'],
      'package_name',
    );
    if (nativePackage == packageName) {
      if (selectedAndroid != null) {
        throw CustomException(
          'Duplicate Firebase Android package: $packageName',
        );
      }
      selectedAndroid = client;
    }
  }
  if (selectedAndroid == null) {
    throw CustomException(
      'Firebase Android package does not match $packageName.',
    );
  }
  final androidAppId = firebaseObject(
    selectedAndroid['client_info'],
    'client_info',
  )['mobilesdk_app_id'];
  final ios = firebasePlistStrings(
    contents['ios/Runner/GoogleService-Info.plist']!,
  );
  assertFirebaseSetting(ios['PROJECT_ID'], projectId, 'iOS project');
  assertFirebaseSetting(
    ios['BUNDLE_ID'],
    iosPackageName ?? packageName,
    'iOS bundle ID',
  );
  assertFirebaseSetting(ios['GCM_SENDER_ID'], sender, 'iOS sender ID');
  assertFirebaseAppId(ios['GOOGLE_APP_ID'], 'ios', sender);

  final options = firebaseDartOptions(contents['lib/firebase_options.dart']!);
  for (final platform in ['android', 'ios']) {
    final fields = options[platform]!;
    assertFirebaseSetting(
      fields['projectId'],
      projectId,
      'Dart $platform project',
    );
    assertFirebaseSetting(
      fields['messagingSenderId'],
      sender,
      'Dart $platform sender ID',
    );
    assertFirebaseSetting(
      fields['appId'],
      platform == 'android' ? androidAppId : ios['GOOGLE_APP_ID'],
      'Dart $platform app ID',
    );
    firebaseString(fields['apiKey'], 'Dart $platform API key');
  }
  assertFirebaseSetting(
    options['ios']!['iosBundleId'],
    iosPackageName ?? packageName,
    'Dart iOS bundle ID',
  );
  assertFirebaseSetting(
    options['ios']!['apiKey'],
    ios['API_KEY'],
    'iOS API key',
  );
  final androidApiKeys = selectedAndroid['api_key'];
  if (androidApiKeys is! List ||
      !androidApiKeys.any(
        (key) =>
            key is Map && key['current_key'] == options['android']!['apiKey'],
      )) {
    throw CustomException(
      'Dart Android API key does not match google-services.json.',
    );
  }

  final metadata = firebaseJsonObject(
    readFirebasePublicConfigFile(
      firebaseConfigurationPath(directory, firebaseSettingsFilePath),
    ),
    'firebase.json',
  );
  final flutter = firebaseObject(metadata['flutter'], 'flutter');
  final platforms = firebaseObject(flutter['platforms'], 'flutter platforms');
  if (platforms.keys.toSet().difference({
    'android',
    'ios',
    'dart',
  }).isNotEmpty) {
    throw CustomException(
      'Firebase cache supports Android and iOS configurations only.',
    );
  }
  for (final platform in ['android', 'ios']) {
    final platformMetadata = firebaseObject(
      platforms[platform],
      '$platform metadata',
    );
    if (platformMetadata.length != 1 ||
        !platformMetadata.containsKey('default')) {
      throw CustomException(
        'Firebase cache requires the default $platform configuration.',
      );
    }
    final config = firebaseObject(
      platformMetadata['default'],
      '$platform default',
    );
    assertFirebaseSetting(
      config['projectId'],
      projectId,
      '$platform metadata project',
    );
    assertFirebaseSetting(
      config['appId'],
      options[platform]!['appId'],
      '$platform metadata app ID',
    );
    assertFirebaseSetting(
      config['fileOutput'],
      platform == 'android'
          ? firebaseApplicationConfigPaths[1]
          : firebaseApplicationConfigPaths[2],
      '$platform metadata fileOutput',
    );
  }
  final dart = firebaseObject(platforms['dart'], 'dart metadata');
  if (dart.length != 1 ||
      !dart.containsKey(firebaseApplicationConfigPaths[0])) {
    throw CustomException(
      'Firebase Dart metadata must target lib/firebase_options.dart.',
    );
  }
  final dartConfig = firebaseObject(
    dart[firebaseApplicationConfigPaths[0]],
    'Dart configuration',
  );
  assertFirebaseSetting(
    dartConfig['projectId'],
    projectId,
    'Dart metadata project',
  );
  final configurations = firebaseObject(
    dartConfig['configurations'],
    'Dart platform app IDs',
  );
  if (configurations.length != 2) {
    throw CustomException(
      'Firebase Dart metadata must include only Android and iOS.',
    );
  }
  for (final platform in ['android', 'ios']) {
    assertFirebaseSetting(
      configurations[platform],
      options[platform]!['appId'],
      'Dart $platform metadata app ID',
    );
  }
  return (contents: contents, flutter: flutter);
}

String readFirebasePublicConfigFile(String path, {bool allowEmpty = false}) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw CustomException('Missing regular Firebase configuration file: $path');
  }
  String content;
  try {
    content = File(path).readAsStringSync();
  } on FormatException {
    throw CustomException(
      'Firebase configuration must contain UTF-8 text: $path',
    );
  }
  if (!allowEmpty && content.trim().isEmpty) {
    throw CustomException('Firebase configuration is empty: $path');
  }
  if (RegExp(
    r'private_key|service_account|-----BEGIN PRIVATE KEY-----',
    caseSensitive: false,
  ).hasMatch(content)) {
    throw CustomException(
      'Private credentials cannot be stored in Firebase app configuration.',
    );
  }
  return content;
}

Map<String, dynamic> firebaseJsonObject(String text, String label) {
  try {
    return firebaseObject(jsonDecode(text), label);
  } on FormatException {
    throw CustomException('Invalid JSON in Firebase $label.');
  }
}

Map<String, dynamic> firebaseObject(Object? value, String label) {
  if (value is! Map<String, dynamic>) {
    throw CustomException('Missing or invalid Firebase $label.');
  }
  return value;
}

String firebaseString(Object? value, String label) {
  if (value is! String || value.trim().isEmpty) {
    throw CustomException('Missing or invalid Firebase $label.');
  }
  return value;
}

void assertFirebaseSetting(Object? actual, Object? expected, String label) {
  firebaseString(expected, label);
  if (actual != expected) {
    throw CustomException(
      'Firebase $label does not match the selected project and package.',
    );
  }
}

void assertFirebaseAppId(Object? value, String platform, String sender) {
  final appId = firebaseString(value, '$platform app ID');
  if (!RegExp('^1:$sender:$platform:[a-fA-F0-9]+\$').hasMatch(appId)) {
    throw CustomException(
      'Firebase $platform app ID does not match its project number.',
    );
  }
}

Map<String, String> firebasePlistStrings(String text) {
  final withoutComments = text.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
  final document = RegExp(
    r'^\s*(?:<\?xml[^?]*\?>\s*)?(?:<!DOCTYPE[^>]*>\s*)?<plist\s+version="1\.0">\s*<dict>([\s\S]*?)</dict>\s*</plist>\s*$',
  ).firstMatch(withoutComments);
  if (document == null) {
    throw CustomException('Invalid Firebase iOS plist.');
  }
  final values = <String, String>{};
  final seenKeys = <String>{};
  final entries = RegExp(
    r'<key>\s*([^<]+?)\s*</key>\s*(?:<string>([^<]*)</string>|<(true|false)\s*/>|<(true|false)>\s*</\4>)',
  );
  final body = document[1]!;
  for (final match in entries.allMatches(body)) {
    final key = decodeFirebaseXmlString(match[1]!);
    if (!seenKeys.add(key)) {
      throw CustomException('Duplicate Firebase iOS plist key.');
    }
    if (match[2] != null) values[key] = decodeFirebaseXmlString(match[2]!);
  }
  if (body.replaceAll(entries, '').trim().isNotEmpty) {
    throw CustomException('Invalid Firebase iOS plist entries.');
  }
  return values;
}

String decodeFirebaseXmlString(String value) {
  return value.replaceAllMapped(RegExp(r'&[^;\s]*;|&'), (match) {
    final entity = match[0]!;
    final simple = {
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&apos;': "'",
    };
    if (simple.containsKey(entity)) return simple[entity]!;
    final number = RegExp(r'^&#(x[0-9a-fA-F]+|[0-9]+);$')
        .firstMatch(entity)?[1];
    if (number != null) {
      final code = number.startsWith('x')
          ? int.parse(number.substring(1), radix: 16)
          : int.parse(number);
      if (code > 0 && code <= 0x10FFFF && (code < 0xD800 || code > 0xDFFF)) {
        return String.fromCharCode(code);
      }
    }
    throw CustomException('Invalid XML entity in Firebase iOS plist.');
  });
}

Map<String, Map<String, String>> firebaseDartOptions(String source) {
  // Tokenize comments separately from strings so commented-out options do not
  // accidentally validate a stale generated file.
  final text = source.replaceAllMapped(
    RegExp(
      r'''('(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*")|//[^\n]*|/\*[\s\S]*?\*/''',
    ),
    (match) => match[1] ?? '',
  );
  final options = <String, Map<String, String>>{};
  final declarations = RegExp(
    r'\bstatic\s+const\s+FirebaseOptions\s+(\w+)\s*=\s*(?:const\s+)?FirebaseOptions\s*\(([^)]*)\)\s*;',
  );
  for (final match in declarations.allMatches(text)) {
    final platform = match[1]!;
    if (platform != 'android' && platform != 'ios') {
      throw CustomException(
        'Firebase cache supports Android and iOS Dart options only.',
      );
    }
    if (options.containsKey(platform)) {
      throw CustomException('Duplicate Firebase Dart platform options.');
    }
    final fields = <String, String>{};
    final body = match[2]!;
    final fieldPattern = RegExp(r'''(\w+)\s*:\s*(['"])([^'"\\\r\n]*)\2\s*,?''');
    for (final field in fieldPattern.allMatches(body)) {
      if (fields.containsKey(field[1])) {
        throw CustomException('Duplicate Firebase Dart option.');
      }
      fields[field[1]!] = field[3]!;
    }
    if (body.replaceAll(fieldPattern, '').trim().isNotEmpty) {
      throw CustomException('Unsupported Firebase Dart options format.');
    }
    options[platform] = fields;
  }
  if (!options.containsKey('android') || !options.containsKey('ios')) {
    throw CustomException(
      'Firebase Dart options must include Android and iOS.',
    );
  }
  return options;
}
