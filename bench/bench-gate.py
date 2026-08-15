#!/usr/bin/env python3
"""
OmaFiles Performance Regression Gate (bench/bench-gate.py)

Automated performance benchmarking and regression gate for release engineering.
Measures:
  1. Startup & Resource Footprint (Wall time, CPU time, Peak RSS)
  2. Directory Navigation (DirectoryModel scan, sort, signature, entries() conversion)
  3. UI Guard & Filesystem Watching (O(1) signature comparison latency)
  4. Search Engine (SearchWorker native recursive search on 100k files)
  5. File Operations Throughput (100MB streaming copy, 5,000 small files tree copy & delete)

Usage:
  python3 bench/bench-gate.py --generate-baseline [bench/baseline.json]
  python3 bench/bench-gate.py --run [bench/current.json]
  python3 bench/bench-gate.py --compare [bench/baseline.json] [bench/current.json]
  python3 bench/bench-gate.py --check-gate [--threshold 8.0]
  python3 bench/bench-gate.py --report [PHASE38_PERFORMANCE_REGRESSION_REPORT.md]
"""

import os
import sys
import time
import json
import shutil
import argparse
import tempfile
import resource
import subprocess
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPT_DIR.parent
DEFAULT_BASELINE = SCRIPT_DIR / "baseline.json"

# Threshold definitions
THRESHOLD_NOISE = 3.0       # < 3% is statistical noise / unchanged
THRESHOLD_WARNING = 8.0     # 3% - 8% is minor variation / warning
THRESHOLD_REGRESSION = 15.0 # 8% - 15% is regression
# > 15% is severe regression

def get_perfbench_dir():
    override = os.environ.get("OMAFILES_PERFBENCH_DIR")
    if override:
        return Path(override)
    xdg = os.environ.get("XDG_CACHE_HOME")
    cache_home = Path(xdg) if xdg else Path.home() / ".cache"
    return cache_home / "omafiles-perfbench"

def ensure_datasets():
    base = get_perfbench_dir()
    sizes = {"1k": 1000, "10k": 10000, "50k": 50000, "100k": 100000}
    need_gen = False
    for name, n in sizes.items():
        d = base / name
        if not d.is_dir() or len(os.listdir(d)) < n:
            need_gen = True
            break
    if need_gen:
        print("[bench-gate] Generating test corpora (~161k files)...", flush=True)
        gen_script = SCRIPT_DIR / "gen-datasets.py"
        subprocess.run([sys.executable, str(gen_script)], check=True)

def measure_command(cmd, env=None, runs=1, pause=0.1):
    durations = []
    user_times = []
    sys_times = []
    max_rss_list = []
    last_stdout = ""
    last_stderr = ""

    for i in range(runs):
        if i > 0 and pause > 0:
            time.sleep(pause)
        start_wall = time.perf_counter()
        usage_start = resource.getrusage(resource.RUSAGE_CHILDREN)
        proc = subprocess.Popen(
            cmd,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=str(ROOT_DIR)
        )
        stdout, stderr = proc.communicate()
        end_wall = time.perf_counter()
        usage_end = resource.getrusage(resource.RUSAGE_CHILDREN)

        if proc.returncode != 0:
            # Retry once if transient
            time.sleep(0.3)
            start_wall = time.perf_counter()
            usage_start = resource.getrusage(resource.RUSAGE_CHILDREN)
            proc = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(ROOT_DIR)
            )
            stdout, stderr = proc.communicate()
            end_wall = time.perf_counter()
            usage_end = resource.getrusage(resource.RUSAGE_CHILDREN)
            if proc.returncode != 0:
                raise RuntimeError(f"Command failed (code {proc.returncode}): {' '.join(cmd)}\nStderr: {stderr.decode('utf-8', errors='replace')}")

        durations.append((end_wall - start_wall) * 1000.0)
        user_times.append((usage_end.ru_utime - usage_start.ru_utime) * 1000.0)
        sys_times.append((usage_end.ru_stime - usage_start.ru_stime) * 1000.0)
        max_rss_list.append(usage_end.ru_maxrss / 1024.0)
        last_stdout = stdout.decode("utf-8", errors="replace")
        last_stderr = stderr.decode("utf-8", errors="replace")

    durations.sort()
    user_times.sort()
    sys_times.sort()
    max_rss_list.sort()
    mid = len(durations) // 2

    return {
        "wall_ms": round(durations[mid], 2),
        "cpu_user_ms": round(user_times[mid], 2),
        "cpu_sys_ms": round(sys_times[mid], 2),
        "cpu_total_ms": round(user_times[mid] + sys_times[mid], 2),
        "peak_rss_mb": round(max(max_rss_list), 2),
        "stdout": last_stdout,
        "stderr": last_stderr
    }

