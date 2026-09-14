#!/usr/bin/env python3

import csv
import importlib.util
from pathlib import Path
import tempfile


repo = Path(__file__).resolve().parents[2]
script = repo / "application" / "scripts" / "399_launch_glofas_search_phase2.py"
spec = importlib.util.spec_from_file_location("glofas_search2_scheduler", str(script))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory(prefix="glofas_search2_scheduler_") as tmp:
    root = Path(tmp)
    (root / "configs").mkdir()
    (root / "status").mkdir()
    manifest = root / "configs" / "job_manifest.csv"
    with manifest.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["job_id", "memory_weight", "method", "design_group_id"])
        writer.writeheader()
        writer.writerow({"job_id": "small", "memory_weight": "1", "method": "ridge", "design_group_id": ""})
        writer.writerow({"job_id": "rhs_a", "memory_weight": "3", "method": "rhs", "design_group_id": "shared"})
        writer.writerow({"job_id": "rhs_b", "memory_weight": "3", "method": "rhs", "design_group_id": "shared"})
    jobs = module.read_jobs(root)
    assert len(jobs) == 3
    assert sum(int(row["memory_weight"]) for row in jobs) == 7
    units = module.build_units(jobs, group_rhs_design=True)
    assert len(units) == 2
    shared = next(unit for unit in units if unit["unit_id"] == "shared")
    assert shared["grouped"] and len(shared["jobs"]) == 2 and shared["memory_weight"] == 3
    command = module.job_command(repo, root, "small")
    assert "396_run_glofas_search_phase2_worker.R" in command
    assert "397_score_glofas_search_phase2.R" in command
    assert command.index("396_run_glofas_search_phase2_worker.R") < command.index("397_score_glofas_search_phase2.R")
    assert "401_run_glofas_search_phase2_rhs_group.R" in module.group_command(repo, root, "shared")
    assert not module.job_complete(root, "small")
    module.status_path(root, "small", ".done").write_text("ok\n")
    assert module.job_complete(root, "small")

print("Search-II scheduler tests passed")
