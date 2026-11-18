#ifndef RUNNER_WINDOW_SIZING_H_
#define RUNNER_WINDOW_SIZING_H_
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <algorithm>
#include <cmath>
#include <memory>

inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterWindowSizing(flutter::BinaryMessenger* messenger, HWND window) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.twist.cast/window", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([window](const auto& call, auto result) {
    if (call.method_name() != "fitVideo") { result->NotImplemented(); return; }
    const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
    auto number = [args](const char* key) {
      if (!args) return 0.0;
      const auto item = args->find(flutter::EncodableValue(key));
      if (item == args->end()) return 0.0;
      const auto* value = std::get_if<double>(&item->second);
      return value ? *value : 0.0;
    };
    const double ratio = number("aspectRatio"), chrome = number("chromeHeight");
    const double area = number("preferredArea"), minimum = number("minimumWidth");
    if (!std::isfinite(ratio) || ratio <= 0 || !std::isfinite(chrome) || chrome < 0 ||
        !std::isfinite(area) || area <= 0 || !std::isfinite(minimum) || minimum <= 0) {
      result->Error("arguments", "Invalid window dimensions"); return;
    }
    if (!IsZoomed(window) && !IsIconic(window)) {
      RECT frame{}, client{};
      MONITORINFO monitor{};
      monitor.cbSize = sizeof(monitor);
      if (!GetWindowRect(window, &frame) || !GetClientRect(window, &client) ||
          !GetMonitorInfo(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST), &monitor)) {
        result->Error("window", "Could not read window dimensions"); return;
      }
      const double scale = GetDpiForWindow(window) / 96.0;
      const int borderX = (frame.right - frame.left) - client.right;
      const int borderY = (frame.bottom - frame.top) - client.bottom;
      const RECT work = monitor.rcWork;
      const double maxWidth = work.right - work.left - borderX;
      const double maxHeight = std::max(1.0, work.bottom - work.top - borderY - chrome * scale);
      const double height = std::min({std::max(std::sqrt(area / ratio) * scale,
          minimum * scale / ratio), maxHeight, maxWidth / ratio});
      const int width = static_cast<int>(std::round(std::min(maxWidth,
          std::max(minimum * scale, height * ratio)))) + borderX;
      const int totalHeight = static_cast<int>(std::round(height + chrome * scale)) + borderY;
      const int x = std::max(static_cast<int>(work.left), std::min(
          static_cast<int>((frame.left + frame.right - width) / 2), static_cast<int>(work.right) - width));
      const int y = std::max(static_cast<int>(work.top), std::min(
          static_cast<int>((frame.top + frame.bottom - totalHeight) / 2), static_cast<int>(work.bottom) - totalHeight));
      if (!SetWindowPos(window, nullptr, x, y, width, totalHeight, SWP_NOZORDER | SWP_NOACTIVATE)) {
        result->Error("window", "Could not resize window"); return;
      }
    }
    result->Success();
  });
  return channel;
}
#endif  // RUNNER_WINDOW_SIZING_H_