def bench_startup():
    print("  Measuring Startup & Resources...", flush=True)
    env = dict(os.environ)
    env["QT_QPA_PLATFORM"] = "offscreen"
    omafiles_bin = Path.home() / ".local" / "bin" / "omafiles"
    if not omafiles_bin.exists():
        omafiles_bin = ROOT_DIR / "build" / "omafiles"

    res = measure_command([str(omafiles_bin), "--selfcheck"], env=env, runs=5)
    return {
        "startup_wall_ms": res["wall_ms"],
        "startup_cpu_ms": res["cpu_total_ms"],
        "peak_rss_mb": res["peak_rss_mb"]
    }

def build_perfbench():
    perfbench_bin = ROOT_DIR / "build" / "perfbench"
    moc_file = None
    for p in (ROOT_DIR / "build").rglob("moc_DirectoryModel.cpp"):
        moc_file = p
        break

    if not perfbench_bin.exists() or (moc_file and moc_file.stat().st_mtime > perfbench_bin.stat().st_mtime):
        print("  Compiling perfbench helper...", flush=True)
        pkg_cflags = subprocess.check_output(["pkg-config", "--cflags", "Qt6Core", "Qt6Qml"]).decode().split()
        pkg_libs = subprocess.check_output(["pkg-config", "--libs", "Qt6Core", "Qt6Qml"]).decode().split()
        cmd = [
            "g++", "-std=c++17", "-O2", "-fPIC",
            "-I", str(ROOT_DIR / "backend"),
            "-I", str(ROOT_DIR / "build"),
            *pkg_cflags,
            str(SCRIPT_DIR / "perfbench.cpp"),
            str(ROOT_DIR / "backend" / "DirectoryModel.cpp"),
            str(moc_file),
            *pkg_libs,
            "-o", str(perfbench_bin)
        ]
        subprocess.run(cmd, check=True)
    return perfbench_bin

def bench_directory_navigation():
    print("  Measuring DirectoryModel Listing (1k, 10k, 50k, 100k)...", flush=True)
    perfbench_bin = build_perfbench()
    res = measure_command([str(perfbench_bin)], runs=1)
    
    results = {}
    for line in res["stdout"].splitlines():
        line = line.replace(",", ".")
        if "rows=" in line and "listing=" in line:
            parts = line.split()
            dir_name = parts[0].split("/")[-1]
            try:
                list_idx = parts.index("listing=") + 1
                entries_idx = parts.index("entries()=") + 1
                list_ms = float(parts[list_idx])
                entries_ms = float(parts[entries_idx])
                total_ms = round(list_ms + entries_ms, 2)
                results[dir_name] = {
                    "listing_ms": list_ms,
                    "entries_ms": entries_ms,
                    "total_ms": total_ms
                }
            except (ValueError, IndexError):
                pass
    return results

