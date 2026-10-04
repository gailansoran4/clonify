import 'dart:convert';

Map<String, String> firebaseManagerFixture({
  String projectId = 'project-a',
  String packageName = 'com.test.clienta',
  String androidId = '1:123456789:android:aaa1',
  String iosId = '1:123456789:ios:bbb1',
}) {
  return {
    'lib/firebase_options.dart':
        '''
class DefaultFirebaseOptions {
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'android-public-api-key',
    appId: '$androidId',
    messagingSenderId: '123456789',
    projectId: '$projectId',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'ios-public-api-key',
    appId: '$iosId',
    messagingSenderId: '123456789',
    projectId: '$projectId',
    iosBundleId: '$packageName',
  );
}
''',
    'android/app/google-services.json': jsonEncode({
      'project_info': {'project_number': '123456789', 'project_id': projectId},
      'client': [
        {
          'client_info': {
            'mobilesdk_app_id': androidId,
            'android_client_info': {'package_name': packageName},
          },
          'api_key': [
            {'current_key': 'android-public-api-key'},
          ],
        },
      ],
    }),
    'ios/Runner/GoogleService-Info.plist':
        '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
  <key>PROJECT_ID</key><string>$projectId</string>
  <key>BUNDLE_ID</key><string>$packageName</string>
  <key>GCM_SENDER_ID</key><string>123456789</string>
  <key>GOOGLE_APP_ID</key><string>$iosId</string>
  <key>API_KEY</key><string>ios-public-api-key</string>
  <key>IS_ANALYTICS_ENABLED</key><true/>
</dict></plist>
''',
    'firebase.json': jsonEncode({
      'flutter': {
        'platforms': {
          'android': {
            'default': {
              'projectId': projectId,
              'appId': androidId,
              'fileOutput': 'android/app/google-services.json',
            },
          },
          'ios': {
            'default': {
              'projectId': projectId,
              'appId': iosId,
              'fileOutput': 'ios/Runner/GoogleService-Info.plist',
            },
          },
          'dart': {
            'lib/firebase_options.dart': {
              'projectId': projectId,
              'configurations': {'android': androidId, 'ios': iosId},
            },
          },
        },
      },
    }),
  };
}
