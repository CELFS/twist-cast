#ifndef RUNNER_DESKTOP_INPUT_H_
#define RUNNER_DESKTOP_INPUT_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <cmath>
#include <map>
#include <string>
#include <vector>

class DesktopInput {
 public:
  explicit DesktopInput(flutter::BinaryMessenger* messenger)
      : channel_(messenger, "app.twist.cast/desktop-input",
                 &flutter::StandardMethodCodec::GetInstance()) {
    channel_.SetMethodCallHandler([this](const auto& call, auto result) {
      const auto& method = call.method_name();
      if (method == "captureAvailable") {
        result->Success(flutter::EncodableValue(true));
      } else if (method == "enable") {
        enabled_ = GetSystemMetrics(SM_CMONITORS) == 1;
        result->Success(flutter::EncodableValue(enabled_));
      } else if (method == "disable") {
        Release();
        enabled_ = false;
        result->Success();
      } else if (method == "pointer" || method == "key") {
        const auto* args = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
        if (!enabled_ || GetSystemMetrics(SM_CMONITORS) != 1 || !args ||
            !(method == "pointer" ? Pointer(*args) : Key(*args))) {
          Release();
          enabled_ = false;
          result->Error("input-unavailable", "Desktop input was not accepted");
          return;
        }
        result->Success();
      } else {
        result->NotImplemented();
      }
    });
  }
  ~DesktopInput() { Release(); }

 private:
  using Map = flutter::EncodableMap;
  template <typename T>
  static const T* Field(const Map& args, const char* name) {
    const auto it = args.find(flutter::EncodableValue(name));
    return it == args.end() ? nullptr : std::get_if<T>(&it->second);
  }

  void Release() {
    if (pressed_) {
      INPUT up{};
      up.type = INPUT_MOUSE;
      up.mi.dwFlags = MOUSEEVENTF_LEFTUP;
      SendInput(1, &up, sizeof(INPUT));
      pressed_ = false;
    }
  }

  bool Pointer(const Map& args) {
    const auto* action = Field<std::string>(args, "action");
    if (!action) return false;
    if (*action == "cancel") { Release(); return true; }
    const auto* x = Field<double>(args, "x");
    const auto* y = Field<double>(args, "y");
    if (!x || !y || !(*x >= 0 && *x <= 1 && *y >= 0 && *y <= 1)) return false;
    INPUT input{};
    input.type = INPUT_MOUSE;
    input.mi.dx = std::lround(*x * 65535);
    input.mi.dy = std::lround(*y * 65535);
    input.mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_MOVE;
    if (*action == "secondary" && !pressed_) {
      INPUT click[2] = {input, input};
      click[0].mi.dwFlags |= MOUSEEVENTF_RIGHTDOWN;
      click[1].mi.dwFlags |= MOUSEEVENTF_RIGHTUP;
      return SendInput(2, click, sizeof(INPUT)) == 2;
    }
    if (*action == "down" && !pressed_) input.mi.dwFlags |= MOUSEEVENTF_LEFTDOWN;
    else if (*action == "up" && pressed_) input.mi.dwFlags |= MOUSEEVENTF_LEFTUP;
    else if (*action == "scroll") {
      const auto* dy = Field<double>(args, "dy");
      if (!dy || !std::isfinite(*dy) || std::abs(*dy) > 0.35) return false;
      input.mi.dwFlags |= MOUSEEVENTF_WHEEL;
      input.mi.mouseData = static_cast<DWORD>(std::lround(-*dy * 10 * WHEEL_DELTA));
    } else if (*action != "move" || !pressed_) return true;
    if (SendInput(1, &input, sizeof(INPUT)) != 1) return false;
    if (*action == "down") pressed_ = true;
    if (*action == "up") pressed_ = false;
    return true;
  }

  bool Key(const Map& args) {
    const auto* key = Field<std::string>(args, "key");
    if (!key) return false;
    std::vector<INPUT> events;
    auto add = [&events](WORD code, DWORD flags) {
      INPUT input{};
      input.type = INPUT_KEYBOARD;
      if (flags & KEYEVENTF_UNICODE) input.ki.wScan = code;
      else input.ki.wVk = code;
      input.ki.dwFlags = flags;
      events.push_back(input);
      input.ki.dwFlags |= KEYEVENTF_KEYUP;
      events.push_back(input);
    };
    if (*key == "text") {
      const auto* text = Field<std::string>(args, "text");
      if (!text || text->empty() || text->size() > 1024) return false;
      wchar_t units[256];
      int count = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text->data(),
          static_cast<int>(text->size()), units, 256);
      if (!count) return false;
      for (int i = 0; i < count; ++i) add(units[i], KEYEVENTF_UNICODE);
    } else {
      static const std::map<std::string, WORD> keys = {
          {"Enter", VK_RETURN}, {"Backspace", VK_BACK}, {"Tab", VK_TAB}, {"Escape", VK_ESCAPE},
          {"Left", VK_LEFT}, {"Right", VK_RIGHT}, {"Up", VK_UP}, {"Down", VK_DOWN}};
      const auto it = keys.find(*key);
      if (it == keys.end()) return false;
      add(it->second, it->second >= VK_LEFT && it->second <= VK_DOWN ? KEYEVENTF_EXTENDEDKEY : 0);
    }
    const UINT count = static_cast<UINT>(events.size());
    return SendInput(count, events.data(), sizeof(INPUT)) == count;
  }

  flutter::MethodChannel<flutter::EncodableValue> channel_;
  bool enabled_ = false;
  bool pressed_ = false;
};
#endif
