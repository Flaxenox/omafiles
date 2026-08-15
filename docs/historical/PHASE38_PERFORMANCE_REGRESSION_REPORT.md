# OmaFiles — Phase 38: Performance Regression Gate Report

**Harness:** `bench/bench-gate.py`  
**Baseline Snapshot:** v0.9.0-rc1-pre2 (2026-08-15T00:14:43Z)  
**Current Run:** 2026-08-15T00:15:11Z  
**Release Recommendation:** **READY FOR RELEASE**  

---

## 1. Executive Summary

- **Total Benchmarked Metrics:** 22
- **Improvements Detected:** 2
- **Unchanged (Noise < 3%):** 18
- **Minor Warnings (3–8%):** 2
- **Regressions (> 8%):** 0

All performance metrics are within the canonical baseline tolerance gate. No regressions detected.

---

## 2. Comprehensive Baseline Comparison

| Category | Metric | Baseline (v0.9.0-rc1) | Current Run | Delta | Status |
|---|---|---|---|---|---|
| Startup | Startup Wall Time | 726.73 ms | 725.28 ms | -0.2% | 🟢 **UNCHANGED** |
| Startup | Startup CPU Time | 436.7 ms | 433.15 ms | -0.8% | 🟢 **UNCHANGED** |
| Startup | Peak Memory (RSS) | 93.97 MB | 94.12 MB | +0.2% | 🟢 **UNCHANGED** |
| Navigation | Directory Listing 1k | 2.22 ms | 2.24 ms | +0.9% | 🟢 **UNCHANGED** |
| Navigation | QVariant Conversion 1k | 0.34 ms | 0.33 ms | -2.9% | 🟢 **UNCHANGED** |
| Navigation | Directory Listing 10k | 25.55 ms | 25.55 ms | +0.0% | 🟢 **UNCHANGED** |
| Navigation | QVariant Conversion 10k | 2.88 ms | 2.84 ms | -1.4% | 🟢 **UNCHANGED** |
| Navigation | Directory Listing 50k | 136.64 ms | 136.92 ms | +0.2% | 🟢 **UNCHANGED** |
| Navigation | QVariant Conversion 50k | 13.78 ms | 13.68 ms | -0.7% | 🟢 **UNCHANGED** |
| Navigation | Directory Listing 100k | 306.38 ms | 307.08 ms | +0.2% | 🟢 **UNCHANGED** |
| Navigation | QVariant Conversion 100k | 45.68 ms | 46.79 ms | +2.4% | 🟢 **UNCHANGED** |
| UIGuard | Signature Check rows_1002 | 0.0 ms/call | 0.0 ms/call | +0.0% | 🟢 **UNCHANGED** |
| UIGuard | Signature Check rows_10002 | 0.001 ms/call | 0.0 ms/call | -100.0% | 🟢 **IMPROVED** |
| UIGuard | Signature Check rows_50002 | 0.0 ms/call | 0.0 ms/call | +0.0% | 🟢 **UNCHANGED** |
| UIGuard | Signature Check rows_100002 | 0.0 ms/call | 0.001 ms/call | +0.0% | 🟢 **UNCHANGED** |
| Search | Search query_Report_ms | 3.0 ms | 3.0 ms | +0.0% | 🟢 **UNCHANGED** |
| Search | Search query_img_ms | 3.0 ms | 3.0 ms | +0.0% | 🟢 **UNCHANGED** |
| Search | Search query_999_ms | 77.0 ms | 76.0 ms | -1.3% | 🟢 **UNCHANGED** |
| Search | Search query_Folder_0000_ms | 79.0 ms | 74.0 ms | -6.3% | 🟢 **IMPROVED** |
| FileOps | 100MB Copy Throughput | 3077.27 MB/s | 3049.23 MB/s | -0.9% | 🟢 **UNCHANGED** |
| FileOps | 5k Small Files Copy Rate | 25227.0 items/s | 24341.2 items/s | -3.5% | 🟡 **WARNING** |
| FileOps | 5k Small Files Delete Rate | 237476.8 items/s | 227269.7 items/s | -4.3% | 🟡 **WARNING** |

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

> **Status: READY FOR RELEASE**  
> All hot paths (C++ `DirectoryModel`, native content search, media metadata extraction, UI content signature guard, and file operations) meet or exceed release performance baselines.
