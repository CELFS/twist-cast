import Cocoa
import FlutterMacOS
import Sparkle

final class AppUpdates: NSObject, SPUUpdaterDelegate {
  private var controller: SPUStandardUpdaterController!
  private var started = false
  private var failed = false

  override init() {
    super.init()
    controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      result([
        "platform": "macos-universal",
        "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        "buildNumber": Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0,
        "phase": controller.updater.sessionInProgress ? "updating" : failed ? "failed" : "idle",
        "received": 0, "total": 0
      ])
    case "download":
      do {
        if !started {
          try controller.updater.start()
          started = true
        }
        guard controller.updater.canCheckForUpdates else {
          result(FlutterError(code: "busy", message: nil, details: nil))
          return
        }
        failed = false
        // Sparkle reads the published feed and verifies the package signature before installation.
        // Its standard window owns download progress, cancellation, and install/relaunch.
        controller.checkForUpdates(nil)
        result(nil)
      } catch {
        result(FlutterError(code: "update", message: error.localizedDescription, details: nil))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    failed = true
  }
}
