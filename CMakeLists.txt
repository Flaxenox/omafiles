cmake_minimum_required(VERSION 3.21)
project(omafiles-standalone LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)

qt_standard_project_setup()

qt_add_executable(omafiles-standalone main.cpp)

target_link_libraries(omafiles-standalone PRIVATE
  Qt6::Core
  Qt6::Gui
  Qt6::Qml
  Qt6::Quick
  Qt6::QuickControls2
)

# Fase 4 (josema): primer arranque standalone, sin empaquetar todavía --
# el binario carga el QML directo del árbol fuente (ver main.cpp), así
# que solo hace falta que sepa dónde está esa raíz.
target_compile_definitions(omafiles-standalone PRIVATE
  OMAFILES_SOURCE_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)
