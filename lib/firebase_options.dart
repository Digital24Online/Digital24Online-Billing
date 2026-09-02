import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration for Digital 24 Online Billing.
///
/// This configuration is for the registered Android app:
/// com.digital24online
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    return android;
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAd_gZsvRaeOSfVWBpA8CSXEDySo93B-_g',
    appId: '1:330482211610:android:62c665a5e465411dd4eaa3',
    messagingSenderId: '330482211610',
    projectId: 'digital-24-online-billing',
    storageBucket: 'digital-24-online-billing.firebasestorage.app',
  );
}
