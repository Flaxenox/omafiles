#pragma once

// GIO C headers conflict with Qt's "signals" macro (defined in <QObject>).
// This compatibility header safely encapsulates the undefine workaround
// so it doesn't accidentally propagate or leak if GIO is used elsewhere.
#undef signals
#include <gio/gio.h>
