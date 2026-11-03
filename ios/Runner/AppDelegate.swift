import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerKV(engineBridge)
  }

  // 自建轻量键值存储（UserDefaults），与 Android 端 chunyin/kv 语义一致
  private func registerKV(_ engineBridge: FlutterImplicitEngineBridge) {
    let reg = engineBridge.pluginRegistry.registrar(forPlugin: "ChunyinKV")
    let ch = FlutterMethodChannel(name: "chunyin/kv",
                                  binaryMessenger: reg.messenger())
    let d = UserDefaults.standard
    ch.setMethodCallHandler { call, result in
      switch call.method {
      case "getAll":
        var out: [String: Any] = [:]
        for (k, v) in d.dictionaryRepresentation() where k.hasPrefix("cy_")  {
          if v is String || v is Bool || v is NSNumber {
            out[k] = v
          }
        }
        result(out)
      case "put":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String else {
          result(FlutterError(code: "bad_args", message: "key is null", details: nil))
          return
        }
        let v = args["value"]
        if let s = v as? String {
          d.set(s, forKey: key)
        } else if let b = v as? Bool {
          d.set(b, forKey: key)
        } else if let n = v as? NSNumber {
          d.set(n.doubleValue, forKey: key)
        } else {
          d.removeObject(forKey: key)
        }
        result(true)
      case "remove":
        if let args = call.arguments as? [String: Any],
           let key = args["key"] as? String {
          d.removeObject(forKey: key)
          result(true)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
