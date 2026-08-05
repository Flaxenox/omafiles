#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlFileSelector>
#include <QQuickStyle>

// Bootstrap Qt6 mínimo del frontend standalone (Fase 4, josema: primer
// arranque, no una app completa todavía). Carga
// integrations/standalone/Main.qml, que a su vez instancia
// core/OmafilesContent.qml (el mismo núcleo que usa el frontend
// Quickshell) dentro de un ApplicationWindow real. OMAFILES_SOURCE_DIR
// (definido por CMakeLists.txt) apunta a la raíz del proyecto en disco
// -- carga por sistema de ficheros, sin empaquetar en qrc todavía
// (suficiente para demostrar que el núcleo arranca bajo un host
// distinto; empaquetado/instalación quedan fuera del alcance de esta
// fase).
int main(int argc, char *argv[]) {
  QGuiApplication app(argc, argv);

  // qs.Ui usa QtQuick.Controls (Button/TextField) -- Basic es el estilo
  // que no depende de ningún backend nativo extra, el más seguro para un
  // primer arranque.
  QQuickStyle::setStyle("Basic");

  QQmlApplicationEngine engine;

  const QString sourceDir = QStringLiteral(OMAFILES_SOURCE_DIR);
  // Adaptadores mínimos de qs.Commons/qs.Ui (Fase 4) -- ver
  // integrations/standalone/qml_modules/. Añadido ANTES de cargar
  // Main.qml para que cualquier "import qs.Commons"/"import qs.Ui" en
  // core/logic/panels/dialogs/shared se resuelva contra estos adaptadores
  // en vez de fallar (esos módulos solo existen dentro de Quickshell).
  engine.addImportPath(sourceDir + "/integrations/standalone/qml_modules");

  // services/+standalone/*.qml sustituye automáticamente a
  // services/*.qml (ProcessRunner, ProcessWatcher, Detached, Notifier,
  // Env) vía el selector "standalone" -- mecanismo nativo de Qt
  // (QQmlFileSelector) para dar una implementación alternativa sin
  // tocar ni un import en logic/. Los servicios reales usan
  // Quickshell.Io.Process, que no existe fuera de Quickshell.
  auto *fileSelector = new QQmlFileSelector(&engine, &engine);
  fileSelector->setExtraSelectors(QStringList{QStringLiteral("standalone")});

  // QML no tiene acceso nativo a variables de entorno -- services/
  // +standalone/Env.qml lee esto para HOME (la única que usa el
  // núcleo). Puesto en el contexto raíz ANTES de cargar Main.qml.
  engine.rootContext()->setContextProperty(
      QStringLiteral("standaloneHomeDir"), qEnvironmentVariable("HOME"));

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

  engine.load(QUrl::fromLocalFile(sourceDir + "/integrations/standalone/Main.qml"));

  if (engine.rootObjects().isEmpty()) return -1;

  return app.exec();
}
