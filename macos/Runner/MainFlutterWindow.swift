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

    super.awakeFromNib()
  }
}
