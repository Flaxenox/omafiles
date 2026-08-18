#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <qqmlregistration.h>

// Desktop notifications via org.freedesktop.Notifications (QDBus session
// bus) -- migrated (V1.1) from the previous notify-send subprocess per-call
// fork, per the migration note this file used to carry (BACKEND_DESIGN.md).
// Same fire-and-forget philosophy: no reply is awaited, a missing/
// dead notification daemon fails exactly as silently as notify-send did.
//
// QML singleton (Omafiles.Backend.Notifier): consumed as Notifier.notify("...").
//
// Under --selfcheck the real D-Bus toast is skipped (history() still
// records normally) -- repeated selfcheck runs during a normal dev
// session were spamming the developer's real notification tray otherwise,
// confirmed directly (2026-08-18).
//
// Adds a session-only history (last kMaxHistory, newest first) so a missed
// desktop toast isn't lost forever -- this was the concrete gap behind the
// unreproduced "Trash freeze" report (no way to check afterward what, if
// anything, had actually happened). Deliberately NOT persisted across
// restarts and NOT actionable (no inline buttons) -- see the v1.1 feature
// inventory's explicit scope note: this is a reliability fix, not a
// notification center.
class Notifier : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

  Q_PROPERTY(QVariantList history READ history NOTIFY historyChanged)

public:
  explicit Notifier(QObject *parent = nullptr);

  // Shows a desktop notification with the fixed "Omafiles" title
  // and `text` as the body, and records it in history().
  Q_INVOKABLE void notify(const QString &text);

  // { text, timestamp (epoch seconds, see shared/Utils.js's relativeTime) },
  // newest first, capped at kMaxHistory entries.
  QVariantList history() const;

  // Clears the in-memory history (does not affect already-shown toasts).
  Q_INVOKABLE void clearHistory();

signals:
  void historyChanged();

private:
  static constexpr int kMaxHistory = 50;
  QVariantList m_history;
};
