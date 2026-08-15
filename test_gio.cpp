#include <gio/gio.h>
#include <iostream>
int main() {
  g_type_init(); // deprecated but just to test
  GFile *file = g_file_new_for_uri("smb://10.0.0.1/share");
  std::cout << g_file_get_uri(file) << std::endl;
  g_object_unref(file);
  return 0;
}
