"""Focused tests for the R93 exact-name normal runtime repair."""

from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

import pytest


ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = ROOT / "application/scripts/pricefm"
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))
SCRIPT = SCRIPT_DIR / "293_materialize_pricefm_stage_r93_normal_runtime.py"


def load_script():
    spec = importlib.util.spec_from_file_location(SCRIPT.stem, SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def minimal_source(tmp_path: Path) -> Path:
    source = tmp_path / "source"
    for name in ("R", "src", "inst", "man"):
        (source / name).mkdir(parents=True)
    (source / "R/qdesn_normal.R").write_text(
        "normalize <- function(prior, p) {\n"
        "  b <- prior$mean %||% prior$b %||% rep(0, p)\n"
        "  b\n"
        "}\n"
    )
    (source / "DESCRIPTION").write_text("Package: exdqlm\nVersion: 1.1.1\n")
    (source / "NAMESPACE").write_text("export(normalize)\n")
    return source


def test_runtime_patch_uses_exact_list_names_and_marks_version(tmp_path):
    module = load_script()
    source = minimal_source(tmp_path)
    package = tmp_path / "runtime/exdqlm"
    module.prepare_source(source, package)
    module.patch_source(package)
    normal = (package / "R/qdesn_normal.R").read_text()
    assert 'prior[["mean", exact = TRUE]]' in normal
    assert 'prior[["b", exact = TRUE]]' in normal
    assert "prior$mean %||% prior$b" not in normal
    description = (package / "DESCRIPTION").read_text()
    assert f"Version: {module.VERSION}" in description
    assert f"Config/PriceFM/repair: {module.REPAIR}" in description


def test_runtime_patch_refuses_missing_or_duplicate_anchor(tmp_path):
    module = load_script()
    source = minimal_source(tmp_path)
    package = tmp_path / "runtime/exdqlm"
    module.prepare_source(source, package)
    module.patch_source(package)
    with pytest.raises(RuntimeError, match="exactly one runtime repair anchor"):
        module.patch_source(package)