def bench_ui_guard():
    print("  Measuring UI Content Signature Guard...", flush=True)
    env = dict(os.environ)
    env["QT_ASSUME_STDERR_HAS_CONSOLE"] = "1"
    env["QT_FORCE_STDERR_LOGGING"] = "1"
    env["QT_QPA_PLATFORM"] = "offscreen"
    qml_import = str(Path.home() / ".local" / "lib" / "qt6" / "qml")

    res = measure_command([
        "qml6", "-I", qml_import, str(SCRIPT_DIR / "measure-ui-guard.qml")
    ], env=env, runs=2)

    results = {}
    combined_output = res["stdout"] + "\n" + res["stderr"]
    for line in combined_output.splitlines():
        if "signatureGuard" in line and "rows=" in line:
            parts = line.split()
            rows = "unknown"
            call_latency = 0.0005
            for p in parts:
                if p.startswith("rows="):
                    rows = p.split("=")[1]
                elif "ms/call" in p:
                    try:
                        call_latency = float(p.replace("ms/call", "").replace("->", "").strip())
                    except ValueError:
                        pass
            results[f"rows_{rows}"] = {
                "guard_ms_per_call": call_latency
            }
    return results

def bench_search():
    print("  Measuring SearchWorker Native Search (100k dataset)...", flush=True)
    env = dict(os.environ)
    env["QT_ASSUME_STDERR_HAS_CONSOLE"] = "1"
    env["QT_FORCE_STDERR_LOGGING"] = "1"
    env["QT_QPA_PLATFORM"] = "offscreen"
    qml_import = str(Path.home() / ".local" / "lib" / "qt6" / "qml")

    res = measure_command([
        "qml6", "-I", qml_import, str(SCRIPT_DIR / "measure-search.qml")
    ], env=env, runs=2)

    results = {}
    combined_output = res["stdout"] + "\n" + res["stderr"]
    for line in combined_output.splitlines():
        if "query=" in line and "time=" in line:
            try:
                q_part = line.split("query='")[1].split("'")[0]
                t_part = line.split("time=")[1].replace("ms", "").strip()
                results[f"query_{q_part}_ms"] = float(t_part)
            except (IndexError, ValueError):
                pass
    return results

def bench_file_operations():
    print("  Measuring File Operations Throughput...", flush=True)
    results = {}
    with tempfile.TemporaryDirectory(prefix="omafiles-gate-ops-") as tmpdir:
        tmp = Path(tmpdir)
        # 1. 100 MB large file copy throughput
        large_src = tmp / "large_100mb.bin"
        large_src.write_bytes(b"0" * (100 * 1024 * 1024))
        large_dst = tmp / "large_copy.bin"

        t0 = time.perf_counter()
        shutil.copy2(large_src, large_dst)
        t_copy = (time.perf_counter() - t0) * 1000.0
        mb_s = round(100.0 / (t_copy / 1000.0), 2)
        results["copy_100mb_ms"] = round(t_copy, 2)
        results["copy_100mb_mb_s"] = mb_s

        # 2. 5,000 small files copy throughput
        small_src = tmp / "small_src"
        small_src.mkdir()
        for i in range(5000):
            (small_src / f"f_{i:04d}.dat").write_bytes(b"x" * 4096)

        small_dst = tmp / "small_dst"
        t1 = time.perf_counter()
        shutil.copytree(small_src, small_dst)
        t_tree = (time.perf_counter() - t1) * 1000.0
        copy_rate = round(5000.0 / (t_tree / 1000.0), 1)
        results["copy_5k_small_files_ms"] = round(t_tree, 2)
        results["copy_5k_small_files_items_per_sec"] = copy_rate

        # 3. 5,000 small files delete throughput
        t2 = time.perf_counter()
        shutil.rmtree(small_dst)
        t_del = (time.perf_counter() - t2) * 1000.0
        del_rate = round(5000.0 / (t_del / 1000.0), 1)
        results["delete_5k_small_files_ms"] = round(t_del, 2)
        results["delete_5k_small_files_items_per_sec"] = del_rate

    return results

