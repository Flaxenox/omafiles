import QtQuick
import qs.Commons
import qs.Ui

// Barra lateral (marcadores/recientes/unidades/red). Décimo componente
// extraído de Omafiles.qml, y el primero que no es un diálogo modal --
// está siempre visible, así que no hace falta forzar ninguna propiedad
// a mano para probarlo en vivo, basta con reiniciar el shell y mirar.
//
// Más superficie de interfaz que los anteriores: los constructores de
// icono/acciones de menú contextual (iconForBookmark, bookmarkActions,
// etc.) se pasan como referencias a función -- QML permite tratar una
// function de nivel raíz como un valor normal -- en vez de intentar
// replicar su lógica aquí (a diferencia de ChmodPanel.qml, donde SÍ
// mereció la pena reproducir un cálculo pequeño en local, aquí son
// demasiadas funciones y algunas leen Paths.homeDir/trashDir).
Item {
  id: root

  property var bookmarks: []
  property var recentFiles: []
  property var mounts: []
  property var networkMounts: []
  property string currentPath: ""
  property string dropHoverPath: ""
  // Device path cuya expulsión está en curso -> spinner del botón de eject
  // (Fase 21). Lo alimenta MainLayout desde MountsState.ejectingDevice.
  property string ejectingDevice: ""

  // Item contra el que mapToItem() calcula la posición del menú
  // contextual -- en Omafiles.qml es "card" (el BorderSurface raíz del
  // panel), que un componente aparte no puede ver por su cuenta.
  property Item positionRelativeTo: null

  property var iconForBookmark: null
  property var iconFor: null
  property var iconForMount: null
  property var iconForNetworkMount: null
  property var openContextMenu: null
  property var bookmarkActionsFor: null
  property var mountActionsFor: null
  property var networkMountActionsFor: null

  signal bookmarkOpened(var bookmark)
  signal recentOpened(var item)
  signal recentLaunched(var item)
  signal recentRemoveRequested(string path)
  signal recentClearRequested()
  signal mountActivated(var mount)
  signal mountEjectRequested(var mount)
  signal networkMountOpened(var mount)
  signal connectRequested()
  signal filesDropped(var drop, string destPath)
  signal dropHoverChanged(string path)

  Column {
    id: sidebar
    // Sigue el ancho real del componente (lo fija MainLayout), no un 160 fijo:
    // así los separadores/cabeceras/filas (todos width: sidebar.width) ocupan
    // todo el ancho. Antes, al ensanchar la Sidebar, se quedaban cortos.
    width: parent.width
    height: parent.height
    spacing: Style.spacing.md

    PanelSectionHeader {
      text: "BOOKMARKS"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.bookmarks

      CursorSurface {
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: bookmarkMouse.containsMouse
        current: isCurrent || root.dropHoverPath === modelData.path
        Accessible.role: Accessible.ListItem
        Accessible.name: "Bookmark, " + modelData.label
        Accessible.selected: isCurrent

        DropArea {
          // Deshabilitado para marcadores de fichero -- soltar
          // algo "sobre un fichero" no tiene destino real (a
          // diferencia de una carpeta), destDir tendría que ser un
          // directorio.
          anchors.fill: parent
          enabled: modelData.type !== "file"
          keys: ["text/uri-list"]
          onEntered: function (drag) {
            if (!drag.hasUrls) { drag.accepted = false; return }
            root.dropHoverChanged(modelData.path)
          }
          onExited: if (root.dropHoverPath === modelData.path) root.dropHoverChanged("")
          onDropped: function (drop) {
            root.dropHoverChanged("")
            root.filesDropped(drop, modelData.path)
          }
        }

        OpticalGlyph {
          id: bookmarkIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconForBookmark(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: bookmarkIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - bookmarkIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: bookmarkMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.bookmarkActionsFor(modelData))
              return
            }
            root.bookmarkOpened(modelData)
          }
        }
      }
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      visible: root.recentFiles.length > 0
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.xs
    }

    PanelSectionHeader {
      visible: root.recentFiles.length > 0
      text: "RECENT"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      visible: root.recentFiles.length > 0
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.recentFiles

      CursorSurface {
        required property var modelData
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: recentMouse.containsMouse
        Accessible.role: Accessible.ListItem
        Accessible.name: "Recent file, " + modelData.name

        OpticalGlyph {
          id: recentIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconFor({ type: "file", name: parent.modelData.name })
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: recentIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.name
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - recentIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: recentMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, [
                { label: "Open", action: function () { root.recentOpened(modelData) } },
                { label: "Remove from recent", destructive: true, action: function () { root.recentRemoveRequested(modelData.path) } },
                { label: "Clear recent", destructive: true, action: function () { root.recentClearRequested() } }
              ])
              return
            }
            root.recentOpened(modelData)
          }
          onDoubleClicked: root.recentLaunched(modelData)
        }
      }
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      visible: root.mounts.length > 0
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.xs
    }

    PanelSectionHeader {
      visible: root.mounts.length > 0
      text: "DEVICES"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      visible: root.mounts.length > 0
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.mounts

      CursorSurface {
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: mountMouse.containsMouse
        current: isCurrent || root.dropHoverPath === modelData.path
        Accessible.role: Accessible.ListItem
        Accessible.name: modelData.label + (modelData.mounted ? "" : ", not mounted")
        Accessible.selected: isCurrent

        DropArea {
          // Solo unidades ya montadas -- soltar en una sin montar no
          // tiene destino real todavía.
          anchors.fill: parent
          enabled: modelData.mounted
          keys: ["text/uri-list"]
          onEntered: function (drag) {
            if (!drag.hasUrls) { drag.accepted = false; return }
            root.dropHoverChanged(modelData.path)
          }
          onExited: if (root.dropHoverPath === modelData.path) root.dropHoverChanged("")
          onDropped: function (drop) {
            root.dropHoverChanged("")
            root.filesDropped(drop, modelData.path)
          }
        }

        OpticalGlyph {
          id: mountIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          opacity: parent.modelData.mounted ? 1.0 : 0.5
          text: root.iconForMount(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: mountIcon.right
          anchors.leftMargin: Style.spacing.xs
          opacity: parent.modelData.mounted ? 1.0 : 0.5
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          // Reserva sitio para el botón de eject cuando el dispositivo es
          // expulsable, para que el nombre no salte al aparecer en hover.
          width: sidebar.width - Style.spacing.sm * 2 - mountIcon.width - Style.spacing.xs
            - (parent.modelData.removable ? Style.font.title + Style.spacing.sm : 0)
        }

        PanelToolTip {
          visible: mountMouse.containsMouse && !parent.modelData.mounted
          text: "Not mounted -- click to mount"
        }

        MouseArea {
          id: mountMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.mountActionsFor(modelData))
              return
            }
            root.mountActivated(modelData)
          }
        }

        // Botón de expulsión (Fase 21): solo en dispositivos expulsables.
        // Oculto en reposo; aparece con fade suave (120 ms) + leve
        // deslizamiento de 3 px al pasar el ratón por la fila (estética Omarchy
        // Quattro, sin rebotes). Mientras la expulsión está en curso muestra un
        // spinner y no acepta más clics; la fila desaparece sola cuando
        // UDisksWatcher refresca el listado (sin timers). Reutiliza
        // mountOps.ejectMount vía la señal mountEjectRequested.
        Item {
          id: ejectSlot
          readonly property var mount: parent.modelData
          readonly property bool isCurrent: parent.isCurrent
          readonly property bool ejecting: mount.device === root.ejectingDevice
          readonly property bool hovered: mountMouse.containsMouse || ejectMouse.containsMouse
          visible: mount.removable
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          width: Style.font.title
          height: Style.font.title

          OpticalGlyph {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: ejectSlot.hovered ? 0 : 3
            width: Style.font.title
            height: Style.font.title
            visible: !ejectSlot.ejecting
            text: "\u{F01EA}" // nf-md-eject (verificado en el cmap de la fuente)
            fontFamily: Style.font.family
            fontSize: Style.font.icon
            color: ejectSlot.isCurrent ? Color.menu.selectedText : Color.menu.text
            // Siempre visible pero discreto en reposo (Omarchy Quattro), más
            // brillante al pasar el ratón por la fila -- oculto del todo (0.0)
            // era imposible de descubrir.
            opacity: ejectSlot.hovered ? 0.95 : 0.4
            Behavior on opacity { NumberAnimation { duration: 120 } }
            Behavior on anchors.rightMargin { NumberAnimation { duration: 120 } }
          }

          // Spinner: punto en órbita (sin glyph ni timers), solo al expulsar.
          Item {
            id: ejectSpinner
            anchors.centerIn: parent
            width: Style.font.icon
            height: Style.font.icon
            visible: ejectSlot.ejecting
            Rectangle {
              width: 3; height: 3; radius: 1.5
              color: Color.accent
              anchors.horizontalCenter: parent.horizontalCenter
              anchors.top: parent.top
            }
            RotationAnimator on rotation {
              running: ejectSpinner.visible
              loops: Animation.Infinite
              from: 0; to: 360; duration: 800
            }
          }

          MouseArea {
            id: ejectMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            enabled: !ejectSlot.ejecting
            onClicked: root.mountEjectRequested(ejectSlot.mount)
          }
        }
      }
    }

    Item {
      width: 1
      height: Style.spacing.sm
    }

    PanelSeparator {
      foreground: Color.menu.text
      strength: 0.15
    }

    Item {
      width: 1
      height: Style.spacing.xs
    }

    // A diferencia de DEVICES/marcadores, esta cabecera y la fila de
    // "Connect to server..." se ven siempre, con mounts activos o
    // sin ellos -- si dependieran de root.networkMounts.length > 0
    // nadie podría descubrir la función la primera vez, cuando por
    // definición todavía no hay ninguna conexión de red activa.
    PanelSectionHeader {
      text: "NETWORK"
      foreground: Color.menu.text
      fontFamily: Style.font.family
      fontSize: Style.font.subtitle
    }

    Item {
      width: 1
      height: Style.spacing.xxs
    }

    Repeater {
      model: root.networkMounts

      CursorSurface {
        required property var modelData
        readonly property bool isCurrent: root.currentPath === modelData.path
        width: sidebar.width
        implicitHeight: Style.spacing.controlHeight
        foreground: Color.menu.text
        accent: Color.accent
        hasCursor: networkMountMouse.containsMouse
        current: isCurrent
        Accessible.role: Accessible.ListItem
        Accessible.name: "Network location, " + modelData.label
        Accessible.selected: isCurrent

        OpticalGlyph {
          id: networkMountIcon
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.sm
          width: Style.font.title
          height: Style.font.title
          text: root.iconForNetworkMount(parent.modelData)
          fontFamily: Style.font.family
          fontSize: Style.font.icon
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: networkMountIcon.right
          anchors.leftMargin: Style.spacing.xs
          text: parent.modelData.label
          font.pixelSize: Style.font.title
          font.family: Style.font.family
          font.weight: Font.Medium
          color: parent.isCurrent ? Color.menu.selectedText : Color.menu.text
          elide: Text.ElideRight
          width: sidebar.width - Style.spacing.sm * 2 - networkMountIcon.width - Style.spacing.xs
        }

        MouseArea {
          id: networkMountMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: function (mouse) {
            if (mouse.button === Qt.RightButton) {
              var pos = mapToItem(root.positionRelativeTo, mouse.x, mouse.y)
              root.openContextMenu(pos.x, pos.y, root.networkMountActionsFor(modelData))
              return
            }
            root.networkMountOpened(modelData)
          }
        }
      }
    }

    CursorSurface {
      width: sidebar.width
      implicitHeight: Style.spacing.controlHeight
      foreground: Color.menu.text
      accent: Color.accent
      hasCursor: connectServerMouse.containsMouse
      Accessible.role: Accessible.Button
      Accessible.name: "Connect to server"

      OpticalGlyph {
        id: connectServerIcon
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.sm
        width: Style.font.title
        height: Style.font.title
        text: "\u{F0490}"
        fontFamily: Style.font.family
        fontSize: Style.font.icon
        color: Color.menu.text
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: connectServerIcon.right
        anchors.leftMargin: Style.spacing.xs
        text: "Connect…"
        font.pixelSize: Style.font.title
        font.family: Style.font.family
        font.weight: Font.Medium
        color: Color.menu.text
        elide: Text.ElideRight
        width: sidebar.width - Style.spacing.sm * 2 - connectServerIcon.width - Style.spacing.xs
      }

      MouseArea {
        id: connectServerMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.connectRequested()
      }
    }
  }
}
