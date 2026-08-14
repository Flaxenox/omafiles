// Micro-benchmark of DirectoryModel listing path.
// Uses ONLY the public async API (list + listed + entries), which is the real
// path experienced by the UI. Measures: (a) scan+dispatch+apply up to the listed() signal,
// (b) QVariantList construction in entries(). Reports the median of N runs
// with warm cache. Not installed or linked into the app; compiled manually
// against backend/DirectoryModel.cpp (see bench/README.md).
#include "DirectoryModel.h"
#include <QCoreApplication>
#include <QDir>
#include <QElapsedTimer>
#include <QEventLoop>
#include <QString>
#include <QVariantList>
#include <algorithm>
#include <cstdio>
#include <vector>

// Portable dataset location: honor an explicit override, else the XDG cache dir
// (fallback ~/.cache). No hardcoded home or username, so this runs on any clone.
static QString resolveBase() {
  const QByteArray override = qgetenv("OMAFILES_PERFBENCH_DIR");
  if (!override.isEmpty())
    return QString::fromLocal8Bit(override);
  const QByteArray xdg = qgetenv("XDG_CACHE_HOME");
  const QString cacheHome =
      xdg.isEmpty() ? QDir::homePath() + "/.cache" : QString::fromLocal8Bit(xdg);
  return cacheHome + "/omafiles-perfbench";
}

static double medianOf(std::vector<double> v) {
  std::sort(v.begin(), v.end());
  return v[v.size() / 2];
}

// Measures one directory: outputs {median_listing_ms, median_entries_ms, rows}.
static void benchDir(const QString &path, int iters) {
  std::vector<double> listMs, convMs;
  int rows = 0;
  for (int k = 0; k < iters; ++k) {
    DirectoryModel m;
    QEventLoop loop;
    QElapsedTimer t;
    double listedAt = 0, convAt = 0;
    int localRows = 0;
    QObject::connect(&m, &DirectoryModel::listed, &loop, [&]() {
      listedAt = t.nsecsElapsed() / 1e6;
      // entries(): QVariantList construction (conversion cost).
      QElapsedTimer tc;
      tc.start();
      QVariantList e = m.entries();
      convAt = tc.nsecsElapsed() / 1e6;
      localRows = e.size();
      loop.quit();
    });
    t.start();
    m.list(path, /*showHidden=*/false);
    loop.exec();
    listMs.push_back(listedAt);
    convMs.push_back(convAt);
    rows = localRows;
  }
  std::printf("%-42s rows=%-7d  listing=%7.2f ms   entries()=%7.2f ms\n",
              qPrintable(path), rows, medianOf(listMs), medianOf(convMs));
}

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  const QString base = resolveBase();
  const char *sizes[] = {"1k", "10k", "50k", "100k"};
  const int iters = 9;
  // Warm-up: one pass per dir to warm up the inode cache.
  for (const char *s : sizes) {
    DirectoryModel m;
    QEventLoop loop;
    QObject::connect(&m, &DirectoryModel::listed, &loop, &QEventLoop::quit);
    m.list(QString("%1/%2").arg(base, s));
    loop.exec();
  }
  std::printf("=== DirectoryModel listing (median of %d runs, warm cache) ===\n", iters);
  for (const char *s : sizes)
    benchDir(QString("%1/%2").arg(base, s), iters);
  return 0;
}
