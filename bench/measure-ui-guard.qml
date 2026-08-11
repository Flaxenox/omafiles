import QtQuick
import Omafiles.Backend

// Compara el coste EN HILO DE UI de la guarda "¿cambió la carpeta?":
//   ANTES (Fase 10.A): Utils.entriesEqual -> itera N entradas, materializa todo.
//   AHORA (Fase 27):  comparar DirectoryModel.signature (string) -> O(1).
Item {
  DirectoryModel { id: m; onListed: harness.step() }
  QtObject {
    id: harness
    property var dirs: [
      "/home/josema/.cache/omafiles-perfbench/1k",
      "/home/josema/.cache/omafiles-perfbench/10k",
      "/home/josema/.cache/omafiles-perfbench/50k",
      "/home/josema/.cache/omafiles-perfbench/100k"
    ]
    property int i: -1
    property string last: ""
    function next() { i++; if (i >= dirs.length) { Qt.exit(0); return } last = ""; m.list(dirs[i], false) }
    function step() {
      // NUEVO camino: leer la firma y comparar (esto es TODO lo que corre en la
      // guarda cuando la carpeta no cambió). Medimos 1000 repeticiones para que
      // el reloj de ms lo capte.
      var reps = 1000
      var t0 = Date.now()
      var changed = 0
      for (var r = 0; r < reps; r++) {
        var sig = m.signature
        if (sig !== last) { changed++; }
      }
      var t1 = Date.now()
      // materialización perezosa (solo lectura, sin iterar): lo que hace ListView
      var e = m.entries
      var t2 = Date.now()
      last = m.signature
      console.log("rows=" + e.length
        + "  signatureGuard(x" + reps + ")=" + (t1 - t0) + "ms"
        + "  -> " + ((t1 - t0) / reps).toFixed(4) + "ms/vez"
        + "  lazyRead=" + (t2 - t1) + "ms")
      next()
    }
  }
  Component.onCompleted: harness.next()
}
