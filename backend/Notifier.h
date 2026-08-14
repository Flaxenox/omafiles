#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Desktop notifications via notify-send.
// QML singleton (Omafiles.Backend.Notifier): consumed as Notifier.notify("...").
//
// Design note (BACKEND_DESIGN.md 5.1): the idiomatic form would be
// org.freedesktop.Notifications over QDBus (no fork, with notification IDs).
// It is left as notify-send in 5.C to avoid introducing behaviour changes; the
// migration to QDBus is later work.
//
// QML singleton (Omafiles.Backend.Notifier): stateless, consumed as
// Notifier.notify("text").
class Notifier : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit Notifier(QObject *parent = nullptr);

  // Shows a desktop notification with the fixed "Omafiles" title
  // and `text` as the body.
  Q_INVOKABLE void notify(const QString &text);
};
