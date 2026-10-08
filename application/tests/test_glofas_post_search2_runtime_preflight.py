#!/usr/bin/env python3
"""Focused tests for post-Search-II production input/readiness helpers."""

import csv
import importlib.util
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


prepare = load(
    "glofas_post_search2_prepare",
    ROOT / "application/scripts/404_prepare_glofas_post_search2_runtime.py",
)


with tempfile.TemporaryDirectory(prefix="glofas_post_search2_preflight_") as tmp:
    tmp = Path(tmp)
    source = tmp / "source"
    source.mkdir()
    (source / "a.csv").write_text("date,value\n2022-12-25,1\n", encoding="utf-8")
    (source / "b.csv").write_text("date,value\n2022-12-25,2\n", encoding="utf-8")
    contract_path = tmp / "contract.csv"
    rows = []
    for input_id, name in (("a", "a.csv"), ("b", "b.csv")):
        path = source / name
        rows.append({
            "input_id": input_id,
            "relative_path": name,
            "size_bytes": path.stat().st_size,
            "sha256": prepare.sha256(path),
            "required": "true",
            "model_role": "test",
        })
    with contract_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)

    loaded = prepare.load_hash_contract(contract_path)
    assert len(prepare.validate_input_source(source, loaded)) == 2
    (source / "uncontracted.txt").write_text("must not be copied\n", encoding="utf-8")
    copied = tmp / "copied"
    prepare.copy_input_bundle(source, copied, loaded)
    assert prepare.sha256(copied / "a.csv") == rows[0]["sha256"]
    assert not (copied / "uncontracted.txt").exists()

    unsafe_contract = tmp / "unsafe_contract.csv"
    unsafe_rows = [{**rows[0], "relative_path": "../a.csv"}]
    with unsafe_contract.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(unsafe_rows[0]))
        writer.writeheader()
        writer.writerows(unsafe_rows)
    try:
        prepare.load_hash_contract(unsafe_contract)
    except SystemExit as exc:
        assert "unsafe relative path" in str(exc)
    else:
        raise AssertionError("unsafe input path was accepted")

    (source / "a.csv").write_text("changed\n", encoding="utf-8")
    try:
        prepare.validate_input_source(source, loaded)
    except SystemExit as exc:
        assert "mismatch" in str(exc)
    else:
        raise AssertionError("changed input was accepted")

    nonempty = tmp / "nonempty"
    nonempty.mkdir()
    (nonempty / "evidence.txt").write_text("keep", encoding="utf-8")
    try:
        prepare.require_empty_destination(nonempty, "test")
    except SystemExit as exc:
        assert "non-empty" in str(exc)
    else:
        raise AssertionError("non-empty destination was accepted")

    original = {
        "paths": {"input_manifest": "/old/manifest.csv", "cutoffs": "cutoffs.csv"},
        "reservoir": {"alpha": 0.5, "rho": 0.9},
    }
    relocated = {
        "paths": {"input_manifest": "/new/manifest.csv", "cutoffs": "cutoffs.csv"},
        "reservoir": {"alpha": 0.5, "rho": 0.9},
    }
    changed = {
        "paths": {"input_manifest": "/new/manifest.csv", "cutoffs": "cutoffs.csv"},
        "reservoir": {"alpha": 0.6, "rho": 0.9},
    }
    assert prepare.scientific_config_hash(original) == prepare.scientific_config_hash(relocated)
    assert prepare.scientific_config_hash(original) != prepare.scientific_config_hash(changed)

print("GLOFAS_POST_SEARCH2_RUNTIME_PREFLIGHT_TEST_PASS")
