#ifndef RUNNER_FILE_DIALOGS_H_
#define RUNNER_FILE_DIALOGS_H_
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <windows.h>
#include <commdlg.h>
#include <memory>
#include <vector>
#include "utils.h"

inline std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterFileDialogs(flutter::BinaryMessenger* messenger, HWND owner) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "app.twist.cast/files", &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler([owner](const auto& call, auto result) {
    const bool save = call.method_name() == "save";
    if (!save && call.method_name() != "pick") { result->NotImplemented(); return; }
    std::vector<wchar_t> path(32768);
    if (save) {
      const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
      if (!args) { result->Error("arguments"); return; }
      const auto it = args->find(flutter::EncodableValue("name"));
      const auto* name = it == args->end() ? nullptr : std::get_if<std::string>(&it->second);
      if (!name || !MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, name->c_str(), -1,
              path.data(), static_cast<int>(path.size()))) { result->Error("arguments"); return; }
    }
    OPENFILENAMEW picker{};
    picker.lStructSize = sizeof(picker);
    picker.hwndOwner = owner;
    picker.lpstrFile = path.data();
    picker.nMaxFile = static_cast<DWORD>(path.size());
    picker.Flags = OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST |
        (save ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
    if (save ? GetSaveFileNameW(&picker) : GetOpenFileNameW(&picker)) {
      result->Success(flutter::EncodableValue(Utf8FromUtf16(path.data())));
    } else if (CommDlgExtendedError()) { result->Error("dialog"); }
    else { result->Success(); }
  });
  return channel;
}
#endif  // RUNNER_FILE_DIALOGS_H_