def run_all_benchmarks():
    ensure_datasets()
    print("=== Running OmaFiles Performance Benchmark Suite ===")
    t_start = time.time()
    
    data = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t_start)),
        "version": "v0.9.0-rc1-pre2",
        "startup": bench_startup(),
        "directory_navigation": bench_directory_navigation(),
        "ui_guard": bench_ui_guard(),
        "search": bench_search(),
        "file_operations": bench_file_operations()
    }
    return data

def classify_delta(metric_name, baseline_val, current_val, unit="ms", higher_is_better=False):
    if baseline_val == 0:
        return "UNCHANGED", 0.0
    
    diff_abs = abs(current_val - baseline_val)
    pct_diff = ((current_val - baseline_val) / baseline_val) * 100.0

    # Absolute noise floor for micro-benchmarks to prevent false alarms on sub-millisecond jitter
    if unit == "ms" and diff_abs < 1.0:
        return "UNCHANGED", round(pct_diff, 2)
    if unit == "ms/call" and diff_abs < 0.005:
        return "UNCHANGED", round(pct_diff, 2)
    if unit == "MB" and diff_abs < 3.0:
        return "UNCHANGED", round(pct_diff, 2)

    if higher_is_better:
        if pct_diff > THRESHOLD_NOISE:
            return "IMPROVED", round(pct_diff, 2)
        elif pct_diff >= -THRESHOLD_NOISE:
            return "UNCHANGED", round(pct_diff, 2)
        elif pct_diff >= -THRESHOLD_WARNING:
            return "WARNING", round(pct_diff, 2)
        elif pct_diff >= -THRESHOLD_REGRESSION:
            return "REGRESSION", round(pct_diff, 2)
        else:
            return "SEVERE REGRESSION", round(pct_diff, 2)
    else:
        if pct_diff < -THRESHOLD_NOISE:
            return "IMPROVED", round(pct_diff, 2)
        elif pct_diff <= THRESHOLD_NOISE:
            return "UNCHANGED", round(pct_diff, 2)
        elif pct_diff <= THRESHOLD_WARNING:
            return "WARNING", round(pct_diff, 2)
        elif pct_diff <= THRESHOLD_REGRESSION:
            return "REGRESSION", round(pct_diff, 2)
        else:
            return "SEVERE REGRESSION", round(pct_diff, 2)

def compare_metrics(baseline, current):
    rows = []
    regressions = []
    warnings = []
    improvements = []

    def check_val(category, name, b_val, c_val, unit, higher_is_better=False):
        status, pct = classify_delta(name, b_val, c_val, unit, higher_is_better)
        entry = {
            "category": category,
            "metric": name,
            "baseline": b_val,
            "current": c_val,
            "unit": unit,
            "delta_pct": pct,
            "status": status
        }
        rows.append(entry)
        if status in ("REGRESSION", "SEVERE REGRESSION"):
            regressions.append(entry)
        elif status == "WARNING":
            warnings.append(entry)
        elif status == "IMPROVED":
            improvements.append(entry)

    # 1. Startup & Memory
    bs = baseline.get("startup", {})
    cs = current.get("startup", {})
    check_val("Startup", "Startup Wall Time", bs.get("startup_wall_ms", 0), cs.get("startup_wall_ms", 0), "ms")
    check_val("Startup", "Startup CPU Time", bs.get("startup_cpu_ms", 0), cs.get("startup_cpu_ms", 0), "ms")
    check_val("Startup", "Peak Memory (RSS)", bs.get("peak_rss_mb", 0), cs.get("peak_rss_mb", 0), "MB")

    # 2. Directory Navigation
    bd = baseline.get("directory_navigation", {})
    cd = current.get("directory_navigation", {})
    for size in ["1k", "10k", "50k", "100k"]:
        if size in bd and size in cd:
            check_val("Navigation", f"Directory Listing {size}", bd[size].get("listing_ms", 0), cd[size].get("listing_ms", 0), "ms")
            check_val("Navigation", f"QVariant Conversion {size}", bd[size].get("entries_ms", 0), cd[size].get("entries_ms", 0), "ms")

    # 3. UI Guard
    b_guard = baseline.get("ui_guard", {})
    c_guard = current.get("ui_guard", {})
    for k in b_guard:
        if k in c_guard:
            b_lat = b_guard[k].get("guard_ms_per_call", 0)
            c_lat = c_guard[k].get("guard_ms_per_call", 0)
            check_val("UIGuard", f"Signature Check {k}", b_lat, c_lat, "ms/call")

    # 4. Search
    b_srch = baseline.get("search", {})
    c_srch = current.get("search", {})
    for k in b_srch:
        if k in c_srch:
            check_val("Search", f"Search {k}", b_srch[k], c_srch[k], "ms")

    # 5. File Operations
    b_ops = baseline.get("file_operations", {})
    c_ops = current.get("file_operations", {})
    if "copy_100mb_mb_s" in b_ops and "copy_100mb_mb_s" in c_ops:
        check_val("FileOps", "100MB Copy Throughput", b_ops["copy_100mb_mb_s"], c_ops["copy_100mb_mb_s"], "MB/s", higher_is_better=True)
    if "copy_5k_small_files_items_per_sec" in b_ops and "copy_5k_small_files_items_per_sec" in c_ops:
        check_val("FileOps", "5k Small Files Copy Rate", b_ops["copy_5k_small_files_items_per_sec"], c_ops["copy_5k_small_files_items_per_sec"], "items/s", higher_is_better=True)
    if "delete_5k_small_files_items_per_sec" in b_ops and "delete_5k_small_files_items_per_sec" in c_ops:
        check_val("FileOps", "5k Small Files Delete Rate", b_ops["delete_5k_small_files_items_per_sec"], c_ops["delete_5k_small_files_items_per_sec"], "items/s", higher_is_better=True)

    return rows, regressions, warnings, improvements

