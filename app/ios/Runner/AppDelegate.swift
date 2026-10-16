import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var filesChannel: FlutterMethodChannel?
  private var liveActivityChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RoadToFiles") {
      let channel = FlutterMethodChannel(name: "org.roadto/files", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(AppDelegate.handleFiles)
      filesChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "RoadToLiveActivity") {
      let channel = FlutterMethodChannel(name: "org.roadto/live_activity", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler(GuidanceActivity.handle)
      liveActivityChannel = channel
    }
  }

  /// "excludeFromBackup" {path}: keeps a directory out of iCloud and computer
  /// backups. Used for the offline regions, which weigh hundreds of MB and
  /// can be reinstalled (Apple's data storage guidelines).
  private static func handleFiles(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "excludeFromBackup",
      let path = (call.arguments as? [String: Any])?["path"] as? String
    else {
      result(FlutterMethodNotImplemented)
      return
    }
    var url = URL(fileURLWithPath: path, isDirectory: true)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      result(nil)
    } catch {
      result(FlutterError(code: "io", message: error.localizedDescription, details: path))
    }
  }
}
