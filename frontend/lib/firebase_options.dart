import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    // switch (defaultTargetPlatform) {
    //   case TargetPlatform.android:
    //     return android;
    //   case TargetPlatform.iOS:
    //     return ios;
    //   case TargetPlatform.macOS:
    //     return macos;
    //   case TargetPlatform.windows:
    //     return windows;
    //   default:
    //     throw UnsupportedError(
    //       'DefaultFirebaseOptions are not supported for this platform.',
    //     );
    // }

    throw UnsupportedError(
      'DefaultFirebaseOptions are not supported for this platform.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA5ySkqiSTi19lHTSt8bhFzypfgqVtaSss',
    appId: '1:897703212804:web:37ad9da2d61544c2ce0251',
    messagingSenderId: '897703212804',
    projectId: 'urbox-1',
    authDomain: 'urbox-1.firebaseapp.com',
    storageBucket: 'urbox-1.firebasestorage.app',
    measurementId: 'G-52WPN2JTE8',
  );
}
