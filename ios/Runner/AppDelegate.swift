import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Hands incoming notifications to flutter_local_notifications and
    // firebase_messaging. Without it, a notification that arrives while the app
    // is in the foreground is delivered to nothing and simply does not appear —
    // and, more subtly, tapping one does not route back into Dart, so the
    // deep link in `NotificationService.pendingDeepLink` never fires.
    //
    // FirebaseApp.configure() is deliberately not called here: `Firebase.initializeApp()`
    // on the Dart side does it, and doing both is what produces the
    // "Default app has already been configured" crash. It also means this file
    // needs no Firebase import, so the project still builds with no
    // GoogleService-Info.plist present.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
