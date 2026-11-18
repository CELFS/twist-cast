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

  private var captureEvents: FlutterEventSink?
  private var captureObserver: NSObjectProtocol?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TwistCastCapture") {
      FlutterEventChannel(name: "app.twist.cast/capture-events", binaryMessenger: registrar.messenger())
        .setStreamHandler(self)
    }
    captureObserver = NotificationCenter.default.addObserver(
      forName: NSNotification.Name("TwistCastCaptureStopped"), object: nil, queue: .main
    ) { [weak self] _ in self?.captureEvents?("stopped") }
  }
}

extension AppDelegate: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    captureEvents = events
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    captureEvents = nil
    return nil
  }
}
