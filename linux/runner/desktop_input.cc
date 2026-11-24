#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>
#include <cmath>
#include <cstring>

#ifdef TWISTCAST_XTEST
#include <gdk/gdkx.h>
#include <X11/XKBlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <utility>
#include <vector>
#endif

namespace {
bool IsX11() {
  auto* display = gdk_display_get_default();
  return display && !strcmp(G_OBJECT_TYPE_NAME(display), "GdkX11Display") &&
      g_strcmp0(g_getenv("XDG_SESSION_TYPE"), "wayland") != 0;
}

struct Input {
  bool enabled = false;
  bool pressed = false;
#ifdef TWISTCAST_XTEST
  Display* display = nullptr;
  bool Enable() {
    if (!IsX11() || gdk_display_get_n_monitors(gdk_display_get_default()) != 1) return false;
    display = gdk_x11_display_get_xdisplay(gdk_display_get_default());
    int event, error, major, minor;
    return ScreenCount(display) == 1 && XTestQueryExtension(display, &event, &error, &major, &minor);
  }
  void Release() {
    if (pressed) { XTestFakeButtonEvent(display, 1, False, 0); XFlush(display); }
    pressed = false;
  }
  static const char* String(FlValue* args, const char* name) {
    auto* value = fl_value_lookup_string(args, name);
    return value && fl_value_get_type(value) == FL_VALUE_TYPE_STRING ? fl_value_get_string(value) : "";
  }

  bool Pointer(FlValue* args) {
    const char* action = String(args, "action");
    if (!strcmp(action, "cancel")) { Release(); return true; }
    auto number = [args](const char* name) {
      auto* value = fl_value_lookup_string(args, name);
      return value && fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(value) : NAN;
    };
    const double x = number("x"), y = number("y");
    if (!(x >= 0 && x <= 1 && y >= 0 && y <= 1)) return false;
    const int screen = DefaultScreen(display);
    XTestFakeMotionEvent(display, screen, std::lround(x * (DisplayWidth(display, screen) - 1)),
                         std::lround(y * (DisplayHeight(display, screen) - 1)), 0);
    if (!strcmp(action, "down") && !pressed) {
      XTestFakeButtonEvent(display, 1, True, 0);
      pressed = true;
    } else if (!strcmp(action, "up")) {
      Release();
    } else if (!strcmp(action, "secondary") && !pressed) {
      XTestFakeButtonEvent(display, 3, True, 0);
      XTestFakeButtonEvent(display, 3, False, 0);
    } else if (!strcmp(action, "scroll")) {
      const double dy = number("dy");
      if (!std::isfinite(dy)) return false;
      const int button = dy > 0 ? 5 : 4;
      XTestFakeButtonEvent(display, button, True, 0);
      XTestFakeButtonEvent(display, button, False, 0);
    }
    XFlush(display);
    return true;
  }

  bool Key(FlValue* args) {
    const char* key = String(args, "key");
    std::vector<KeySym> symbols;
    if (!strcmp(key, "text")) {
      const char* text = String(args, "text");
      if (!*text || strlen(text) > 1024) return false;
      for (; *text; text = g_utf8_next_char(text)) {
        symbols.push_back(gdk_unicode_to_keyval(g_utf8_get_char(text)));
      }
    } else {
      const char* name = !strcmp(key, "Enter") ? "Return" : !strcmp(key, "Backspace") ? "BackSpace" : key;
      symbols.push_back(XStringToKeysym(name));
    }
    XkbStateRec state{};
    if (XkbGetState(display, XkbUseCoreKbd, &state) != Success) return false;
    // Resolve the complete input against the active layout before pressing any key.
    std::vector<std::pair<KeyCode, bool>> sequence;
    for (auto symbol : symbols) {
      if (symbol == NoSymbol) return false;
      KeyCode code = XKeysymToKeycode(display, symbol);
      if (!code) return false;
      bool shifted = XkbKeycodeToKeysym(display, code, state.group, 0) != symbol;
      if (shifted && XkbKeycodeToKeysym(display, code, state.group, 1) != symbol) return false;
      sequence.emplace_back(code, shifted);
    }
    const KeyCode shift = XKeysymToKeycode(display, XK_Shift_L);
    for (const auto& item : sequence) {
      if (item.second) XTestFakeKeyEvent(display, shift, True, 0);
      XTestFakeKeyEvent(display, item.first, True, 0);
      XTestFakeKeyEvent(display, item.first, False, 0);
      if (item.second) XTestFakeKeyEvent(display, shift, False, 0);
    }
    XFlush(display);
    return true;
  }
#else
  bool Enable() { return false; }
  void Release() {}
  bool Pointer(FlValue*) { return false; }
  bool Key(FlValue*) { return false; }
#endif
};

void Handle(FlMethodChannel*, FlMethodCall* call, gpointer data) {
  auto* input = static_cast<Input*>(data);
  const char* method = fl_method_call_get_name(call);
  if (!strcmp(method, "enable") || !strcmp(method, "captureAvailable")) {
    const bool allowed = !strcmp(method, "enable") ? (input->enabled = input->Enable()) : IsX11();
    g_autoptr(FlValue) value = fl_value_new_bool(allowed);
    fl_method_call_respond_success(call, value, nullptr);
    return;
  }
  if (!strcmp(method, "disable")) {
    input->enabled = false;
    input->Release();
  } else if (!strcmp(method, "pointer") || !strcmp(method, "key")) {
    auto* args = fl_method_call_get_args(call);
    if (!input->enabled || gdk_display_get_n_monitors(gdk_display_get_default()) != 1 ||
        !args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP ||
        !(strcmp(method, "key") ? input->Pointer(args) : input->Key(args))) {
      input->Release();
      input->enabled = false;
      fl_method_call_respond_error(call, "input-unavailable", "Desktop input unavailable", nullptr, nullptr);
      return;
    }
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}
}  // namespace

void RegisterDesktopInput(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "app.twist.cast/desktop-input",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, Handle, new Input(), [](gpointer data) {
    auto* input = static_cast<Input*>(data);
    input->Release();
    delete input;
  });
}
