import 'dart:convert';

import '../custom_exceptions.dart';

/// Converts profile keys to public Dart field names.
String camelCaseField(String name) => snakeCaseField(name).replaceAllMapped(
  RegExp(r'_([a-zA-Z0-9])'),
  (match) => match[1]!.toUpperCase(),
);

/// Converts Dart/legacy field names to the persisted profile convention.
String snakeCaseField(String name) => name
    .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
    .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
    .toLowerCase();

/// Accepts legacy camelCase profiles while rejecting ambiguous aliases.
/// Internally keys are camelCase; disk profiles always use snake_case.
Map<String, dynamic> normalizeProfile(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  for (final entry in source.entries) {
    final key = camelCaseField(entry.key);
    if (result.containsKey(key)) {
      throw CustomException(
        'Duplicate profile field: ${snakeCaseField(key)}. Use one spelling only.',
      );
    }
    result[key] = entry.value;
  }
  // A legacy shared ID is a migration fallback, never a generated field.
  final shared = result.remove('packageName');
  if (shared != null) {
    result.putIfAbsent('androidPackageName', () => shared);
    result.putIfAbsent('iosPackageName', () => shared);
  }
  final colors = result['colors'];
  if (colors is List) {
    result['colors'] = [
      for (final color in colors)
        if (color is Map)
          {
            ...Map<String, dynamic>.from(color),
            if (color['name'] is String)
              'name': camelCaseField(color['name'] as String),
          }
        else
          color,
    ];
  }
  return result;
}

Map<String, dynamic> profileToJson(Map<String, dynamic> config) => {
  for (final entry in normalizeProfile(config).entries)
    snakeCaseField(entry.key): entry.key == 'colors' && entry.value is List
        ? [
            for (final color in entry.value as List)
              if (color is Map)
                {
                  ...color,
                  if (color['name'] is String)
                    'name': snakeCaseField(color['name'] as String),
                }
              else
                color,
          ]
        : entry.value,
};

String encodeProfile(Map<String, dynamic> config) =>
    '${const JsonEncoder.withIndent('  ').convert(profileToJson(config))}\n';

String androidPackageName(Map<String, dynamic> config) =>
    normalizeProfile(config)['androidPackageName'] as String? ?? '';

String iosPackageName(Map<String, dynamic> config) =>
    normalizeProfile(config)['iosPackageName'] as String? ?? '';
