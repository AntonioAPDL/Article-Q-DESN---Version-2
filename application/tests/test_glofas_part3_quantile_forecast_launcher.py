#!/usr/bin/env python3
import csv
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path


repo = Path(__file__).resolve().parents[2]
script = repo / "application/scripts/75_prepare_glofas_part3_quantile_forecast_chain.py"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    configs = root / "configs"
    configs.mkdir(parents=True)
    cache = configs / "part3_design_cache.rds"
    cache.write_bytes(b"test-cache")
    fits = {}
    for family in ("normal_ridge_joint", "normal_rhs_vb_joint"):
        path = root / f"{family}.rds"
        path.write_bytes(family.encode())
        fits[family] = path
    with (configs / "part3_preflight_certificate.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["status", "design_cache", "design_cache_sha256"])
        writer.writeheader()
        writer.writerow({"status": "ready_for_part3_quantile_forecast_chain", "design_cache": cache, "design_cache_sha256": digest(cache)})
    with (configs / "part3_normal_fit_inventory.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=["model_family", "fit_path", "fit_sha256"])
        writer.writeheader()
        for family, path in fits.items():
            writer.writerow({"model_family": family, "fit_path": path, "fit_sha256": digest(path)})
    subprocess.run(["python3", str(script), "--repo-root", str(repo), "--runtime-root", str(root)], check=True)
    with (configs / "part3_quantile_forecast_job_manifest.csv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    assert len(rows) == 18
    keyed = {row["job_id"]: row for row in rows}
    assert keyed["independent_al_q0p50"]["dependencies"] == "normal_rhs_forecast"
    assert keyed["independent_al_q0p35"]["dependencies"] == "independent_al_q0p50"
    assert keyed["independent_al_q0p20"]["dependencies"] == "independent_al_q0p35"
    assert keyed["independent_al_q0p05"]["dependencies"] == "independent_al_q0p20"
    assert keyed["independent_al_q0p65"]["dependencies"] == "independent_al_q0p50"
    assert keyed["independent_al_q0p80"]["dependencies"] == "independent_al_q0p65"
    assert keyed["independent_al_q0p95"]["dependencies"] == "independent_al_q0p80"
    for tau in ("0p05", "0p20", "0p35", "0p50", "0p65", "0p80", "0p95"):
        assert keyed[f"independent_exal_q{tau}"]["dependencies"] == f"independent_al_q{tau}"
    assert len(keyed["joint_al"]["dependencies"].split("|")) == 7
    assert len(keyed["joint_exal"]["dependencies"].split("|")) == 7
    metadata = json.loads((configs / "part3_quantile_forecast_chain_metadata.json").read_text())
    assert metadata["quantile_fits_and_forecasts"] == 16
print("test_glofas_part3_quantile_forecast_launcher: OK")
