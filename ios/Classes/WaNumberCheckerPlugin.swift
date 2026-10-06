import Flutter
import UIKit

/// iOS stub: contact-sync WA detection is Android-only.
/// Every call answers `unsupported` so consumers get a clean status
/// instead of a crash. Channels mirror Android for forward-compat.
public class WaNumberCheckerPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let methods = FlutterMethodChannel(
      name: "wa_number_checker/methods", binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(
      name: "wa_number_checker/events", binaryMessenger: registrar.messenger())
    let instance = WaNumberCheckerPlugin()
    registrar.addMethodCallDelegate(instance, channel: methods)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "normalize":
      let raw = (call.arguments as? [String: Any])?["phone"] as? String ?? ""
      result(WaNumberCheckerPlugin.normalize(raw))
    case "getDeviceInfo":
      result([
        "waInstalled": false, "w4bInstalled": false,
        "waActive": false, "w4bActive": false,
        "online": false, "powerSave": false,
        "tempAccountType": "", "tempAccountReady": false,
        "unsupported": true,
      ])
    case "checkExisting", "insertTemp", "deleteContact",
      "ensureTempAccount", "startObserver", "stopObserver",
      "openWhatsApp", "showReturnNotice", "showProgressNotice", "cancelReturnNotice":
      result(
        FlutterError(
          code: "UNSUPPORTED",
          message: "wa_number_checker is Android-only (iOS unsupported)",
          details: nil))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func normalize(_ raw: String) -> String {
    var d = raw.filter { $0.isNumber }
    if d.hasPrefix("08") { d = "62" + d.dropFirst(2) }
    return d
  }
}

extension WaNumberCheckerPlugin: FlutterStreamHandler {
  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? { return nil }
  public func onCancel(withArguments arguments: Any?) -> FlutterError? { return nil }
}
