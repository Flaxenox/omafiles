import os, sys
# Portable dataset location: honor an explicit override, else the XDG cache dir
# (fallback ~/.cache). No hardcoded home or username, so this runs on any clone.
base = os.environ.get("OMAFILES_PERFBENCH_DIR") or os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache"),
    "omafiles-perfbench")
sizes = {"1k":1000, "10k":10000, "50k":50000, "100k":100000}
for name, n in sizes.items():
    d = os.path.join(base, name)
    os.makedirs(d, exist_ok=True)
    existing = len(os.listdir(d))
    if existing >= n:
        print(f"{name}: already {existing}", flush=True); continue
    for i in range(n):
        # mix: digits (naturalCompare), MixedCase (toLower/locale), extensions
        if i % 50 == 0:
            fn = f"Folder_{i:06d}"
            os.makedirs(os.path.join(d, fn), exist_ok=True)
        else:
            fn = f"File_{i:06d}_Report.txt" if i % 3 else f"img{i}.PNG"
            p = os.path.join(d, fn)
            if not os.path.exists(p):
                open(p, "w").close()
    # symlinks: one valid, one broken
    try:
        os.symlink(os.path.join(d, "File_000001_Report.txt"), os.path.join(d, "zzz_link_valid"))
    except FileExistsError: pass
    try:
        os.symlink("/nonexistent/target", os.path.join(d, "zzz_link_broken"))
    except FileExistsError: pass
    print(f"{name}: created {n}", flush=True)
print("DONE", flush=True)
