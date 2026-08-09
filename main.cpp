#include <QCoreApplication>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
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

  // Plugin C++ Omafiles.Backend (Fase 5.B): ya no va compilado dentro del
  // binario, se carga por import path desde build/qml -- EXACTAMENTE el
  // mismo mecanismo y el mismo .so que usara Quickshell. Anadido antes de
  // cargar Main.qml para que "import Omafiles.Backend" (en Main.qml y en
  // services/*.qml) resuelva.
  engine.addImportPath(QStringLiteral(OMAFILES_QML_IMPORT_DIR));

  // Fase 5.C (josema): ya no hay QQmlFileSelector. Existia para que
  // services/+standalone/*.qml sustituyera a services/*.qml en el host
  // standalone, porque la version Quickshell usaba Quickshell.Io.Process
  // (inexistente fuera de Quickshell). Ahora services/*.qml es una unica
  // implementacion sobre Omafiles.Backend que sirve a los dos frontends,
  // asi que no hay dos variantes que seleccionar y services/+standalone/
  // se ha borrado entero.

  // Las variables de entorno se leen ya desde el backend C++
  // (Omafiles.Backend.Env, qEnvironmentVariable real) -- ver
  // services/Env.qml. Fase 4 las inyectaba aqui como context property;
  // Fase 5 lo elimina.

  QObject::connect(
      &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
      []() { QCoreApplication::exit(-1); }, Qt::QueuedConnection);

  engine.load(QUrl::fromLocalFile(sourceDir + "/integrations/standalone/Main.qml"));

  if (engine.rootObjects().isEmpty()) return -1;

  return app.exec();
}
