#pragma once

#include <QAbstractListModel>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVector>
#include <functional>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

class QFileSystemWatcher;

// Backend C++ del listado de directorios (Fase 6.B, josema). Sustituto
// nativo de list-dir.sh + Utils.parseEntries: un QAbstractListModel que
// hace el escaneo con readdir/stat/lstat directos, sin fork por fichero ni
// tuberia de shell NUL-delimitada. Ver BACKEND_DESIGN.md 5.3.
//
// En 6.B se INTRODUCE en paralelo: list-dir.sh sigue siendo la fuente viva
// del panel; este modelo se valida comparando su salida con la del script
// en varios directorios. La conmutacion de consumidores es posterior.
//
// Paridad EXACTA con list-dir.sh (es lo que permite comparar y, luego,
// sustituir sin cambiar comportamiento):
//   - carpetas primero, luego ficheros;
//   - dentro de cada grupo, orden case-insensitive con la MISMA collation
//     de glibc que usa `sort -f` (wcscoll_l sobre un locale_t del entorno);
//   - symlink a dir cuenta como dir; roto va a ficheros con tamano/mtime
//     del propio enlace (lstat), estado "broken";
//   - tamano de las carpetas forzado a 0, igual que el script;
//   - codigos de error equivalentes a los exit codes (2/3/4/1).
//
// Se registra como tipo QML Omafiles.Backend.DirectoryModel; lo consume el
// adaptador services/DirectoryModel.qml (no singleton: varias pestanas
// listan rutas distintas a la vez, cada una su instancia).
class DirectoryModel : public QAbstractListModel {
  Q_OBJECT
  QML_ELEMENT

  // Codigo del ultimo listado, con los MISMOS valores que los exit codes
  // de list-dir.sh para que logic/ pueda mapearlos igual:
  //   0 = ok, 2 = sin permiso (r/x), 3 = no existe, 4 = no es carpeta,
  //   1 = otro (no se pudo abrir).
  Q_PROPERTY(int error READ error NOTIFY errorChanged)

  // true mientras hay un escaneo en vuelo (corre en un hilo del pool, la
  // UI no se bloquea). Util para spinners y para demostrar el no-bloqueo.
  Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

  // Numero de filas del modelo (comodidad para QML).
  Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

  // Instantanea de las filas como array de objetos
  // {type,name,size,mtime,link} -- EXACTAMENTE la forma que producia
  // Utils.parseEntries(list-dir.sh). Es el puente de la migracion (el
  // diseno pide "introducir como fuente de datos con la API de array
  // intacta") y la base de la comparacion con el script.
  Q_PROPERTY(QVariantList entries READ entries NOTIFY listed)

public:
  explicit DirectoryModel(QObject *parent = nullptr);
  ~DirectoryModel() override;

  enum Role {
    NameRole = Qt::UserRole + 1,
    PathRole,
    TypeRole,     // "dir" | "file"
    IsDirRole,    // bool
    IsSymlinkRole,// bool
    LinkRole,     // "" | "valid" | "broken"
    SizeRole,     // qint64 (0 para carpetas, como el script)
    MtimeRole,    // qint64, epoch en segundos
  };

  // Una entrada del listado. Publica porque las funciones de escaneo del
  // .cpp (gatherOne/sortInto) la manejan como valor; no expone nada
  // sensible, es un POD de datos.
  struct Entry {
    QString name;
    QString type; // "dir" | "file"
    QString link; // "" | "valid" | "broken"
    bool isDir = false;
    bool isSymlink = false;
    qint64 size = 0;
    qint64 mtime = 0;
  };

  // Lanza el listado ASINCRONO de `path`. `showHidden` incluye dotfiles.
  // Vuelve al instante; el escaneo corre en un hilo del pool y el
  // resultado se aplica en el hilo de UI (listed()/errorChanged). Un
  // listado que llega con una generacion vieja se descarta (contador de
  // generacion, patron del proyecto: PreviewLoader/previewRequestId).
  Q_INVOKABLE void list(const QString &path, bool showHidden = false);

