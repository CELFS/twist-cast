import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

final class DiagnosticExport {
  private var busy = false

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "export" else { result(FlutterMethodNotImplemented); return }
    guard !busy else { result(FlutterError(code: "busy", message: nil, details: nil)); return }
    guard let args = call.arguments as? [String: Any], let json = args["json"] as? String,
      let data = json.data(using: .utf8), data.count <= 4 * 1024 * 1024 else {
      result(FlutterError(code: "size", message: nil, details: nil)); return
    }
    busy = true
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "twistcast-receiver-\(Int(Date().timeIntervalSince1970)).json"
    panel.begin { [self] response in
      guard response == .OK, let url = panel.url else { busy = false; result(false); return }
      DispatchQueue.global(qos: .utility).async {
        let saved: Bool
        do { try data.write(to: url, options: .atomic); saved = true } catch { saved = false }
        DispatchQueue.main.async { [self] in
          busy = false
          if saved { result(true) } else { result(FlutterError(code: "export", message: nil, details: nil)) }
        }
      }
    }
  }
}
