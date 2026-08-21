#!/usr/bin/env python3
"""
OmaFiles startup benchmark (V1.2 startup performance audit).

Launches build/omafiles-standalone repeatedly with OMAFILES_STARTUP_TRACE=1,
captures its stderr trace (see backend/StartupTrace.h / main.cpp), and
reports timing for the milestones that matter for perceived startup:

  - main() reached (process launch -> dynamic linker + libc/Qt static init
    done; measured by diffing the harness's OWN CLOCK_MONOTONIC read right
    before spawning against the process's self-reported T0)
  - QGuiApplication constructed
  - engine.load(Main.qml) returned  (QML tree built, all Component.onCompleted ran)
  - first frame swapped              (real pixels on screen -- "first visible window")
  - DirectoryModel::apply            (first listing became visible)

Each run is killed shortly after the window appears (SIGTERM, not caught by
Qt by default -- no onClosing side effects, no session.json write). Requires
a real Wayland/X11 session (uses the real platform plugin, not offscreen,
so the numbers reflect actual compositor latency).

Usage: python3 bench/startup_bench.py [N_RUNS] [--out results.json]
"""
import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BIN = ROOT / "build" / "omafiles-standalone"
KILL_AFTER = 1.5  # seconds of trace capture per run before terminating

MILESTONES = [
    "QGuiApplication constructed",
    "single-instance check done (this is the primary instance)",
    "QQmlApplicationEngine constructed",
    "resourceDir resolved + import paths added",
    "engine.load(Main.qml) starting",
    "engine.load(Main.qml) returned (QML tree built, all Component.onCompleted ran)",
    "first frame swapped (window actually visible on screen)",
    "entering app.exec()",
    "DirectoryModel::apply (a listing became visible)",
]


def run_once(idx):
    env = os.environ.copy()
    env["OMAFILES_STARTUP_TRACE"] = "1"
    t_launch = time.clock_gettime(time.CLOCK_MONOTONIC)
    proc = subprocess.Popen(
        [str(BIN)], env=env, cwd=str(ROOT),
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    lines = []
    sel = selectors.DefaultSelector()
    sel.register(proc.stderr, selectors.EVENT_READ)
    deadline = time.monotonic() + KILL_AFTER
    while time.monotonic() < deadline:
        for key, _ in sel.select(timeout=0.05):
            line = key.fileobj.readline()
            if line:
                lines.append(line.rstrip("\n"))
    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
    try:
        rest = proc.stderr.read()
        if rest:
            lines.extend(rest.splitlines())
    except Exception:
        pass

    t0_ns = None
    marks = {}
    for line in lines:
        if line.startswith("[startup-t0] "):
            t0_ns = int(line.split(" ", 1)[1].strip())
        elif line.startswith("[startup] "):
            rest = line[len("[startup] "):]
            ms_str, label = rest.split("ms", 1)
            label = label.strip()
            ms = float(ms_str.strip())
            if label not in marks:  # first occurrence only
                marks[label] = ms

    result = {"marks": marks}
    if t0_ns is not None:
        launch_to_main_ms = (t0_ns - int(t_launch * 1e9)) / 1e6
        result["launch_to_main_ms"] = launch_to_main_ms
    return result


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    k = (len(s) - 1) * p
    f, c = int(k), min(int(k) + 1, len(s) - 1)
    if f == c:
        return s[f]
    return s[f] + (s[c] - s[f]) * (k - f)


def summarize(label, values):
    values = [v for v in values if v is not None]
    if not values:
        print(f"  {label:70s}  (no data)")
        return
    print(f"  {label:70s}  min={min(values):8.2f}  max={max(values):8.2f}  "
          f"avg={sum(values)/len(values):8.2f}  median={pct(values,0.5):8.2f}  n={len(values)}")


def main():
    n_runs = int(sys.argv[1]) if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else 12
    out_path = None
    if "--out" in sys.argv:
        out_path = sys.argv[sys.argv.index("--out") + 1]

    if not BIN.exists():
        print(f"binary not found: {BIN}", file=sys.stderr)
        sys.exit(1)

    runs = []
    for i in range(n_runs):
        print(f"run {i+1}/{n_runs}...", file=sys.stderr)
        runs.append(run_once(i))
        time.sleep(0.4)  # let the socket/window fully tear down before the next launch

    print(f"\n=== {n_runs} runs ===\n")
    summarize("process launch -> main() reached (loader overhead)",
              [r.get("launch_to_main_ms") for r in runs])
    print()
    for m in MILESTONES:
        summarize(m, [r["marks"].get(m) for r in runs])

    # first-run vs rest (cold vs warm proxy)
    if len(runs) > 1:
        print("\n=== first run vs. rest (cold-ish vs warm proxy) ===\n")
        first = runs[0]
        rest = runs[1:]
        for m in ["first frame swapped (window actually visible on screen)",
                  "DirectoryModel::apply (a listing became visible)"]:
            f = first["marks"].get(m)
            r = [x["marks"].get(m) for x in rest]
            r = [x for x in r if x is not None]
            print(f"  {m}")
            print(f"    first run: {f}")
            if r:
                print(f"    rest avg:  {sum(r)/len(r):.2f}  min={min(r):.2f}  max={max(r):.2f}")

    if out_path:
        with open(out_path, "w") as f:
            json.dump(runs, f, indent=2)
        print(f"\nraw data written to {out_path}")


if __name__ == "__main__":
    main()