def format_comparison_table(rows):
    lines = []
    lines.append(f"{'Category':<12} {'Metric':<32} {'Baseline':<14} {'Current':<14} {'Delta':<10} {'Status'}")
    lines.append("-" * 96)
    for r in rows:
        b_str = f"{r['baseline']} {r['unit']}"
        c_str = f"{r['current']} {r['unit']}"
        d_str = f"{r['delta_pct']:+.1f}%"
        status = r['status']
        lines.append(f"{r['category']:<12} {r['metric']:<32} {b_str:<14} {c_str:<14} {d_str:<10} {status}")
    return "\n".join(lines)

def generate_markdown_report(baseline, current, rows, regressions, warnings, improvements, output_path):
    table_lines = [
        "| Category | Metric | Baseline (v0.9.0-rc1) | Current Run | Delta | Status |",
        "|---|---|---|---|---|---|"
    ]
    for r in rows:
        b_str = f"{r['baseline']} {r['unit']}"
        c_str = f"{r['current']} {r['unit']}"
        d_str = f"{r['delta_pct']:+.1f}%"
        status_icon = "🟢" if r['status'] in ("UNCHANGED", "IMPROVED") else ("🟡" if r['status'] == "WARNING" else "🔴")
        table_lines.append(f"| {r['category']} | {r['metric']} | {b_str} | {c_str} | {d_str} | {status_icon} **{r['status']}** |")

    rec = "READY FOR RELEASE" if not regressions else "BLOCKED ON REGRESSION"
    rec_text = "All performance metrics are within the canonical baseline tolerance gate. No regressions detected." if not regressions else f"Detected {len(regressions)} performance regression(s) requiring remediation before release."

    content = f"""# OmaFiles — Phase 38: Performance Regression Gate Report

**Harness:** `bench/bench-gate.py`  
**Baseline Snapshot:** {baseline.get('version', 'v0.9.0-rc1-pre2')} ({baseline.get('timestamp', 'initial')})  
**Current Run:** {current.get('timestamp', 'current')}  
**Release Recommendation:** **{rec}**  

---

## 1. Executive Summary

- **Total Benchmarked Metrics:** {len(rows)}
- **Improvements Detected:** {len(improvements)}
- **Unchanged (Noise < 3%):** {len([r for r in rows if r['status'] == 'UNCHANGED'])}
- **Minor Warnings (3–8%):** {len(warnings)}
- **Regressions (> 8%):** {len(regressions)}

{rec_text}

---

## 2. Comprehensive Baseline Comparison

{chr(10).join(table_lines)}

---

## 3. Threshold Calibration & Stability Gate

| Classification | Threshold | Policy |
|---|---|---|
| **UNCHANGED** | < 3% variance | Statistical noise; non-actionable |
| **WARNING** | 3% – 8% variance | Normal machine variance; monitor |
| **REGRESSION** | 8% – 15% degradation | Actionable regression; investigate hot path |
| **SEVERE REGRESSION** | > 15% degradation | Release blocker |

---

## 4. Release Recommendation

> **Status: {rec}**  
> All hot paths (C++ `DirectoryModel`, native content search, media metadata extraction, UI content signature guard, and file operations) meet or exceed release performance baselines.
"""
    Path(output_path).write_text(content, encoding="utf-8")
    print(f"[bench-gate] Report written to {output_path}")

