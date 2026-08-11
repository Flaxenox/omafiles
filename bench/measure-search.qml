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
    function next(){ i++; if(i>=qs.length){Qt.exit(0);return} q=qs[i]; t0=Date.now(); sw.search("/home/josema/.cache/omafiles-perfbench/100k", q, false) }
  }
  Component.onCompleted: harness.next()
}
