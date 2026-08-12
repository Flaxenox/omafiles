import QtQuick
import Omafiles.Backend as Backend
import "../../../services"
import "../../../state"
import "../../../Utils.js" as Utils

// Domain checks extracted from integrations/standalone/SelfCheck.qml (_register).
// Structural refactor only — behavior unchanged.
QtObject {
  function register(sc) {
        sc.add("JsonStore write/read round-trip", function (done) {
          var payload = { a: 1, b: "x", nested: { k: [1, 2, 3] } }
          function onSaved(path, ok) {
            JsonStore.saved.disconnect(onSaved)
            if (!ok) { done(false, "write failed"); return }
            function onLoaded(p, data, lok) {
              JsonStore.loaded.disconnect(onLoaded)
              if (!lok) { done(false, "read failed"); return }
              var good = data && data.a === 1 && data.b === "x"
                && data.nested && data.nested.k.length === 3
              done(good, good ? "" : "data doesn't match: " + JSON.stringify(data))
            }
            JsonStore.loaded.connect(onLoaded)
            JsonStore.read(sc.jsonFile)
          }
          JsonStore.saved.connect(onSaved)
          JsonStore.write(sc.jsonFile, payload)
        })
  }
}
