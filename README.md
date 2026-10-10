# Clonify

![GitHub issues](https://img.shields.io/github/issues/DevMohammadSalameh/clonify)
![GitHub pull requests](https://img.shields.io/github/issues-pr/DevMohammadSalameh/clonify)
![GitHub contributors](https://img.shields.io/github/contributors/DevMohammadSalameh/clonify)
![GitHub](https://img.shields.io/github/license/DevMohammadSalameh/clonify)

## About

A powerful command-line tool for managing multiple Flutter project clones with different configurations, branding, Firebase, and Shorebird. Perfect for white-label applications or managing multiple client-specific versions of the same Flutter app.

## Features

- 🎨 Manage multiple app variants from a single codebase
- 🔥 Optional Firebase integration per clone
- 🐦 Optional Shorebird `app_id` sync per clone on `configure`
- 📱 Auto-generate launcher icons and splash screens
- 📦 Rename packages and app names per clone
- 🏗️ Build multiple platforms (Android APK/AAB, iOS IPA)
- 🚀 Optional Fastlane integration for app store uploads
- 💾 Configuration persistence for easy switching between clones
- ✨ **Modern TUI (Text User Interface)** with interactive prompts and progress indicators

## Installation

### Prerequisites

- Dart SDK (^3.13.0)
- Flutter SDK (for building apps)
- Firebase CLI (optional, for Firebase features)
- Fastlane (optional, for upload features)

### Important: Required Dev Dependencies

Clonify relies on the following packages to automate asset generation. **Add these to your Flutter project's `dev_dependencies`** for full functionality:

```yaml
dev_dependencies:
  flutter_launcher_icons: ^0.13.1  # Automated launcher icon generation
  flutter_native_splash: ^2.3.1     # Splash screen creation
  intl_utils: ^2.8.7                # Internationalization (optional)
```

**Why these are needed:**
- Clonify calls these tools as external commands to generate icons and splash screens
- Preflight checks required generators before making changes and reports missing dependencies
- You don't need to import them in your code - Clonify uses them automatically

**Note:** Package renaming functionality is now built directly into Clonify - no external package required!

### Install Globally

Install clonify globally to use it from anywhere:

```bash
# From this fork
dart pub global activate --source git https://github.com/gailansoran4/clonify.git

# Or install from a local clone
git clone https://github.com/gailansoran4/clonify.git
cd clonify
dart pub global activate --source path .
```

Make sure your PATH includes the Dart global bin directory:
- macOS/Linux: `~/.pub-cache/bin`
- Windows: `%LOCALAPPDATA%\Pub\Cache\bin`

Verify installation:
```bash
clonify --version  # or clonify -v
clonify --help
```

## User Interface

Clonify features a modern **Text User Interface (TUI)** that enhances your development experience with:

### Interactive Prompts
- 🎯 **Arrow-key navigation** for selecting options (type selection, multiple choices)
- ✅ **Smart validation** with immediate feedback for inputs (colors, URLs, package names, versions)
- 🎨 **Color-coded messages** for success (green), errors (red), warnings (yellow), and info (blue)
- 📋 **Configuration summaries** showing all settings before applying
- 🔄 **Confirmation prompts** with sensible defaults for quick workflows

### Progress Indicators
- 📦 **Package renaming** with real-time progress feedback
- 🔥 **Firebase configuration** progress tracking
- 🎨 **Asset replacement** progress updates
- 🚀 **Launcher icon generation** with completion status
- 💦 **Splash screen creation** progress
- 🌍 **Internationalization file generation** progress
- 🛠️ **Build operations** with unified progress tracking for APK/AAB/IPA

### Enhanced Commands
- **`init`** - Interactive wizard with emoji indicators and type selection
- **`create`** - Guided clone creation with validation and configuration summary
- **`list`** - Colored tables with active client highlighting and emoji column headers
- **`configure`** - Progress indicators for all long-running operations
- **`build`** - Unified build progress with elapsed time tracking

### Accessibility
- 🔌 **TTY detection** - Automatically detects terminal capabilities
- 🎛️ **Fallback mode** - Works in CI/CD and non-interactive environments
- 🚫 **`--no-tui` flag** - Disable TUI features for basic text mode
- 🎨 **`NO_COLOR` support** - Respects environment variable for color-blind accessibility
- ⏭️ **`--skipAll` flag** - Skip all interactive prompts for automation

### Examples

```bash
# Use TUI features (default)
clonify create

# Disable TUI for CI/CD environments
clonify create --no-tui

# Skip all prompts for automation
clonify configure --skipAll
```

## Quick Start

### 1. Initialize Clonify

Set up your project with global configuration:

```bash
clonify init
```

This will prompt you for:
- Firebase configuration (optional)
- Fastlane configuration (optional)
- Company name
- Default app color
- Assets selection (launcher icon, splash screen, logo)
- Custom configuration fields (optional) - define custom fields that will be required for each clone

Creates: `./clonify/clonify_settings.yaml`

### 2. Create Your First Clone

Create a new client-specific configuration:

```bash
clonify create
```

This will prompt you for:
- Client ID (unique identifier)
- Base URL for API
- Primary color
- Package name (e.g., `com.company.clienta`)
- App name
- Version
- Firebase project ID (if Firebase enabled)
- Custom field values (if custom fields were defined during init)

Creates: `./clonify/clones/{clientId}/config.json` and assets directory

### 3. Configure Your Flutter Project

Apply a clone's configuration to your Flutter project:

```bash
clonify configure --clientId your_client_id

# Or use the last configured client
clonify configure
```

This will:
- Rename app and package
- Configure Firebase (if enabled)
- Update launcher icons and splash screens
- Sync versions
- Generate compile-time configuration class
- Apply Background Geolocation licenses and Android notification icon
- Sync per-clone Android Play signing (`upload-keystore.jks` + `key.properties`)
- Back up managed project files before applying changes and restore them on
  failure (iOS, Android, version, Shorebird, Firebase, clone `config.json`).
  Interrupted operations retain a recovery journal; see `clonify recover` below.
- **Fail immediately** if required assets or licenses are missing:
  - `launcherIcon` / `splashScreen` / `logo` missing, empty, or not PNG
  - `notificationIcon` configured but the file was not generated
  - `backgroundGeolocationLicenseIos` or `backgroundGeolocationLicenseAndroid`
    missing, blank, invalid, or issued for another package/OS
  - `androidKeystore` / `androidKeyProperties` configured (or clone `android/`
    files present) but the keystore / `key.properties` is missing or invalid

Generates: `lib/generated/clone_configs.dart`
this class can be used in your project for accessing clone specific attributes. 

### 4. Build Your App

Build platform-specific artifacts:

```bash
# Build Android AAB and iOS IPA (default)
clonify build --clientId your_client_id

# Build specific platforms
clonify build --clientId your_client_id --buildApk --no-buildAab

# Use last client ID
clonify build
```

### 5. List All Clones

View all configured clones:

```bash
clonify list
```

## Validation and recovery (0.5)

Run these from the Flutter project root:

```bash
clonify doctor
clonify doctor --clientId staff
clonify configure --clientId staff --dry-run
clonify configure --clientId staff --skipAll
clonify firebase refresh --clientId staff
clonify recover
```

`doctor` checks all profiles, or the selected `--clientId`, without editing
project files or contacting Firebase. `--dry-run` checks the same local
requirements for a proposed configure command and lists its steps. Missing
assets, signing files, tools, malformed JSON/YAML, mismatched profile IDs,
invalid field types, and required service settings produce a nonzero exit.
Online authorization and tool-generated outputs are verified during execution.

A configure operation validates first, snapshots managed project files, applies
local changes, performs Firebase setup last, and verifies the result before
saving the active profile. Build and upload commands verify the active profile,
native identifiers, configured Firebase project, version, and configured Android
signing files. Confirmation flags never bypass identity checks.

On failure or cancellation, local managed files are restored. If restoration
fails, Clonify keeps the backup and prints its location. After a crash or forced
termination, stop any orphaned external tool processes and run `clonify recover`.
The recovery journal is in `.dart_tool/clonify/recovery.json`; backups live in
`.dart_tool/clonify/checkpoints/`. Do not delete `.dart_tool` while recovery is
pending. Recovery works even if the settings file is broken. A project lock
prevents simultaneous mutating Clonify commands.

Backups cover native platform folders, branding, generated clone/localization
files, profile configuration, versions, and Firebase metadata. Regenerable build
and tool caches are excluded. External tool caches outside the project, cloud
Firebase app registrations, and store uploads cannot be rolled back. An upload
failure reports completed uploads and warns when remote completion is uncertain.
Shorebird release/patch failures restore the preceding local configure too;
published remote releases or patches must be checked separately before retrying.

### Upgrade workflow

Legacy commands and profile JSON remain readable; successful configure migrates the profile keys. Dart 3.13 or newer is
supported. After upgrading, configure each profile once before building it;
Clonify records the successful configuration in `clonify/active_profile.json`.
`last_client.txt` is never read or written and can be deleted. Pass `--client-id`
(or legacy `--clientId`) explicitly, reuse the active receipt, or let Clonify
select the only available profile. Ambiguous selection gives an actionable error.
Builds still verify the receipt, generated fields, and native IDs.
Changing a profile's app settings requires another configure. Changing only its
credential path does not invalidate an existing build.

Use `clonify build` before uploading: successful builds receive local SHA-256
receipts tied to the profile in `.dart_tool/clonify/builds/`. Old, modified, or
unverified artifacts are rejected. Rebuild after deleting `.dart_tool`.
Android bundles use `flutter build appbundle`. Platform builds run sequentially;
IPA builds require macOS. For Android only:

```bash
clonify build --clientId staff --skipAll --no-buildIpa
clonify upload --clientId staff --skipAll --no-uploadIOS
```

Fastfiles must define `bundleId`, `app_version`, and (Android) `app_version_code`
variables and pass a literal `aab: "..."` or `ipa: "..."` to their upload action.
Clonify binds that argument to the verified artifact before running the lane.
Opaque dynamic artifact-selection lanes are rejected so they cannot silently
upload another customer's file. Keep store authentication configured in Fastlane.

`--skipPubUpdate` now leaves the pubspec version unchanged. A mismatched pubspec
version blocks build/upload until reconciled. `--skipAll` skips prompts;
`--autoUpdate` increments the version rather than updating dependencies.
`--isDebug` skips Firebase and Shorebird setup; it does not disable validation.

Exit codes: `0` success, `1` operational failure, `64` invalid command usage,
`130` cancellation. `--no-tui` uses plain output for scripts and CI.
On Windows, batch tools support spaces in paths, but reject shell characters
such as `&`, `%`, `!`, and quotes in tool paths or arguments. Move the tool or
credential to a path without those characters before retrying.

## Commands

### Global Options

Available for all commands:
- `--no-tui` - Disable TUI (Text User Interface) features and use basic text mode
- `--help` - Display help information for any command

### `clonify init`
Initialize Clonify environment with global settings.

**Aliases:** `i`, `initialize`

### `clonify create`
Create a new Flutter project clone configuration.

**Aliases:** `create-clone`

### `clonify configure [options]`
Configure the Flutter project for a specific client.

**Aliases:** `con`, `config`, `c`

**Options:**
- `--clientId <id>` - Client ID to configure (or use last)
- `--dry-run` - Validate and preview without changes
- `--skipAll` - Skip all user prompts
- `--autoUpdate` - Automatically increment version
- `--isDebug` - Skip Firebase and Shorebird setup
- `--skipFirebaseConfigure` - Restore matching saved Firebase files without online setup
- `--refreshFirebase` - Configure Firebase online and replace this clone's saved files
- `--skipShorebirdConfigure` - Skip Shorebird app_id sync
- `--skipPubUpdate` - Skip pubspec.yaml updates
- `--skipVersionUpdate` - Skip version updates

### `clonify build [options]`
Build the Flutter project clone.

**Aliases:** `b`

**Options:**
- `--clientId <id>` - Client ID to build (or use last)
- `--skipAll` - Skip all user prompts
- `--buildAab` - Build Android App Bundle (default: true)
- `--buildApk` - Build Android APK (default: false)
- `--buildIpa` - Build iOS IPA (default: true)
- `--skipBuildCheck` - Skip build confirmation (validation still runs)

### `clonify upload [options]`
Upload builds to app stores via Fastlane.

**Aliases:** `up`, `u`

**Options:**
- `--clientId <id>` - Client ID to upload
- `--skipAll` - Skip all prompts
- `--skipAndroidUploadCheck` - Upload Android without prompting (validation still runs)
- `--skipIOSUploadCheck` - Upload iOS without prompting (validation still runs)
- `--no-uploadAndroid` / `--no-uploadIOS` - Exclude a platform

### `clonify list`
List all configured clones.

**Aliases:** `l`, `list-clones`, `ls`

### `clonify which`
Display the current clone configuration.

**Aliases:** `w`, `current`, `who`

### `clonify clean [options]`
Clean up a partial or broken clone.

**Aliases:** `clear`

**Options:**
- `--clientId <id>` - Client ID to clean (required)

## Configuration Files

### Global Settings: `./clonify/clonify_settings.yaml`

```yaml
firebase:
  enabled: true
  settings_file: "path/to/firebase.json"

fastlane:
  enabled: false
  settings_file: ""

company_name: "Your Company"
default_color: "#FFFFFF"

clone_assets:
  - icon.png
  - splash.png
  - logo.png

launcher_icon_asset: "icon.png"
splash_screen_asset: "splash.png"

# Optional: Custom configuration fields
custom_fields:
  - name: "socketUrl"
    type: "string"
  - name: "maxRetries"
    type: "int"
  - name: "enableDebug"
    type: "bool"
```

### Per-Clone Config: `./clonify/clones/{clientId}/config.json`

All profile keys use `snake_case`. Generated Dart fields use `camelCase`.
The required fields are exactly the following (the former shared package name
is now two independent platform identifiers):

```json
{
  "client_id": "client_a",
  "android_package_name": "com.company.clienta",
  "ios_package_name": "com.company.clienta.ios",
  "app_name": "Client A App",
  "version": "1.0.0+1",
  "logo": "logo.png",
  "launcher_icon": "icon.png",
  "splash_screen": "splash.png"
}
```

Place those three PNG files under `clonify/clones/client_a/assets/`.
All other fields are optional: `base_url`, `primary_color`, `firebase_project_id`,
`firebase_service_account`, `shorebird_app_id`, `notification_icon`,
`background_notification_color`, `background_splash_color`, `android_keystore`,
`android_key_properties`, `background_geolocation_license_android`,
`background_geolocation_license_ios`, `colors`, and configured custom fields.
Supplied values are validated; an absent custom field is omitted from Dart.
Omitted optional strings never become the literal string `'null'`.
Firebase and Shorebird setup run only when the integration is enabled and its
profile ID is supplied. Each supplied geolocation license must match its own
platform's ID. Omitting a license removes the previous profile's native license.
Signing files, when supplied, still need to be valid for release signing.

Custom fields are declared in `clonify_settings.yaml`, for example
`name: is_client_account` with `type: bool`; JSON values keep their native types
(`true`, `5`, `1.5`, or strings). Custom and color names are converted to Dart
camelCase and checked for duplicate/reserved names before configuration.

Legacy camelCase JSON and `packageName` / `package_name` remain readable.
A legacy shared ID supplies both platforms unless a platform explicitly supplies
its own ID. Successful configure and version updates save canonical snake_case
JSON with both platform IDs. Duplicate snake/camel aliases are rejected.

### Generated Config: `lib/generated/clone_configs.dart`

```dart
abstract class CloneConfigs() {
  static const String clientId = 'client_a';
  static const String androidPackageName = 'com.company.clienta';
  static const String iosPackageName = 'com.company.clienta.ios';
  static const String appName = 'Client A App';
  static const String version = '1.0.0+1';
  static const String logo = 'assets/images/logo.png';
  static const String launcherIcon = 'assets/images/icon.png';
  static const String splashScreen = 'assets/images/splash.png';
}
```

Generated code uses [Dart 3.13 primary constructors](https://dart.dev/language/primary-constructors).
Set your Flutter app's `environment.sdk` lower bound to at least `3.13.0`.
Strings use single quotes with escaped apostrophes, interpolation, backslashes,
and control characters. Use `CloneConfigs.androidPackageName` and
`CloneConfigs.iosPackageName` in place of the former shared `packageName` field.

Use in your Flutter app:
```dart
import 'package:your_app/generated/clone_configs.dart';

final clientId = CloneConfigs.clientId;
final androidPackage = CloneConfigs.androidPackageName;
final iosBundleId = CloneConfigs.iosPackageName;
```


## Workflow Example

### Managing Multiple Clients

```bash
# Initial setup (one time)
clonify init

# Create client A
clonify create
# Enter: client_a, com.company.clienta, etc.

# Create client B
clonify create
# Enter: client_b, com.company.clientb, etc.

# Work on client A
clonify configure --clientId client_a
clonify build --clientId client_a

# Switch to client B
clonify configure --clientId client_b
clonify build --clientId client_b

# List all clients
clonify list
```

## Optional Features

### Firebase Integration

Firebase is **optional**. Enable `firebase.enabled`, set `settings_file` to your
`firebase.json`, and set each clone's `firebase_project_id`, `android_package_name`, and `ios_package_name`.

#### One-time setup without Gmail switching

Install Firebase CLI and FlutterFire CLI (`dart pub global activate
flutterfire_cli`, version 1.4.1 or newer) once on each developer's computer.
Create a Google service account and grant it the permissions needed to read app
configuration and register apps in each target Firebase project. The project
owner's Gmail can differ; project access is what matters. Project creation needs
additional permission, so normally create the Firebase project first.

Keep the private service-account JSON **outside the Flutter project and Git**.
For example, save it on the Desktop and put its normal path in each profile:

```json
"firebase_project_id": "amada-6c209",
"firebase_service_account": "~/Desktop/amada-firebase.json"
```

No shell export is needed. Different profiles can use different JSON files and
projects. On another computer, store an authorized credential there and update
the path once. Cached switches do not need this private file.

Advanced setups may still use `env:VARIABLE_NAME`. Without a profile reference,
Clonify checks `CLONIFY_FIREBASE_SERVICE_ACCOUNT`, then
`GOOGLE_APPLICATION_CREDENTIALS`; when neither is set, the saved Firebase CLI
login is used for online setup.
Service-account setup runs in a temporary Firebase account store, preserving
your saved Gmail logins and preventing them from overriding the selected key.

```bash
# Set up or refresh this clone's registered Android/iOS apps once:
clonify configure --clientId client_a --refreshFirebase --skipVersionUpdate

# Normal switches restore saved configuration without Firebase login:
clonify configure --clientId client_a --skipVersionUpdate
clonify configure --clientId client_b --skipVersionUpdate
```

#### Share saved Firebase files with your team

Each configured clone saves these public app settings under
`clonify/clones/{clientId}/firebase/`:

```text
lib/firebase_options.dart
android/app/google-services.json
ios/Runner/GoogleService-Info.plist
firebase.json                         # only Flutter metadata
```

Share this directory with the project. Your friend can switch an already saved
clone without the private credential, Firebase CLI, or FlutterFire CLI.
Clonify validates project IDs, bundle/package names, app IDs, sender IDs, and API
keys before copying. Deployment sections such as Hosting and Functions stay in
the configured Firebase settings file. A mismatched or incomplete saved
configuration fails; use `--refreshFirebase` after changing a clone's project or
package.
Configuration that already matches the active app can also be saved without
going online. Firebase configuration supports Android and iOS. Newly added
Firebase products may need a refresh to update native build integration.

`--skipFirebaseConfigure` allows saved/matching files only and never runs
FlutterFire. `--skipAll` skips prompts but still restores or configures Firebase.
Disable `firebase.enabled` entirely only for apps that do not use Firebase.

These files contain public Firebase app identifiers. A service-account JSON
contains private administration credentials and must never be placed in this
cache, clone assets, mobile app, or source control. A Firebase API key alone
cannot authorize app registration or configuration downloads.

### Shorebird Integration

Shorebird is **optional**. Enable with:

```yaml
shorebird:
  enabled: true
```

Clonify always syncs `./shorebird.yaml` from each clone's `shorebirdAppId` on `configure`.

Release / patch (replaces project wrapper scripts):

```bash
clonify shorebird --clientId your_client -- release android
clonify shorebird --clientId your_client -- patch ios
```

To skip Shorebird sync during configure only:
- Set `shorebird.enabled: false`
- Or use `--skipShorebirdConfigure`

### Android Play signing

Each clone can keep its own upload keystore (do **not** commit secrets):

```
clonify/clones/{clientId}/android/upload-keystore.jks
clonify/clones/{clientId}/android/key.properties
```

`key.properties` uses the Flutter format:

```
storePassword=YOUR_STORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=upload
storeFile=upload-keystore.jks
```

On `clonify configure`, Clonify copies those files to `android/` and wires
release signing in `android/app/build.gradle(.kts)` to `rootProject.file(...)`.
If the files are missing, configure skips signing (debug keys stay in use)
unless `androidKeystore` / `androidKeyProperties` is set in `config.json`.
Switching to a clone with no signing files removes leftover
`android/key.properties` so the previous Play key is not reused.
Keystore names must be a file name (`upload-keystore.jks`), not a path.

Add to the Flutter app `.gitignore`:

```
**/android/key.properties
*.jks
*.keystore
```

### Fastlane Integration

Fastlane is **optional**. To use Fastlane:

1. Enable during `clonify init`
2. Provide path to Fastlane settings
3. Use `clonify upload` to deploy to stores

## Development

### Run Tests

```bash
dart test
```

### Run Linter

```bash
dart analyze
```

### Format Code

```bash
dart format .
```

### Build Executable

```bash
dart compile exe bin/clonify.dart
```

## Requirements

- Dart SDK ^3.13.0
- Flutter SDK (for building apps)
- Firebase CLI (optional, if using Firebase features)
- Fastlane (optional, if using upload features)
- Xcode (for iOS builds on macOS)
- Android SDK (for Android builds)

## Contributing

Contributions are welcome! Please read the contributing guidelines before submitting PRs.

## Changelog

For all notable changes to this project, refer to the CHANGELOG.

## Support 

For any issues or suggestions, please open an issue. Your feedback is highly appreciated.

## Version

This is a pre-release version. The API may change in future releases. Feedback and bug reports are welcome!

## License

**GPL v3** (GNU General Public License v3.0) - see [LICENSE](LICENSE) file for details.

Copyright (c) 2024 Mohammad Salameh

**What this means:**
- ✅ Free to use for any purpose (including commercial projects)
- ✅ Free to modify and study the code
- ✅ Can sell applications built WITH this tool
- ❌ Cannot sell this tool itself as closed-source software
- ⚠️ If you distribute modified versions, you MUST share the source code under GPL v3

Full license: https://www.gnu.org/licenses/gpl-3.0.txt

## Author

**Mohammad Salameh**

- GitHub: [@DevMohammadSalameh](https://github.com/DevMohammadSalameh)
- Repository: https://github.com/DevMohammadSalameh/clonify
- Issues: https://github.com/DevMohammadSalameh/clonify/issues

## Acknowledgments

Built with ❤️ for the Flutter community, inspired by the need for efficient white-label app management.

### Special Thanks to Open Source Contributors

Clonify leverages these excellent community packages:

**Core TUI Libraries:**
- [mason_logger](https://pub.dev/packages/mason_logger) - Interactive CLI prompts and progress indicators
- [chalkdart](https://pub.dev/packages/chalkdart) - Terminal string styling and colors

**Asset Generation Tools (Called by Clonify):**
- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) - Automated launcher icon generation
- [flutter_native_splash](https://pub.dev/packages/flutter_native_splash) - Splash screen creation

**Internalized Tools:**
- [package_rename_plus](https://pub.dev/packages/package_rename_plus) - Package renaming functionality (now built directly into Clonify v0.4.3+)

**Architecture Inspiration:**
- Inspired by the architecture of the `rename` package for Flutter project management

A huge thank you to all the maintainers and contributors of these projects! 🙏
