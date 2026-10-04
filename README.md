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

- Dart SDK (^3.8.1)
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
- The tool will check for their presence and warn you if they're missing
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
- Apply all file changes as one transaction: any error restores the project
  as if `clonify configure` never ran (iOS, Android, version, Shorebird,
  Firebase files, clone `config.json`)
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
- `--skipAll` - Skip all user prompts
- `--autoUpdate` - Automatically increment version
- `--isDebug` - Run in debug mode
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
- `--skipBuildCheck` - Skip pre-build checks

### `clonify upload [options]`
Upload builds to app stores via Fastlane.

**Aliases:** `up`, `u`

**Options:**
- `--clientId <id>` - Client ID to upload
- `--skipAll` - Skip all prompts
- `--skipAndroidUploadCheck` - Skip Android upload verification
- `--skipIOSUploadCheck` - Skip iOS upload verification

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

```json
{
  "clientId": "client_a",
  "packageName": "com.company.clienta",
  "appName": "Client A App",
  "baseUrl": "https://api.client-a.com",
  "primaryColor": "0xFF6200EE",
  "firebaseProjectId": "firebase-client-a",
  "firebaseServiceAccount": "env:CLONIFY_FIREBASE_SERVICE_ACCOUNT",
  "backgroundSplashColor": "0xFFFFFFFF",
  "androidKeystore": "upload-keystore.jks",
  "androidKeyProperties": "key.properties",
  "version": "1.0.0+1",
  "socketUrl": "wss://socket.client-a.com",
  "maxRetries": "5",
  "enableDebug": "false",
  "colors": [
    {
      "name": "primaryBlue",
      "color": "6200EE"
    }
  ],
  "linearGradients": [
    {
      "name": "primaryGradient",
      "colors": ["6200EE", "03DAC6"],
      "begin": "topLeft",
      "end": "bottomRight",
      "transform": "0"
    }
  ]
}
```

### Generated Config: `lib/generated/clone_configs.dart`

```dart
abstract class CloneConfigs {
  static const String clientId = "client_a";
  static const String baseUrl = "https://api.client-a.com";
  static const String version = "1.0.0+1";
  static const String primaryColor = "0xFF6200EE";
  static const String socketUrl = "wss://socket.client-a.com";
  static const int maxRetries = 5;
  static const bool enableDebug = false;
  static const primaryBlue = Color(0xFF6200EE);
  static const primaryGradient = LinearGradient(...);
}
```

Use in your Flutter app:
```dart
import 'package:your_app/generated/clone_configs.dart';

// Access configuration
final baseUrl = CloneConfigs.baseUrl;
final clientId = CloneConfigs.clientId;
final primaryColor = CloneConfigs.primaryBlue;

// Access custom fields
final socketUrl = CloneConfigs.socketUrl;
final maxRetries = CloneConfigs.maxRetries;
final isDebugEnabled = CloneConfigs.enableDebug;
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
`firebase.json`, and set each clone's `firebaseProjectId` and `packageName`.

#### One-time setup without Gmail switching

Install Firebase CLI and FlutterFire CLI (`dart pub global activate
flutterfire_cli`, version 1.4.1 or newer) once on each developer's computer.
Create a Google service account and grant it the permissions needed to read app
configuration and register apps in each target Firebase project. The project
owner's Gmail can differ; project access is what matters. Project creation needs
additional permission, so normally create the Firebase project first.

Keep the private service-account JSON **outside the Flutter project and Git**.
On your Mac or your friend's computer, point a local environment variable to it:

```bash
export CLONIFY_FIREBASE_SERVICE_ACCOUNT="$HOME/.config/clonify/amada-service-account.json"
```

Save that export in your shell startup file for future terminals. Clone JSON
contains only a reference, never the private key:

```json
"firebaseProjectId": "amada-6c209",
"firebaseServiceAccount": "env:CLONIFY_FIREBASE_SERVICE_ACCOUNT"
```

Different projects may reference different environment variables. Absolute paths
and `~/` paths are also accepted. Without a clone reference, Clonify checks
`CLONIFY_FIREBASE_SERVICE_ACCOUNT`, then `GOOGLE_APPLICATION_CREDENTIALS`; when
neither is set, the existing Firebase CLI login remains available for setup.
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

- Dart SDK ^3.8.1
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
