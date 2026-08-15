#include <gio/gio.h>
#include <stdio.h>

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
  GFile *file = g_file_new_for_uri("smb://127.0.0.1/share");
  GMountOperation *op = g_mount_operation_new();
  // g_mount_operation_set_anonymous(op, TRUE); // try without credentials
  GMainLoop *loop = g_main_loop_new(NULL, FALSE);
  g_file_mount_enclosing_volume(file, G_MOUNT_MOUNT_NONE, op, NULL, mount_done_cb, loop);
  g_main_loop_run(loop);
  g_object_unref(op);
  g_object_unref(file);
  return 0;
}
