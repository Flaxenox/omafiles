pragma Singleton
import QtQuick
import Quickshell

// Lectura de variables de entorno -- hoy delega directo en
// Quickshell.env(), pero es el ÚNICO sitio del proyecto que lo hace
// (Fase 1.5, previa a Qt6 standalone: ver
// [[project_omafiles_standalone_prep]]). Cuando llegue standalone, solo
// el cuerpo de get() necesita cambiar (a qgetenv/QProcessEnvironment),
// nunca los sitios que lo llaman.
QtObject {
  function get(name) {
    return Quickshell.env(name)
  }
}
