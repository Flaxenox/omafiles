import QtQuick
import "../state"

// Row selection (single, range, drag marquee) -- twenty-fifth
// component extracted from Omafiles.qml.
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

  // Starts/moves/ends the marquee -- shared by all the catchers that
  // can receive the initial press (top/bottom/left empty areas,
  // gutters of each row) so as not to duplicate the logic. `contentY` is the
  // position inside list.contentItem (mapToItem already gives it corrected for
  // scroll); `viewportY` is the position inside `list` uncorrected,
  // to detect if the cursor is stuck to an edge and
  // auto-scroll is needed.
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

  // Recomputes the selection from the marquee rectangle (marqueeStartY/
  // marqueeCurrentY, in content coordinates). Rows of uniform height
  // (names/metadata do not wrap, always one line) -- it is enough to
  // divide by the average height instead of inspecting the ListView's real
  // delegates, simpler and independent of the virtualization.
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
