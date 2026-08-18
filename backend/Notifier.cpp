#include "Notifier.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDateTime>
#include <QVariantMap>

Notifier::Notifier(QObject *parent) : QObject(parent) {}

void Notifier::notify(const QString &text) {
  // Real desktop toast skipped under --selfcheck (same guard as
  // core/AppBindings.qml's self-registration) -- a real notification per
  // call is a REAL, disruptive side effect on the developer's actual
  // desktop (confirmed directly, 2026-08-18: repeated selfcheck runs during
  // this session's own development spammed the real notification tray).
  // history() still records normally either way, so the history/
  // clearHistory() mechanism stays fully testable.
  if (qEnvironmentVariableIsSet("OMAFILES_SELFCHECK")) {
    QVariantMap entry;
    entry.insert(QStringLiteral("text"), text);
    entry.insert(QStringLiteral("timestamp"), QDateTime::currentSecsSinceEpoch());
    m_history.prepend(entry);
    while (m_history.size() > kMaxHistory)
      m_history.removeLast();
    emit historyChanged();
    return;
  }

  // "Omafiles" as the title/app_name centralized here (previously it was
  // repeated in each of the 16+ call sites). app_icon "omafiles" resolves
  // via the user's hicolor icon theme (installed by
  // scripts/install-integrations.sh) -- notify-send's call never passed one.
  QDBusInterface iface(QStringLiteral("org.freedesktop.Notifications"),
                       QStringLiteral("/org/freedesktop/Notifications"),
                       QStringLiteral("org.freedesktop.Notifications"),
                       QDBusConnection::sessionBus());
  QVariantMap hints;
  hints.insert(QStringLiteral("urgency"), QVariant::fromValue(static_cast<uchar>(1))); // normal
  iface.call(QDBus::NoBlock, QStringLiteral("Notify"),
             QStringLiteral("Omafiles"),         // app_name
             quint32(0),                         // replaces_id: always a new toast
             QStringLiteral("omafiles"),          // app_icon (hicolor theme name)
             QStringLiteral("Omafiles"),          // summary
             text,                                // body
             QStringList(),                       // actions: none (explicitly out of scope)
             hints,
             qint32(-1));                         // expire_timeout: server default

  QVariantMap entry;
  entry.insert(QStringLiteral("text"), text);
  entry.insert(QStringLiteral("timestamp"), QDateTime::currentSecsSinceEpoch());
  m_history.prepend(entry);
  while (m_history.size() > kMaxHistory)
    m_history.removeLast();
  emit historyChanged();
}

QVariantList Notifier::history() const { return m_history; }

void Notifier::clearHistory() {
  if (m_history.isEmpty())
    return;
  m_history.clear();
  emit historyChanged();
}
