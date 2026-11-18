import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var updates: AppUpdates?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let updates = AppUpdates()
    self.updates = updates
    FlutterMethodChannel(name: "app.twist.cast/updates", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { call, result in updates.handle(call, result: result) }
    FlutterMethodChannel(name: "app.twist.cast/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "fitVideo" else { result(FlutterMethodNotImplemented); return }
        guard let self = self, let args = call.arguments as? [String: Double],
          let ratio = args["aspectRatio"], let chrome = args["chromeHeight"],
          let area = args["preferredArea"], let minimum = args["minimumWidth"],
          ratio.isFinite, ratio > 0, chrome.isFinite, chrome >= 0,
          area.isFinite, area > 0, minimum.isFinite, minimum > 0 else {
          result(FlutterError(code: "arguments", message: nil, details: nil)); return
        }
        if !self.styleMask.contains(.fullScreen), !self.isZoomed, let screen = self.screen {
          let bounds = screen.visibleFrame
          let border = self.frame.height - self.contentRect(forFrameRect: self.frame).height
          let height = min(max(sqrt(area / ratio), minimum / ratio),
            max(1, bounds.height - border - chrome), bounds.width / ratio)
          let width = min(bounds.width, max(minimum, height * ratio))
          var frame = self.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: height + chrome))
          frame.origin.x = max(bounds.minX, min(self.frame.midX - frame.width / 2, bounds.maxX - frame.width))
          frame.origin.y = max(bounds.minY, min(self.frame.midY - frame.height / 2, bounds.maxY - frame.height))
          self.setFrame(frame, display: true)
        }
        result(nil)
      }

    super.awakeFromNib()
  }
}
