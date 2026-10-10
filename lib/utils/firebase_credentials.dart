import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves a private credential file without copying it into the Flutter app.
///
/// References accept `env:VARIABLE`, an absolute path, or a `~/` path. When no
/// reference is configured, Clonify's environment variable takes precedence
/// over Application Default Credentials. No reference retains CLI login.
String? resolveFirebaseServiceAccount({
  String? reference,
  String? projectDirectory,
  Map<String, String>? environment,
}) {
  final variables = environment ?? Platform.environment;
  var path = reference?.trim();
  if (path == null || path.isEmpty) {
    path = variables['CLONIFY_FIREBASE_SERVICE_ACCOUNT']?.trim();
    if (path == null || path.isEmpty) {
      path = variables['GOOGLE_APPLICATION_CREDENTIALS']?.trim();
    }
  }
  if (path == null || path.isEmpty) return null;

  if (path.startsWith('env:')) {
    final variable = path.substring(4);
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(variable)) {
      throw const FormatException(
        'firebaseServiceAccount must reference an environment variable name.',
      );
    }
    path = variables[variable]?.trim();
    if (path == null || path.isEmpty) {
      throw const FormatException(
        'The firebaseServiceAccount environment variable is not set.',
      );
    }
  }

  if (path.startsWith('~/') || path.startsWith(r'~\')) {
    final homeDirectory = variables['HOME'] ?? variables['USERPROFILE'];
    if (homeDirectory == null || homeDirectory.isEmpty) {
      throw const FormatException(
        'Cannot resolve firebaseServiceAccount without a home directory.',
      );
    }
    path = p.join(homeDirectory, path.substring(2));
  }
  if (!p.isAbsolute(path)) {
    throw const FormatException(
      'firebaseServiceAccount must use env:VARIABLE, an absolute path, or ~/path.',
    );
  }

  final credentialFile = File(p.normalize(path));
  String resolvedPath;
  String projectPath;
  Object? credential;
  try {
    resolvedPath = credentialFile.resolveSymbolicLinksSync();
    projectPath = Directory(projectDirectory ?? Directory.current.path)
        .resolveSymbolicLinksSync();
    credential = jsonDecode(File(resolvedPath).readAsStringSync());
  } on FileSystemException {
    throw const FormatException(
      'Cannot read the firebaseServiceAccount credential file.',
    );
  } on FormatException {
    throw const FormatException(
      'firebaseServiceAccount must reference a valid service-account JSON file.',
    );
  }

  if (p.equals(projectPath, resolvedPath) ||
      p.isWithin(projectPath, resolvedPath) ||
      p.isWithin(
        p.normalize(p.absolute(projectDirectory ?? Directory.current.path)),
        credentialFile.path,
      )) {
    throw const FormatException(
      'Keep firebaseServiceAccount credentials outside the Flutter project.',
    );
  }
  if (credential is! Map<String, dynamic> ||
      credential['type'] != 'service_account') {
    throw const FormatException(
      'firebaseServiceAccount must reference a service_account JSON file.',
    );
  }
  for (final field in ['client_email', 'private_key']) {
    final value = credential[field];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'firebaseServiceAccount credential is missing $field.',
      );
    }
  }
  return p.normalize(resolvedPath);
}

/// Runs Firebase commands without the user's cached login taking precedence.
///
/// Pass the callback's environment to both Firebase and FlutterFire processes.
/// The temporary Configstore is discarded even when the operation fails; the
/// user's saved CLI accounts are never changed. A null credential keeps login.
Future<T> withFirebaseServiceAccount<T>({
  required String? credentialPath,
  required Future<T> Function(Map<String, String>? environment) operation,
  Map<String, String>? environment,
}) async {
  if (credentialPath == null) return operation(environment);

  final configDirectory = Directory.systemTemp.createTempSync(
    'clonify_firebase_auth_',
  );
  final variables = <String, String>{
    ...environment ?? Platform.environment,
    'GOOGLE_APPLICATION_CREDENTIALS': credentialPath,
    'XDG_CONFIG_HOME': configDirectory.path,
    'FIREBASE_TOKEN': '',
  };
  try {
    return await operation(variables);
  } finally {
    if (configDirectory.existsSync()) {
      configDirectory.deleteSync(recursive: true);
    }
  }
}