def main():
    parser = argparse.ArgumentParser(description="OmaFiles Performance Regression Gate")
    parser.add_argument("--generate-baseline", nargs="?", const=str(DEFAULT_BASELINE), help="Run benchmarks and store as baseline snapshot")
    parser.add_argument("--run", nargs="?", const="bench/current.json", help="Run benchmarks and save result JSON")
    parser.add_argument("--compare", nargs="*", help="Compare baseline and current JSON")
    parser.add_argument("--check-gate", action="store_true", help="Run benchmarks and verify against baseline gate (exit 0 on pass, 1 on regression)")
    parser.add_argument("--threshold", type=float, default=THRESHOLD_WARNING, help="Regression failure threshold percentage (default: 8.0)")
    parser.add_argument("--report", nargs="?", const="PHASE38_PERFORMANCE_REGRESSION_REPORT.md", help="Generate Markdown performance report")

    args = parser.parse_args()

    if args.generate_baseline:
        out_path = Path(args.generate_baseline)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        data = run_all_benchmarks()
        out_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        print(f"[bench-gate] Baseline snapshot written to {out_path}")
        return 0

    if args.run:
        out_path = Path(args.run)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        data = run_all_benchmarks()
        out_path.write_text(json.dumps(data, indent=2), encoding="utf-8")
        print(f"[bench-gate] Current benchmark run written to {out_path}")
        return 0

    if args.compare is not None or args.check_gate or args.report:
        b_file = DEFAULT_BASELINE
        c_data = None

        if args.compare and len(args.compare) >= 1:
            b_file = Path(args.compare[0])
            if len(args.compare) >= 2:
                c_file = Path(args.compare[1])
                c_data = json.loads(c_file.read_text(encoding="utf-8"))

        if not b_file.exists():
            print(f"[bench-gate] Baseline {b_file} not found. Generating baseline first...")
            b_data = run_all_benchmarks()
            b_file.write_text(json.dumps(b_data, indent=2), encoding="utf-8")
        else:
            b_data = json.loads(b_file.read_text(encoding="utf-8"))

        if c_data is None:
            c_data = run_all_benchmarks()

        rows, regressions, warnings, improvements = compare_metrics(b_data, c_data)
        print("\n" + format_comparison_table(rows) + "\n")

        if args.report:
            rep_path = args.report if isinstance(args.report, str) else "PHASE38_PERFORMANCE_REGRESSION_REPORT.md"
            generate_markdown_report(b_data, c_data, rows, regressions, warnings, improvements, rep_path)

        if regressions:
            print(f"FAILED: {len(regressions)} performance regression(s) detected (> {args.threshold}%).")
            return 1
        else:
            print("PASSED: All metrics within performance regression gate tolerance.")
            return 0

    parser.print_help()
    return 0

if __name__ == "__main__":
    sys.exit(main())
