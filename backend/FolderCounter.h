#pragma once

#include <QObject>
#include <QString>
#include <qqmlregistration.h>

// Cuenta las entradas directas de una carpeta para el subtítulo de la lista de
// ficheros ("42 items", Fase 23, josema). NO toca DirectoryModel (que lista la
// carpeta ACTUAL): cuenta el contenido de las SUBcarpetas visibles, a demanda
// (una por fila-carpeta) y de forma ASÍNCRONA (QThreadPool) para no bloquear la
// UI ni en carpetas enormes (node_modules). QDirIterator recorre el directorio
// sin stat por entrada. El resultado llega por la señal counted(path, n); la
// caché (con invalidación) la lleva state/FolderCountState en QML. Singleton
// QML, sin dependencia de Quickshell.
class FolderCounter : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit FolderCounter(QObject *parent = nullptr);

  // Lanza el conteo async de `path`. includeHidden refleja NavState.showHidden
  // para que el número cuadre con lo que se vería dentro. Emite counted(path,n)
  // al terminar (n = -1 si no se puede abrir: permisos, no existe, no es dir).
  Q_INVOKABLE void request(const QString &path, bool includeHidden);

signals:
  void counted(const QString &path, int n);
};
