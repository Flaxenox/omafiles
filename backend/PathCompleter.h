#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <qqmlregistration.h>

// NATIVE path autocompletion for the address bar (Ctrl+L, Phase 26).
// No external processes (no `ls`/`compgen`): it resolves in C++ with QDir, which
// is instantaneous and does not fork. It is the backend of
//
// QML singleton (Omafiles.Backend.PathCompleter): stateless, one instance is
// enough. It is consumed as PathCompleter.complete(text, base).
class PathCompleter : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit PathCompleter(QObject *parent = nullptr);

  // Returns up to `limit` DIRECTORY paths that complete `input`. The address
  // bar navigates to folders, so only directories are completed (with a
  // trailing "/", ready to keep typing the next segment).
  //
  // `input` can be:
  //   - absolute            (/home/jose/Doc)
  //   - with a tilde        (~/Doc, ~)
  //   - relative to `base`  (Doc, ../Videos)  -> resolved against `base`
  //
  // The last-segment matching is smart-case (case-sensitive only if the prefix
  // has any uppercase). Natural alphabetical order, hidden files excluded
  // unless the prefix starts with ".".
  Q_INVOKABLE QStringList complete(const QString &input, const QString &base,
                                   int limit = 50) const;

  // Expands ~ / ~/... to the home. Returns `input` as is if it does not start
  // with ~. It is used by the QML side when navigating (Enter) to accept a ~
  // typed by hand.
  Q_INVOKABLE QString expandTilde(const QString &input) const;
};
