#ifndef RUNNER_WINDOW_SIZING_H_
#define RUNNER_WINDOW_SIZING_H_
#include <flutter_linux/flutter_linux.h>
#include <algorithm>
#include <cmath>

inline void RegisterWindowSizing(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "app.twist.cast/window", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer data) {
        if (g_strcmp0(fl_method_call_get_name(call), "fitVideo") != 0) {
          fl_method_call_respond_not_implemented(call, nullptr); return;
        }
        FlValue* args = fl_method_call_get_args(call);
        auto number = [args](const char* key) {
          if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return 0.0;
          FlValue* value = fl_value_lookup_string(args, key);
          return value && fl_value_get_type(value) == FL_VALUE_TYPE_FLOAT ? fl_value_get_float(value) : 0.0;
        };
        const double ratio = number("aspectRatio"), chrome = number("chromeHeight");
        const double area = number("preferredArea"), minimum = number("minimumWidth");
        if (!std::isfinite(ratio) || ratio <= 0 || !std::isfinite(chrome) || chrome < 0 ||
            !std::isfinite(area) || area <= 0 || !std::isfinite(minimum) || minimum <= 0) {
          fl_method_call_respond_error(call, "arguments", "Invalid window dimensions", nullptr, nullptr); return;
        }
        GtkWindow* window = GTK_WINDOW(data);
        GdkWindow* native = gtk_widget_get_window(GTK_WIDGET(window));
        if (!native) {
          fl_method_call_respond_error(call, "window", "Window unavailable", nullptr, nullptr); return;
        }
        if (!(gdk_window_get_state(native) & (GDK_WINDOW_STATE_FULLSCREEN | GDK_WINDOW_STATE_MAXIMIZED))) {
          GdkMonitor* monitor = gdk_display_get_monitor_at_window(gdk_window_get_display(native), native);
          GdkRectangle bounds{}, frame{};
          gdk_monitor_get_workarea(monitor, &bounds);
          gdk_window_get_frame_extents(native, &frame);
          int oldWidth, oldHeight;
          gtk_window_get_size(window, &oldWidth, &oldHeight);
          const int borderX = std::max(0, frame.width - oldWidth);
          const int borderY = std::max(0, frame.height - oldHeight);
          const double maxWidth = bounds.width - borderX;
          const double height = std::min({std::max(std::sqrt(area / ratio), minimum / ratio),
              std::max(1.0, bounds.height - borderY - chrome), maxWidth / ratio});
          const int width = static_cast<int>(std::round(std::min(maxWidth, std::max(minimum, height * ratio))));
          const int totalHeight = static_cast<int>(std::round(height + chrome));
          gtk_window_resize(window, width, totalHeight);
          gtk_window_move(window,
              std::max(bounds.x, std::min(frame.x + (frame.width - width - borderX) / 2,
                  bounds.x + bounds.width - width - borderX)),
              std::max(bounds.y, std::min(frame.y + (frame.height - totalHeight - borderY) / 2,
                  bounds.y + bounds.height - totalHeight - borderY)));
        }
        fl_method_call_respond_success(call, nullptr, nullptr);
      }, g_object_ref(window), g_object_unref);
}
#endif  // RUNNER_WINDOW_SIZING_H_
