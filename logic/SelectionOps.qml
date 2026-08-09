import QtQuick
import "../state"

// Selección de filas (individual, rango, lazo de arrastre) -- vigésimo
// quinto componente extraído de Omafiles.qml.
Item {
  property Item root: null
  property Item previewLoader: null

  function isSelected(index) {
    return SelectionState.selectedIndices.indexOf(index) >= 0
  }

  function selectOnly(index) {
    SelectionState.selectedIndex = index
    SelectionState.anchorIndex = index
    SelectionState.selectedIndices = index >= 0 ? [index] : []
    if (PreviewState.previewOpen) {
      if (index >= 0 && index < NavState.visibleEntries.length && NavState.visibleEntries[index].type !== "dir") {
        previewLoader.loadPreview(NavState.visibleEntries[index])
      } else {
        PreviewState.previewOpen = false
      }
    }
  }

  function toggleSelect(index) {
    var next = SelectionState.selectedIndices.slice()
    var pos = next.indexOf(index)
    if (pos >= 0) next.splice(pos, 1)
    else next.push(index)
    SelectionState.selectedIndices = next
    SelectionState.selectedIndex = index
    SelectionState.anchorIndex = index
  }

  function selectNone() {
    selectOnly(-1)
  }

  function invertSelection() {
    var current = SelectionState.selectedIndices
    var next = []
    for (var i = 0; i < NavState.visibleEntries.length; i++) {
      if (current.indexOf(i) < 0) next.push(i)
    }
    SelectionState.selectedIndices = next
    SelectionState.selectedIndex = next.length > 0 ? next[next.length - 1] : -1
    SelectionState.anchorIndex = SelectionState.selectedIndex
  }

  function selectRange(index) {
    var start = SelectionState.anchorIndex >= 0 ? SelectionState.anchorIndex : index
    var from = Math.min(start, index)
    var to = Math.max(start, index)
    var next = []
    for (var i = from; i <= to; i++) next.push(i)
    SelectionState.selectedIndices = next
    SelectionState.selectedIndex = index
  }

  // Arranca/mueve/termina el lazo -- compartido por todos los catchers que
  // pueden recibir el press inicial (huecos de arriba/abajo/izquierda,
  // gutters de cada fila) para no duplicar la lógica. `contentY` es la
  // posición dentro de list.contentItem (mapToItem ya la da corregida por
  // scroll); `viewportY` es la posición dentro de `list` sin corregir,
  // para detectar si el cursor está pegado a un borde y hace falta
  // auto-scroll.
  function startMarquee(x, contentY, viewportY, ctrlHeld) {
    SelectionState.marqueeAdditive = ctrlHeld
    SelectionState.marqueeBaseSelection = ctrlHeld ? SelectionState.selectedIndices.slice() : []
    if (!ctrlHeld) selectOnly(-1)
    SelectionState.marqueeStartX = x
    SelectionState.marqueeCurrentX = x
    SelectionState.marqueeStartY = contentY
    SelectionState.marqueeCurrentY = contentY
    SelectionState.marqueeViewportY = viewportY
    SelectionState.marqueeActive = true
  }

  function moveMarquee(x, contentY, viewportY) {
    if (!SelectionState.marqueeActive) return
    SelectionState.marqueeCurrentX = x
    SelectionState.marqueeCurrentY = contentY
    SelectionState.marqueeViewportY = viewportY
    updateMarqueeSelection(SelectionState.marqueeAdditive, SelectionState.marqueeBaseSelection)
  }

  function endMarquee() {
    SelectionState.marqueeActive = false
  }

  // Recalcula la selección a partir del rectángulo del lazo (marqueeStartY/
  // marqueeCurrentY, en coordenadas de contenido). Filas de altura uniforme
  // (nombres/metadatos no hacen wrap, siempre una línea) -- basta con
  // dividir por la altura media en vez de inspeccionar los delegados reales
  // de la ListView, más simple y ajeno a la virtualización.
  function updateMarqueeSelection(additive, base) {
    var total = NavState.visibleEntries.length
    if (total === 0 || root.measuredRowHeight <= 0) return
    var rowH = root.measuredRowHeight
    var contentEnd = total * rowH
    var top = Math.min(SelectionState.marqueeStartY, SelectionState.marqueeCurrentY)
    var bottom = Math.max(SelectionState.marqueeStartY, SelectionState.marqueeCurrentY)
    var picked = []
    if (bottom > 0 && top < contentEnd) {
      var firstIdx = Math.max(0, Math.floor(top / rowH))
      var lastIdx = Math.min(total - 1, Math.ceil(bottom / rowH) - 1)
      for (var i = firstIdx; i <= lastIdx; i++) picked.push(i)
    }
    var next = additive
      ? base.concat(picked.filter(function (i) { return base.indexOf(i) < 0 }))
      : picked
    SelectionState.selectedIndices = next
    SelectionState.selectedIndex = next.length > 0 ? next[next.length - 1] : -1
  }

  function selectedEntries() {
    return SelectionState.selectedIndices
      .filter(function (i) { return i >= 0 && i < NavState.visibleEntries.length })
      .map(function (i) { return NavState.visibleEntries[i] })
  }
}
