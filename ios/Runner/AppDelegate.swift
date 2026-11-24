import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private let fileDialogs = FileDialogs()
  private var captureEvents: FlutterEventSink?
  private var captureObserver: NSObjectProtocol?

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "TwistCastCapture") {
      FlutterMethodChannel(name: "app.twist.cast/files", binaryMessenger: registrar.messenger())
        .setMethodCallHandler(fileDialogs.handle)
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

private final class FileDialogs: NSObject, UIDocumentPickerDelegate {
  private var pending: FlutterResult?
  private var exportFolder: URL?
  private var limit = 0

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard pending == nil else { result(FlutterError(code: "busy", message: nil, details: nil)); return }
    let args = call.arguments as? [String: Any]
    guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
      .first(where: { $0.activationState == .foregroundActive }),
      var presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
      result(FlutterError(code: "window", message: nil, details: nil)); return
    }
    while let top = presenter.presentedViewController { presenter = top }
    pending = result
    if call.method == "pick", let bound = args?["limit"] as? Int {
      limit = bound
      present(UIDocumentPickerViewController(forOpeningContentTypes: [.item]), on: presenter)
    } else if call.method == "save", let name = args?["name"] as? String,
              let bytes = args?["bytes"] as? FlutterStandardTypedData {
      let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      exportFolder = folder
      let url = folder.appendingPathComponent(name)
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try bytes.data.write(to: url)
          DispatchQueue.main.async {
            self.present(UIDocumentPickerViewController(forExporting: [url], asCopy: true), on: presenter)
          }
        } catch {
          DispatchQueue.main.async { self.finish(FlutterError(code: "save", message: nil, details: nil)) }
        }
      }
    } else { finish(FlutterMethodNotImplemented) }
  }

  private func present(_ picker: UIDocumentPickerViewController, on presenter: UIViewController) {
    guard presenter.viewIfLoaded?.window != nil else {
      finish(FlutterError(code: "window", message: nil, details: nil)); return
    }
    picker.delegate = self
    picker.modalPresentationStyle = .fullScreen
    presenter.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(nil) }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { finish(nil); return }
    if exportFolder != nil { finish(true); return }
    let limit = self.limit
    DispatchQueue.global(qos: .userInitiated).async {
      let accessed = url.startAccessingSecurityScopedResource()
      defer { if accessed { url.stopAccessingSecurityScopedResource() } }
      var error: NSError?
      var value: Any = FlutterError(code: "read", message: nil, details: nil)
      NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &error) { source in
        do {
          let handle = try FileHandle(forReadingFrom: source)
          defer { try? handle.close() }
          var bytes = Data()
          while let chunk = try handle.read(upToCount: 65536), !chunk.isEmpty {
            guard chunk.count <= limit - bytes.count else {
              value = FlutterError(code: "size", message: nil, details: nil); return
            }
            bytes.append(chunk)
          }
          value = ["name": url.lastPathComponent, "bytes": FlutterStandardTypedData(bytes: bytes)]
        } catch { }
      }
      DispatchQueue.main.async { self.finish(value) }
    }
  }

  private func finish(_ value: Any?) {
    if let folder = exportFolder { try? FileManager.default.removeItem(at: folder) }
    exportFolder = nil
    let result = pending
    pending = nil
    result?(value)
  }
}
