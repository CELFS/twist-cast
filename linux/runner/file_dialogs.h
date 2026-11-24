#ifndef RUNNER_FILE_DIALOGS_H_
#define RUNNER_FILE_DIALOGS_H_
#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

inline void RegisterFileDialogs(FlView* view, GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "app.twist.cast/files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel,
      [](FlMethodChannel*, FlMethodCall* call, gpointer parent) {
        const char* method = fl_method_call_get_name(call);
        const bool save = g_strcmp0(method, "save") == 0;
        if (!save && g_strcmp0(method, "pick") != 0) {
          fl_method_call_respond_not_implemented(call, nullptr); return;
        }
        GtkFileChooserNative* picker = gtk_file_chooser_native_new(
            nullptr, GTK_WINDOW(parent), save ? GTK_FILE_CHOOSER_ACTION_SAVE : GTK_FILE_CHOOSER_ACTION_OPEN,
            nullptr, nullptr);
        GtkFileChooser* chooser = GTK_FILE_CHOOSER(picker);
        gtk_file_chooser_set_local_only(chooser, TRUE);
        if (save) {
          FlValue* name = fl_value_lookup_string(fl_method_call_get_args(call), "name");
          if (name && fl_value_get_type(name) == FL_VALUE_TYPE_STRING)
            gtk_file_chooser_set_current_name(chooser, fl_value_get_string(name));
          gtk_file_chooser_set_do_overwrite_confirmation(chooser, TRUE);
        }
        g_object_ref(call);
        g_signal_connect(picker, "response", G_CALLBACK(+[](GtkNativeDialog* dialog, gint response, gpointer data) {
          FlMethodCall* request = FL_METHOD_CALL(data);
          g_autofree gchar* path = response == GTK_RESPONSE_ACCEPT
              ? gtk_file_chooser_get_filename(GTK_FILE_CHOOSER(dialog)) : nullptr;
          g_autoptr(FlValue) value = path ? fl_value_new_string(path) : fl_value_new_null();
          fl_method_call_respond_success(request, value, nullptr);
          g_object_unref(request);
          g_object_unref(dialog);
        }), call);
        gtk_native_dialog_show(GTK_NATIVE_DIALOG(picker));
      }, window, nullptr);
}
#endif  // RUNNER_FILE_DIALOGS_H_
