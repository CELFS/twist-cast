import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var updates: AppUpdates?
  private var windowChannel: FlutterMethodChannel?
  private var receiverAccessory: NSTitlebarAccessoryViewController?
  private var previousTitleVisibility: NSWindow.TitleVisibility?

  @objc private func toggleReceiverControls() {
    windowChannel?.invokeMethod("toggleReceiverControls", arguments: nil)
  }

  private func setReceiverControls(enabled: Bool, label: String) {
    if enabled {
      if receiverAccessory == nil {
        previousTitleVisibility = titleVisibility
        titleVisibility = .hidden
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 24))
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.target = self
        button.action = #selector(toggleReceiverControls)
        accessory.view = button
        receiverAccessory = accessory
        addTitlebarAccessoryViewController(accessory)
      }
      receiverAccessory?.view.toolTip = label
      receiverAccessory?.view.setAccessibilityLabel(label)
    } else if let accessory = receiverAccessory {
      if let index = titlebarAccessoryViewControllers.firstIndex(of: accessory) {
        removeTitlebarAccessoryViewController(at: index)
      }
      receiverAccessory = nil
      titleVisibility = previousTitleVisibility ?? .visible
      previousTitleVisibility = nil
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let diagnostics = DiagnosticExport()
    FlutterMethodChannel(name: "app.twist.cast/diagnostics", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { call, result in diagnostics.handle(call, result: result) }
    let updates = AppUpdates()
    self.updates = updates
    FlutterMethodChannel(name: "app.twist.cast/updates", binaryMessenger: flutterViewController.engine.binaryMessenger)
      .setMethodCallHandler { call, result in updates.handle(call, result: result) }
    let windowChannel = FlutterMethodChannel(name: "app.twist.cast/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    self.windowChannel = windowChannel
    windowChannel.setMethodCallHandler { [weak self] call, result in
        if call.method == "receiverControls" {
          guard let self = self, let args = call.arguments as? [String: Any],
            let enabled = args["enabled"] as? Bool else {
            result(FlutterError(code: "arguments", message: nil, details: nil)); return
          }
          self.setReceiverControls(enabled: enabled, label: args["label"] as? String ?? "")
          result(enabled)
          return
        }
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
