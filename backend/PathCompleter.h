#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <qqmlregistration.h>

// Autocompletado NATIVO de rutas para la barra de dirección (Ctrl+L, Fase 26).
// Sin procesos externos (nada de `ls`/`compgen`): resuelve en C++ con QDir, que
// es instantáneo y no forkea. Es el backend de services/PathCompleter.qml.
//
// Singleton QML (Omafiles.Backend.PathCompleter): sin estado, una instancia
// basta. Se consume como PathCompleter.complete(text, base).
class PathCompleter : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit PathCompleter(QObject *parent = nullptr);

  // Devuelve hasta `limit` rutas de DIRECTORIO que completan `input`. La barra
  // de dirección navega a carpetas, así que solo se completan directorios (con
  // "/" final, listo para seguir escribiendo el siguiente tramo).
  //
  // `input` puede ser:
  //   - absoluto            (/home/jose/Doc)
  //   - con tilde           (~/Doc, ~)
  //   - relativo a `base`   (Doc, ../Vídeos)  -> se resuelve contra `base`
  //
  // El emparejamiento del último tramo es smart-case (sensible a mayúsculas
  // solo si el prefijo trae alguna). Orden alfabético natural, ocultos fuera
  // salvo que el prefijo empiece por ".".
  Q_INVOKABLE QStringList complete(const QString &input, const QString &base,
                                   int limit = 50) const;

  // Expande ~ / ~/... a la home. Devuelve `input` tal cual si no empieza por ~.
  // Lo usa el lado QML al navegar (Enter) para aceptar ~ escrito a mano.
  Q_INVOKABLE QString expandTilde(const QString &input) const;
};
