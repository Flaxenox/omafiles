#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QGuiApplication>
#include <QImage>
#include <QPageSize>
#include <QPainter>
#include <QPdfWriter>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QObject>
#include <QQuickStyle>
#include <QTemporaryDir>
#include <cstdio>

// Reporter del selfcheck: salida DETERMINISTA a stdout (no depende de las
// reglas de logging de QML, que en release pueden silenciar console.log).
// Expuesto al QML como context property `SelfCheckOut`.
class SelfCheckReporter : public QObject {
  Q_OBJECT
 public:
  using QObject::QObject;
  Q_INVOKABLE void line(const QString &text) {
    printf("%s\n", text.toLocal8Bit().constData());
    fflush(stdout);
  }
};

// Bootstrap Qt6 del frontend standalone (Fase 4, josema). En modo normal
// carga integrations/standalone/Main.qml, que instancia el MISMO
// core/OmafilesContent.qml que el frontend Quickshell, dentro de un
// ApplicationWindow real.
//
// Fase 12 (josema): añade `--selfcheck`. En ese modo el ejecutable deja de
// ser un host alternativo y pasa a ser el entorno OFICIAL de validación
// automática: arranca headless (offscreen), monta fixtures en un directorio
// temporal auto-limpiable y carga integrations/standalone/SelfCheck.qml, que
// ejercita los subsistemas de backend/frontend/integración y termina con
// Qt.exit(nº de fallos). Ver AUDIT-V2.md (Fase 12) y SelfCheck.qml.
//
// OMAFILES_SOURCE_DIR / OMAFILES_QML_IMPORT_DIR los define CMakeLists.txt.

namespace {

// Añade al engine los mismos import paths que necesita el core: los
// adaptadores qs.Commons/qs.Ui del standalone y el plugin C++
// Omafiles.Backend (el mismo .so que carga Quickshell).
void addImportPaths(QQmlApplicationEngine &engine, const QString &sourceDir) {
  engine.addImportPath(sourceDir + "/integrations/standalone/qml_modules");
  engine.addImportPath(QStringLiteral(OMAFILES_QML_IMPORT_DIR));
}

// Genera los ficheros de prueba deterministas que el selfcheck necesita.
// Todo cuelga de `base` (un QTemporaryDir), así que se borra solo al salir.
// Requiere una QGuiApplication viva (QImage/QPdfWriter/QPainter).
bool writeSelfCheckFixtures(const QString &base) {
  QDir d(base);
  if (!d.mkpath("list/sub") || !d.mkpath("watch") || !d.mkpath("ops") ||
      !d.mkpath("json")) {
    return false;
  }

  // Directorio con contenido conocido para DirectoryModel (orden natural:
  // la subcarpeta primero, luego los .txt).
  for (const QString &name : {QStringLiteral("alpha.txt"),
                              QStringLiteral("beta.txt"),
                              QStringLiteral("gamma.txt")}) {
    QFile f(base + "/list/" + name);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write("x");
    f.close();
  }

  // Fichero de texto para PreviewProvider.
  QFile note(base + "/note.txt");
  if (!note.open(QIODevice::WriteOnly)) return false;
  note.write("hello selfcheck\nsecond line\n");
  note.close();

  // Symlink para validar que copy/move preservan enlaces como enlaces.
  QFile::remove(base + "/link.txt");
  QFile::link(base + "/note.txt", base + "/link.txt");

  // Fichero grande (32 MiB) para probar la cancelación cooperativa a mitad
  // de copia: lo bastante grande para que la copia abarque muchos trozos y
  // el cancel() (disparado en el siguiente turno del bucle) caiga en medio.
  {
    QFile big(base + "/big.bin");
    if (!big.open(QIODevice::WriteOnly)) return false;
    const QByteArray chunk(1 << 20, '\0'); // 1 MiB
    for (int i = 0; i < 32; ++i) big.write(chunk);
    big.close();
  }

  // PNG real para ThumbnailProvider (ruta QImageReader).
  QImage img(16, 16, QImage::Format_RGB32);
  img.fill(Qt::red);
  if (!img.save(base + "/img.png", "PNG")) return false;

  // PDF real de una página para ThumbnailProvider (ruta QPdfDocument/qpdf).
  {
    QPdfWriter pdf(base + "/doc.pdf");
    pdf.setPageSize(QPageSize(QPageSize::A4));
    QPainter p(&pdf);
    if (!p.isActive()) return false;
    p.drawText(200, 200, QStringLiteral("selfcheck"));
    p.end();
  }

  return QFile::exists(base + "/img.png") && QFile::exists(base + "/doc.pdf");
}

int runSelfCheck(int argc, char *argv[]) {
  // Headless por defecto (CI): si el usuario no forzó plataforma, offscreen.
  if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
    qputenv("QT_QPA_PLATFORM", "offscreen");
  }
  // El core lee esto en AppBindings para NO autoregistrarse como gestor de
  // archivos durante la validación (sin efectos secundarios en el sistema).
  qputenv("OMAFILES_SELFCHECK", "1");

