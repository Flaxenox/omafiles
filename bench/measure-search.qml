import QtQuick
import Omafiles.Backend
Item {
  SearchWorker { id: sw; onResults: function(list, truncated) {
    var dt = Date.now() - harness.t0
    console.log("query='" + harness.q + "' resultados=" + list.length + " truncado=" + truncated + " tiempo=" + dt + "ms")
    harness.next()
  }}
  QtObject { id: harness
    property var qs: ["Report", "img", "999", "Folder_0000"]
    property int i: -1
    property real t0: 0
    property string q: ""
    // Portable dataset location: explicit override, else the XDG cache dir
    // (fallback $HOME/.cache). No hardcoded home or username; runs on any clone.
    readonly property string cacheHome: Env.get("XDG_CACHE_HOME") !== ""
      ? Env.get("XDG_CACHE_HOME") : Env.get("HOME") + "/.cache"
    readonly property string base: Env.get("OMAFILES_PERFBENCH_DIR") !== ""
      ? Env.get("OMAFILES_PERFBENCH_DIR") : cacheHome + "/omafiles-perfbench"
    function next(){ i++; if(i>=qs.length){Qt.exit(0);return} q=qs[i]; t0=Date.now(); sw.search(base + "/100k", q, false) }
  }
  Component.onCompleted: harness.next()
}
