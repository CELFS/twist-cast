import Cocoa
import FlutterMacOS

/// Input is armed locally for one captured display and one sharing session.
final class DesktopInput {
  private var display: CGDirectDisplayID?
  private var enabled = false
  private var pressed = false
  private var lastPoint = CGPoint.zero
  private let keys: [String: CGKeyCode] = [
    "Enter": 36, "Tab": 48, "Backspace": 51, "Escape": 53,
    "Left": 123, "Right": 124, "Down": 125, "Up": 126,
  ]

  private func mouse(_ type: CGEventType, at point: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
            mouseButton: .left)?.post(tap: .cghidEventTap)
  }

  private func releaseButton() {
    if pressed { mouse(.leftMouseUp, at: lastPoint); pressed = false }
  }

  func handle(_ call: FlutterMethodCall, result: FlutterResult) {
    switch call.method {
    case "captureAvailable":
      display = CGMainDisplayID()
      result(CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess())
    case "enable":
      enabled = display == CGMainDisplayID() &&
        (CGPreflightPostEventAccess() || CGRequestPostEventAccess())
      result(enabled)
    case "disable":
      releaseButton()
      enabled = false
      result(nil)
    case "pointer", "key":
      guard enabled, let id = display, id == CGMainDisplayID(), CGDisplayIsActive(id) != 0,
            CGPreflightPostEventAccess(), let args = call.arguments as? [String: Any] else {
        releaseButton()
        enabled = false
        result(FlutterError(code: "input-unavailable", message: nil, details: nil))
        return
      }
      if call.method == "pointer" { pointer(args, bounds: CGDisplayBounds(id)) }
      else { keyboard(args) }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }

  private func pointer(_ args: [String: Any], bounds: CGRect) {
    guard let action = args["action"] as? String else { return }
    if action == "cancel" { releaseButton(); return }
    guard let x = args["x"] as? Double, let y = args["y"] as? Double,
          (0...1).contains(x), (0...1).contains(y) else { return }
    let point = CGPoint(x: bounds.minX + x * (bounds.width - 1),
                        y: bounds.minY + y * (bounds.height - 1))
    switch action {
    case "down" where !pressed: mouse(.leftMouseDown, at: point); pressed = true
    case "move" where pressed: mouse(.leftMouseDragged, at: point)
    case "up" where pressed: mouse(.leftMouseUp, at: point); pressed = false
    case "secondary" where !pressed:
      for type in [CGEventType.rightMouseDown, .rightMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                mouseButton: .right)?.post(tap: .cghidEventTap)
      }
    case "scroll":
      guard let dy = args["dy"] as? Double else { return }
      let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                          wheel1: Int32(-dy * bounds.height), wheel2: 0, wheel3: 0)
      event?.location = point
      event?.post(tap: .cghidEventTap)
    default: return
    }
    lastPoint = point
  }

  private func keyboard(_ args: [String: Any]) {
    guard let key = args["key"] as? String else { return }
    if key == "text", let text = args["text"] as? String, text.utf16.count <= 256 {
      for scalar in text.unicodeScalars {
        let units = Array(String(scalar).utf16)
        for down in [true, false] {
          let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
          event?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
          event?.post(tap: .cghidEventTap)
        }
      }
    } else if let code = keys[key] {
      for down in [true, false] {
        CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.post(tap: .cghidEventTap)
      }
    }
  }
}
