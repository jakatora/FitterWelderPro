import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // flutter_local_notifications (przypomnienia o uprawnieniach spawacza):
    // delegat centrum powiadomień, żeby przypomnienie pokazało się także przy
    // otwartej aplikacji (README wtyczki, „iOS setup"). O zgodę na
    // powiadomienia aplikacja pyta dopiero przy włączeniu przypomnień.
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
