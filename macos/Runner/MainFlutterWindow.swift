import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var updates: AppUpdates?
  private var windowChannel: FlutterMethodChannel?
  private var receiverAccessory: NSTitlebarAccessoryViewController?
  private let minimumContentSize = NSSize(width: 320, height: 360)
  private var inactiveWindowIndicators: [InactiveWindowIndicator] = []

  override func becomeKey() {
    super.becomeKey()
    inactiveWindowIndicators.forEach { $0.isHidden = true }
  }

  override func resignKey() {
    super.resignKey()
    inactiveWindowIndicators.forEach { $0.isHidden = false }
  }

  private func addInactiveWindowIndicators() {
    let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
    for type in buttons {
      guard let button = standardWindowButton(type) else { continue }
      let indicator = InactiveWindowIndicator(frame: button.bounds)
      indicator.autoresizingMask = [.width, .height]
      indicator.isHidden = isKeyWindow
      button.addSubview(indicator, positioned: .above, relativeTo: nil)
      inactiveWindowIndicators.append(indicator)
    }
  }

  @objc private func toggleReceiverControls() {
    windowChannel?.invokeMethod("toggleReceiverControls", arguments: nil)
  }

  private func setReceiverControls(enabled: Bool, label: String) {
    if enabled {
      if receiverAccessory == nil {
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 36, height: 24))
        button.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: label)
        button.imagePosition = .imageOnly
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.contentTintColor = NSColor(srgbRed: 0.26, green: 0.32, blue: 0.37, alpha: 1)
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
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    titlebarSeparatorStyle = .none
    contentMinSize = minimumContentSize
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
        if call.method == "startWindowDrag" {
          if let event = NSApp.currentEvent, event.type == .leftMouseDown {
            self?.performDrag(with: event)
          }
          result(nil)
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
          let horizontalInset = args["horizontalInset"] ?? 0
          guard horizontalInset.isFinite, horizontalInset >= 0 else {
            result(FlutterError(code: "arguments", message: nil, details: nil)); return
          }
          let border = self.frame.height - self.contentRect(forFrameRect: self.frame).height
          let maxWidth = max(1, bounds.width - horizontalInset)
          let maxHeight = max(1, bounds.height - border - chrome)
          let minWidth = max(1, max(self.minimumContentSize.width, minimum) - horizontalInset)
          let minHeight = max(1, self.minimumContentSize.height - chrome)
          let height = min(max(sqrt(area / ratio), minWidth / ratio, minHeight), maxHeight, maxWidth / ratio)
          let width = max(self.minimumContentSize.width, height * ratio + horizontalInset)
          let totalHeight = max(self.minimumContentSize.height, height + chrome)
          var frame = self.frameRect(forContentRect: NSRect(x: 0, y: 0, width: width, height: totalHeight))
          frame.origin.x = max(bounds.minX, min(self.frame.midX - frame.width / 2, bounds.maxX - frame.width))
          frame.origin.y = max(bounds.minY, min(self.frame.midY - frame.height / 2, bounds.maxY - frame.height))
          self.setFrame(frame, display: true)
        }
        result(nil)
      }

    super.awakeFromNib()
    addInactiveWindowIndicators()
  }
}

private final class InactiveWindowIndicator: NSView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    let diameter = min(11, bounds.width, bounds.height)
    let circle = NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2,
      width: diameter, height: diameter)
    NSColor(srgbRed: 0.67, green: 0.70, blue: 0.73, alpha: 1).setFill()
    NSBezierPath(ovalIn: circle).fill()
  }
}
