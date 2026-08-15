#include <gio/gio.h>
#include <stdio.h>

static void ask_password_cb(GMountOperation *op, const gchar *message, const gchar *default_user, const gchar *default_domain, GAskPasswordFlags flags, gpointer user_data) {
  printf("Auth requested! message: %s\n", message);
  g_mount_operation_set_username(op, "myuser");
  g_mount_operation_set_password(op, "mypass");
  g_mount_operation_reply(op, G_MOUNT_OPERATION_HANDLED);
}

static void mount_done_cb(GObject *source, GAsyncResult *res, gpointer user_data) {
  GError *error = NULL;
  gboolean success = g_file_mount_enclosing_volume_finish(G_FILE(source), res, &error);
  if (success) {
    printf("Mounted successfully!\n");
  } else {
    printf("Mount failed: %s\n", error->message);
    g_error_free(error);
  }
  g_main_loop_quit((GMainLoop *)user_data);
}

int main() {
  GFile *file = g_file_new_for_uri("sftp://localhost");
  GMountOperation *op = g_mount_operation_new();
  g_signal_connect(op, "ask-password", G_CALLBACK(ask_password_cb), NULL);
  GMainLoop *loop = g_main_loop_new(NULL, FALSE);
  g_file_mount_enclosing_volume(file, G_MOUNT_MOUNT_NONE, op, NULL, mount_done_cb, loop);
  g_main_loop_run(loop);
  g_object_unref(op);
  g_object_unref(file);
  return 0;
}
