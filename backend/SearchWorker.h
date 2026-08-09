#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <atomic>
#include <memory>
#include <mutex>
#include <qqmlregistration.h>

// Búsqueda recursiva nativa (Fase 16, josema). Sustituto de
// search-recursive.sh: recorre `root` en profundidad, filtra por subcadena
// (insensible a mayúsculas) sobre el NOMBRE de fichero/carpeta, salta los
// ocultos salvo showHidden, y devuelve hasta 201 entradas con la misma forma
// que DirectoryModel ({type,name,size,mtime,link}) -- `name` es la ruta
// RELATIVA a root, para que el resto del código (unir con currentPath,
// renombrar, borrar, abrir...) funcione igual que con el script.
//
// Async (QThreadPool) y cancelable: cada search() abre una "generación"; una
// nueva búsqueda o cancel() invalida la anterior (ni recorre de más ni emite
// resultados obsoletos). Se piden 201 a propósito -- results() marca
// truncated=true si hubo más de 200 y recorta a 200, igual que el contrato
// del script (el lado QML avisa de lista incompleta).
//
// Instanciable (QML_ELEMENT, como DirectoryModel/ProcessRunner): SearchOps
// tiene su propia instancia. Sin dependencia de Quickshell.
class SearchWorker : public QObject {
  Q_OBJECT
  QML_ELEMENT

public:
  explicit SearchWorker(QObject *parent = nullptr);
  ~SearchWorker() override;

  // Lanza una búsqueda recursiva bajo `root`. Vuelve al instante; el
  // resultado llega por results() en el hilo de UI. Query vacía no busca.
  Q_INVOKABLE void search(const QString &root, const QString &query,
                          bool showHidden);
  // Cancela la búsqueda en curso (invalida su generación): no se emite
  // resultado. Idempotente.
  Q_INVOKABLE void cancel();

signals:
  // Resultados de la última búsqueda vigente. `entries` son objetos
  // {type,name,size,mtime,link}; `truncated` = había más de 200 coincidencias.
  void results(const QVariantList &entries, bool truncated);

private:
  // Generación de la búsqueda vigente. search() la incrementa y la captura;
  // el worker descarta (no emite) si dejó de ser la vigente -- cubre tanto
  // cancel() como una búsqueda que supera a otra.
  std::atomic<quint64> m_gen{0};

  // Guardia de vida contra el `this` colgante (mismo patrón que
  // DirectoryModel/FileOperations): un worker que termine tras destruirse el
  // objeto comprobaría `alive` bajo el mutex antes de entregar.
  struct Life {
    std::mutex mtx;
    bool alive = true;
  };
  std::shared_ptr<Life> m_life = std::make_shared<Life>();
};
