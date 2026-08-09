#pragma once

#include <QObject>
#include <QString>
#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

// Backend C++ de operaciones de fichero (Fase 7, josema). Sustituto nativo
// de los comandos de shell (cp/mv/rm/mkdir/gio trash/...) que hoy monta y
// ejecuta ActionEngine.runAction. Ver BACKEND_DESIGN.md 5.3 (FileOps).
//
// Fase 7 lo INTRODUCE y valida; de momento solo "nueva carpeta" (mkdir) se
// cablea en vivo. El resto de consumidores (copiar/mover/borrar/papelera,
// con su undo/conflicto/progreso sobre shell) migran en un escalon
// posterior -- ese motor es el codigo mas delicado (destructivo + undo).
//
// API asincrona: cada operacion vuelve al instante, corre en un hilo del
// QThreadPool y entrega el resultado por senal en el hilo de UI. Tres
// senales: progress (solo copias/movimientos grandes), finished (exito) y
// error (fallo). El `op` identifica la operacion ("copy", "move", ...) y
// `path` su ruta principal, para que el consumidor correlacione.
//
// Sin dependencia de Quickshell: solo Qt publico. El refresco tras una
// operacion NO lo dispara este tipo -- lo hace el QFileSystemWatcher de
// DirectoryModel (Fase 6.D) al cambiar el directorio. La integracion con
// Notifier vive en el adaptador QML (services/FileOperations.qml), que
// reemite estas senales y avisa en los errores.
class FileOperations : public QObject {
  Q_OBJECT
  QML_ELEMENT
  QML_SINGLETON

public:
  explicit FileOperations(QObject *parent = nullptr);
  ~FileOperations() override;

  // Copia `source` a `destination` (ruta destino COMPLETA, incluido el
  // nombre final). Recursiva si source es carpeta (preserva symlinks como
  // symlinks y el modo de cada fichero). Emite progress durante la copia.
  // Si destination existe: con overwrite=true lo REEMPLAZA (borra y copia);
  // con overwrite=false, error. Fase 13.A (josema): overwrite añade el
  // equivalente a `cp -f`; sin él era `cp -n`.
  Q_INVOKABLE void copy(const QString &source, const QString &destination,
                        bool overwrite = false);

  // Cancela la operación en curso (copia larga) de forma cooperativa: el
  // worker comprueba el flag entre trozos y aborta con error "cancelled".
  // Fase 13.A. El consumidor (ActionEngine) limpia el destino parcial.
  Q_INVOKABLE void cancel();

  // Mueve `source` a `destination` (ruta destino COMPLETA). Intenta un
  // rename atomico (mismo sistema de ficheros); si cruza de disco, copia +
  // borra el origen (con progress, cancelable). Si destination existe: con
  // overwrite=true lo REEMPLAZA (borra y mueve, = `mv -f`); con
  // overwrite=false, error. Fase 13.B (josema).
  Q_INVOKABLE void move(const QString &source, const QString &destination,
                        bool overwrite = false);

  // Renombra `path` a `newName` (mismo directorio). No sobrescribe.
  Q_INVOKABLE void rename(const QString &path, const QString &newName);

  // Borra `path` PERMANENTEMENTE (recursivo si es carpeta). Sin papelera,
  // sin undo -- para eso trash().
  Q_INVOKABLE void remove(const QString &path);

  // Crea la carpeta `path` (y los padres que falten, como mkdir -p).
  Q_INVOKABLE void mkdir(const QString &path);

  // Envia `path` a la papelera XDG (QFile::moveToTrash, crea el .trashinfo
  // estandar; en discos ajenos usa su .Trash-$UID como manda la spec).
  Q_INVOKABLE void trash(const QString &path);

  // Restaura desde la papelera el fichero `path` (dentro de <raiz>/files/):
  // lee su <raiz>/info/<nombre>.trashinfo, lo mueve de vuelta a su ruta
  // original (Path=, percent-decoded) y borra el .trashinfo.
  Q_INVOKABLE void restore(const QString &path);

signals:
  // Progreso 0..100 de una copia/movimiento en curso.
  void progress(const QString &op, const QString &path, double pct);
  // La operacion termino con exito.
  void finished(const QString &op, const QString &path);
  // La operacion fallo; `message` describe el motivo.
  void error(const QString &op, const QString &path, const QString &message);

private:
  struct Result {
    bool ok = false;
    QString message;
  };

  // Lanza `job` en el pool y emite finished/error segun su Result, en el
  // hilo de UI. `op`/`path` para las senales.
  void run(const QString &op, const QString &path, std::function<Result()> job);
  // Emite progress(op, path, pct) de forma segura desde el hilo worker.
  void emitProgress(const QString &op, const QString &path, double pct);

  // Flag de cancelación cooperativa (ver cancel()/copy()). Atómico porque lo
  // escribe el hilo de UI y lo lee el worker del pool.
  std::atomic<bool> m_cancelled{false};

  // Guardia de vida contra el `this` colgante (mismo patrón que
  // DirectoryModel, Fase 10.A): un worker del pool que termine DESPUÉS de que
  // el singleton se destruya (p.ej. al cerrar la app a mitad de una copia)
  // haría invokeMethod sobre memoria muerta -> crash. El worker comprueba
  // `alive` bajo el mutex antes de entregar; el destructor lo pone a false
  // bajo el mismo mutex. Fase 13.B.
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();
};
