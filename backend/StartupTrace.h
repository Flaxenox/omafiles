#pragma once
#include <cstdio>
#include <cstdlib>
#include <ctime>

// Opt-in startup timing trace (V1.2 startup performance audit,
// docs/audits/V1_2_STARTUP_PERFORMANCE_REPORT.md). Disabled by default: a
// single cached getenv() per call, effectively free. Enabled by exporting
// OMAFILES_STARTUP_TRACE=1 before launching omafiles-standalone -- every
// startupTrace() call then prints "[startup] <elapsed_ms>ms  <label>" to
// stderr, timestamped relative to OMAFILES_T0_NS (set by main() as the very
// first thing it does, before QGuiApplication is even constructed -- see
// main.cpp). An env var, not a shared static, is what lets this work across
// the omafiles-standalone / omafiles-backend .so boundary without any
// cross-DSO global state (a `static`/inline variable here would NOT be the
// same instance in both binaries).
inline bool startupTraceEnabled() {
  static const bool enabled = []() {
    const char *v = std::getenv("OMAFILES_STARTUP_TRACE");
    return v && v[0] == '1';
  }();
  return enabled;
}

inline void startupTrace(const char *label) {
  if (!startupTraceEnabled()) return;
  const char *t0s = std::getenv("OMAFILES_T0_NS");
  if (!t0s) return;
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  const long long nowNs = static_cast<long long>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
  const long long t0Ns = std::atoll(t0s);
  // Integer micros formatted by hand (not %f) -- %f is locale-sensitive
  // (e.g. es_ES prints "12,72" not "12.72"), which would silently break any
  // parser expecting a fixed '.' decimal point.
  const long long us = (nowNs - t0Ns) / 1000;
  std::fprintf(stderr, "[startup] %lld.%02lld ms  %s\n", us / 1000, (us % 1000) / 10, label);
  std::fflush(stderr);
}
