cmake_minimum_required(VERSION 3.21)
project(omafiles LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 Pdf DBus Network)

qt_standard_project_setup()

# ---------------------------------------------------------------------------
# backend/ : modulo QML Omafiles.Backend como PLUGIN COMPARTIDO (Fase 5.B)
# ---------------------------------------------------------------------------
# Antes (5.A) el backend se compilaba DENTRO del ejecutable standalone, lo
# que impedia que Quickshell (binario preinstalado que solo carga QML) lo
# usara. Ahora se construye como biblioteca compartida con plugin QML: un
# unico .so + qmldir en build/qml/Omafiles/Backend/, cargable por import
# path tanto por el standalone como por Quickshell -- el mismo fichero
# para ambos, sin duplicacion. Ver BACKEND_DESIGN.md, escalon 5.B.
#
qt_add_library(omafiles-backend SHARED)
qt_add_qml_module(omafiles-backend
  URI Omafiles.Backend
  VERSION 1.0
  PLUGIN_TARGET omafiles-backend
  OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/Omafiles/Backend
  SOURCES
    backend/ProcessRunner.h
    backend/ProcessRunner.cpp
    backend/ProcessWatcher.h
    backend/ProcessWatcher.cpp
    backend/Env.h
    backend/Env.cpp
    backend/Detached.h
    backend/Detached.cpp
    backend/Notifier.h
    backend/Notifier.cpp
    backend/JsonStore.h
    backend/JsonStore.cpp
    backend/DirectoryModel.h
    backend/DirectoryModel.cpp
    backend/FileOperations.h
    backend/FileOperations.cpp
    backend/ThumbnailProvider.h
    backend/ThumbnailProvider.cpp
    backend/PreviewProvider.h
    backend/PreviewProvider.cpp
    backend/SearchWorker.h
    backend/SearchWorker.cpp
    backend/NetworkMounts.h
    backend/NetworkMounts.cpp
    backend/UDisksWatcher.h
    backend/UDisksWatcher.cpp
    backend/FolderCounter.h
    backend/FolderCounter.cpp
    backend/PathCompleter.h
    backend/PathCompleter.cpp
)
# El registro de tipos QML autogenerado hace #include <ProcessRunner.h>
# (corchetes angulares) -- backend/ tiene que estar en el include path o
# el __has_include falla y el tipo queda sin declarar.
target_include_directories(omafiles-backend PRIVATE backend)
target_link_libraries(omafiles-backend PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Pdf
  Qt6::DBus
)

# ---------------------------------------------------------------------------
# integrations/standalone : frontend Qt6
# ---------------------------------------------------------------------------
qt_add_executable(omafiles-standalone main.cpp)

# El standalone ya NO compila el backend dentro: lo carga por import path
# igual que hara Quickshell (main.cpp usa OMAFILES_QML_IMPORT_DIR). Solo
# necesita que el plugin este construido antes de arrancar.
add_dependencies(omafiles-standalone omafiles-backend)

target_link_libraries(omafiles-standalone PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
  Qt6::QuickControls2
  Qt6::Network
)

# OMAFILES_SOURCE_DIR: raiz del arbol QML (se carga del fuente, sin qrc).
# OMAFILES_QML_IMPORT_DIR: donde vive el plugin Omafiles.Backend, para
# anadirlo al import path del engine (ver main.cpp).
target_compile_definitions(omafiles-standalone PRIVATE
  OMAFILES_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
  OMAFILES_QML_IMPORT_DIR="${CMAKE_BINARY_DIR}/qml"
)

# ---------------------------------------------------------------------------
# Deploy estable del modulo (Fase 5.B.1)
# ---------------------------------------------------------------------------
# El shell real de Omarchy (Quickshell bajo uwsm) carga Omafiles.Backend
# por QML_IMPORT_PATH, definido de forma persistente en
# ~/.config/environment.d/omafiles-backend.conf. Esa variable apunta a una
# ruta ESTABLE de usuario, no al build/ (efimero, se borra al limpiar).
# `cmake --install build` copia el modulo ahi. Ver BACKEND_DESIGN.md 4.
set(OMAFILES_QML_INSTALL_DIR "$ENV{HOME}/.local/lib/qt6/qml"
    CACHE PATH "Ruta estable donde se instala el modulo QML Omafiles.Backend")
install(DIRECTORY "${CMAKE_BINARY_DIR}/qml/Omafiles"
        DESTINATION "${OMAFILES_QML_INSTALL_DIR}")

# ---------------------------------------------------------------------------
# Instalacion del binario standalone (Fase 25: frontend Qt6 oficial)
# ---------------------------------------------------------------------------
# El ejecutable se instala RENOMBRADO a `omafiles` en ~/.local/bin (en el PATH
# del usuario, sin root). El QML se sigue cargando del repo (OMAFILES_SOURCE_
# DIR) durante RC1: el repo es la ruta estable de instalacion por ahora; el
# empaquetado con qrc/AUR llega despues de v1.0.0-rc1. El .desktop, el icono y
# el servicio D-Bus FileManager1 los instala scripts/install-integrations.sh
# (idempotente, lo lanza AppBindings al abrir).
set(OMAFILES_BIN_INSTALL_DIR "$ENV{HOME}/.local/bin"
    CACHE PATH "Ruta donde se instala el binario omafiles")
install(PROGRAMS "$<TARGET_FILE:omafiles-standalone>"
        DESTINATION "${OMAFILES_BIN_INSTALL_DIR}"
        RENAME omafiles)

# ---------------------------------------------------------------------------
# Arnés de validación (Fase 12)
# ---------------------------------------------------------------------------
# `cmake --build build --target selfcheck` compila el standalone y ejecuta su
# modo --selfcheck (headless, sin Quickshell, auto-limpia sus temporales).
# Sale 0 si todo pasa, 1 si algo falla -> usable como paso de CI. Ver
# integrations/standalone/SelfCheck.qml.
add_custom_target(selfcheck
  COMMAND omafiles-standalone --selfcheck
  DEPENDS omafiles-standalone
  WORKING_DIRECTORY "${CMAKE_BINARY_DIR}"
  USES_TERMINAL
  COMMENT "Ejecutando omafiles --selfcheck")