  QGuiApplication app(argc, argv);
  QQuickStyle::setStyle("Basic");

  const QString sourceDir = QStringLiteral(OMAFILES_SOURCE_DIR);

  // Bajo $HOME/.cache (no /tmp): así los fixtures viven en el MISMO montaje
  // que la papelera XDG del usuario, y trash/restore hacen round-trip como en
  // uso real (en /tmp, tmpfs aparte, moveToTrash y restore usan papeleras
  // distintas). Sigue siendo auto-limpiable (QTemporaryDir).
  QDir().mkpath(QDir::homePath() + "/.cache");
  QTemporaryDir tmp(QDir::homePath() + "/.cache/omafiles-selfcheck-XXXXXX");
  if (!tmp.isValid() || !writeSelfCheckFixtures(tmp.path())) {
    fprintf(stderr, "[selfcheck] no se pudieron crear los fixtures\n");
    return 2;
  }

  QQmlApplicationEngine engine;
  addImportPaths(engine, sourceDir);
  SelfCheckReporter reporter;
  engine.rootContext()->setContextProperty("selfCheckTmpDir", tmp.path());
  engine.rootContext()->setContextProperty("SelfCheckOut", &reporter);

  bool failedToCreate = false;
  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      [&failedToCreate]() {
        failedToCreate = true;
        QCoreApplication::exit(2);
      },
      Qt::QueuedConnection);

  engine.load(QUrl::fromLocalFile(sourceDir +
                                  "/integrations/standalone/SelfCheck.qml"));
  if (failedToCreate || engine.rootObjects().isEmpty()) {
    fprintf(stderr, "[selfcheck] no se pudo cargar SelfCheck.qml\n");
    return 2;
  }

  // SelfCheck.qml llama Qt.exit(nº de fallos) al terminar; ese código sale
  // por app.exec(). tmp se destruye (y limpia) al volver de main.
  return app.exec();
}

int runNormal(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);

  // qs.Ui usa QtQuick.Controls (Button/TextField) -- Basic es el estilo que
  // no depende de ningún backend nativo extra, el más seguro.
  QQuickStyle::setStyle("Basic");

  QQmlApplicationEngine engine;
  const QString sourceDir = QStringLiteral(OMAFILES_SOURCE_DIR);
  addImportPaths(engine, sourceDir);

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

  engine.load(
      QUrl::fromLocalFile(sourceDir + "/integrations/standalone/Main.qml"));
  if (engine.rootObjects().isEmpty()) return -1;

  return app.exec();
}

}  // namespace

int main(int argc, char *argv[]) {
  for (int i = 1; i < argc; ++i) {
    if (QString::fromLocal8Bit(argv[i]) == QLatin1String("--selfcheck")) {
      return runSelfCheck(argc, argv);
    }
  }
  return runNormal(argc, argv);
}

#include "main.moc"
