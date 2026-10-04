import 'dart:io';

import 'package:yaml_edit/yaml_edit.dart';

import '../constants.dart';
import '../src/clonify_core.dart';
import 'clonify_helpers.dart';
import 'configuration_preflight.dart';
import 'notification_icon_manager.dart';

/// Updates only installed generators and propagates every generator failure.
Future<bool> configureLauncherIconsAndSplashScreen(
  Map<String, dynamic> config,
) async {
  final pubspec = readProjectPubspec();
  final settings = getClonifySettings();
  if (hasProjectDependency(pubspec, 'flutter_launcher_icons') &&
      config['launcherIcon'] != null) {
    final file = File(Constants.flutterLauncherIconsPath);
    final editor = YamlEditor(
      file.existsSync()
          ? file.readAsStringSync()
          : Constants.flutterLauncherIconsYaml,
    );
    final image = "assets/images/${config['launcherIcon']}";
    for (final key in ['image_path', 'adaptive_icon_foreground']) {
      editor.update(['flutter_launcher_icons', key], image);
    }
    editor.update([
      'flutter_launcher_icons',
      'android',
    ], settings.updateAndroidInfo);
    editor.update(['flutter_launcher_icons', 'ios'], settings.updateIOSInfo);
    editor.update(
      ['flutter_launcher_icons', 'web'],
      {
        'generate': Directory('web').existsSync(),
        'image_path': image,
        'background_color': settings.defaultColor,
        'theme_color': settings.defaultColor,
      },
    );
    file.writeAsStringSync(editor.toString());
    await runCommand('dart', [
      'run',
      'flutter_launcher_icons',
    ], successMessage: 'Launcher icons generated.');
  }
  if (hasProjectDependency(pubspec, 'flutter_native_splash') &&
      config['splashScreen'] != null) {
    final file = File(Constants.flutterNativeSplashPath);
    final editor = YamlEditor(
      file.existsSync()
          ? file.readAsStringSync()
          : Constants.flutterNativeSplashYaml,
    );
    final color = notificationColorHexFromPrimary(
      config['backgroundSplashColor'] as String? ?? '#FFFFFF',
    )!;
    final image = "assets/images/${config['splashScreen']}";
    editor.update(['flutter_native_splash', 'color'], color);
    editor.update(['flutter_native_splash', 'image'], image);
    editor.update(['flutter_native_splash', 'android_12', 'image'], image);
    editor.update(['flutter_native_splash', 'android_12', 'color'], color);
    editor.update([
      'flutter_native_splash',
      'android',
    ], settings.updateAndroidInfo);
    editor.update(['flutter_native_splash', 'ios'], settings.updateIOSInfo);
    editor.update([
      'flutter_native_splash',
      'web',
    ], Directory('web').existsSync());
    file.writeAsStringSync(editor.toString());
    await runCommand('dart', [
      'run',
      'flutter_native_splash:create',
    ], successMessage: 'Splash screens generated.');
  }
  if (hasProjectDependency(pubspec, 'intl_utils')) {
    await runCommand('dart', [
      'run',
      'intl_utils:generate',
    ], successMessage: 'Localizations generated.');
  }
  return true;
}