  // Igual que list() pero fusiona el contenido de VARIOS directorios en un
  // solo listado (Fase 6.C, papelera nativa). Sustituye a list-trash.sh,
  // que hacia lo mismo lanzando list-dir.sh por cada raiz XDG y
  // concatenando. Los directorios que no existen o no se pueden leer se
  // saltan en silencio (igual que el `[[ -d ]] &&` del script). Mismo
  // contrato async y misma senal listed()/entries.
  Q_INVOKABLE void listMany(const QStringList &paths, bool showHidden = false);

  // Vigilancia nativa del ultimo directorio pedido (Fase 6.D). Arranca un
  // QFileSystemWatcher sobre `path` (inotify del kernel via Qt, SIN forkear
  // inotifywait). Emite directoryChanged() cuando su contenido cambia; el
  // debounce + el refresco los sigue haciendo NavigationController, que
  // conserva su guarda de no-refrescar-a-mitad-de-renombrado. Devuelve
  // false si no se pudo vigilar (ruta invalida, limite de descriptores) ->
  // el llamador cae al fallback ProcessWatcher/inotifywait.
  Q_INVOKABLE bool watch(const QString &path);
  // Deja de vigilar. No-op si no habia vigilancia.
  Q_INVOKABLE void unwatch();

  int error() const { return m_error; }
  bool loading() const { return m_loading; }
  QVariantList entries() const;

  // QAbstractListModel
  int rowCount(const QModelIndex &parent = QModelIndex()) const override;
  QVariant data(const QModelIndex &index, int role) const override;
  QHash<int, QByteArray> roleNames() const override;

signals:
  void errorChanged();
  void loadingChanged();
  void countChanged();
  // Emitida cada vez que un listado se aplica de verdad (paridad con
  // DirLister.listed): quien resetee scroll/seleccion por CADA listado se
  // engancha aqui, no a un *Changed que QML puede no disparar.
  void listed();
  // El contenido del directorio vigilado cambio (ver watch()).
  void directoryChanged();

private:
  struct Result {
    int error = 0;
    QVector<Entry> rows;
  };

  // Corre en el hilo worker: escanea UN directorio (comprobaciones de
  // error + readdir + stat/lstat + orden). Estatico a proposito: no toca
  // el modelo ni ningun miembro, asi que es seguro aunque el modelo se
  // destruya mientras el hilo corre. Crea su propio locale_t por llamada.
  static Result scan(const QString &path, bool showHidden);
  // Igual, pero fusiona varios directorios (papelera). Los que fallan se
  // saltan; error siempre 0 (agregado, sin concepto de "esta carpeta
  // fallo").
  static Result scanMany(const QStringList &paths, bool showHidden);
  // Corre en el hilo de UI: reemplaza las filas y emite las senales.
  void apply(Result result, quint64 generation);
  // Lanza un escaneo (uno o varios dirs) en el pool y aplica async.
  void startScan(std::function<Result()> job);

  int m_error = 0;
  bool m_loading = false;
  QString m_path;
  QVector<Entry> m_rows;
  quint64 m_generation = 0; // ultima generacion pedida (escaneo)

  // Bandera de vida compartida con los workers del pool (Fase 10.A). El
  // escaneo es estatico, pero la ENTREGA del resultado hace
  // invokeMethod(this): si el modelo se destruye (cerrar una pestana)
  // mientras un worker sigue en vuelo, eso desreferenciaria un QObject
  // muerto. El worker toma el lock y solo invoca si alive sigue true; el
  // destructor toma el mismo lock y lo pone a false, asi que nunca coinciden.
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();

  QFileSystemWatcher *m_watcher = nullptr; // vigilancia nativa (lazy)
  // Ruta vigilada AHORA MISMO: actua como token de cancelacion del
  // watcher, el equivalente de m_generation para el escaneo. Un evento de
  // QFileSystemWatcher cuya ruta no sea esta es de un watcher viejo (el
  // usuario cambio de carpeta) y se descarta antes de reemitir
  // directoryChanged, para que no repueble la carpeta nueva.
  QString m_watchedPath;
};
