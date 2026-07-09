"""Shared helpers for the article-side PriceFM data pipeline."""

from __future__ import print_function

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import yaml


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_CONFIG = "application/config/pricefm_data_pipeline.yaml"


def parse_bool(value):
    if isinstance(value, bool):
        return value
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "y", "on"):
        return True
    if text in ("0", "false", "no", "n", "off"):
        return False
    raise argparse.ArgumentTypeError("expected true or false")


def parser(description):
    p = argparse.ArgumentParser(description=description)
    p.add_argument("--config", default=DEFAULT_CONFIG)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def repo_path(path):
    p = Path(path)
    if p.is_absolute():
        return p
    return REPO_ROOT / p


def load_config(path=DEFAULT_CONFIG):
    config_path = repo_path(path)
    with open(config_path, "r") as f:
        cfg = yaml.safe_load(f)
    if not isinstance(cfg, dict) or "pricefm" not in cfg:
        raise ValueError("Config must contain a top-level 'pricefm' block.")
    validate_config(cfg)
    return cfg


def validate_config(cfg):
    pricefm = cfg["pricefm"]
    required = [
        "repo_id", "filename", "raw_dir", "interim_dir", "processed_dir",
        "time_col", "timezone", "frequency", "observed_start_utc",
        "observed_end_utc", "expected_rows", "expected_columns",
        "split_time_col", "market_time_definition", "regions", "features",
        "splits", "scaling", "windows", "pilot",
    ]
    missing = [k for k in required if k not in pricefm]
    if missing:
        raise ValueError("Missing pricefm config keys: {}".format(", ".join(missing)))
    for key in ("raw_dir", "interim_dir", "processed_dir"):
        path = Path(pricefm[key])
        if path.is_absolute() or not str(path).startswith("application/"):
            raise ValueError("{} must be a repo-relative application path".format(key))
    if len(pricefm["regions"]) != len(set(pricefm["regions"])):
        raise ValueError("Duplicate regions in config.")
    features = pricefm["features"]
    if features["label"] not in features["raw"]:
        raise ValueError("Label feature must be present in raw features.")
    for feature in features["lag"] + features["lead"]:
        if feature not in features["raw"]:
            raise ValueError("Model feature '{}' is absent from raw features.".format(feature))
    if pricefm["split_time_col"] != "market_time":
        raise ValueError("Clean PriceFM pipeline must split on market_time.")
    if pricefm["pilot"]["region"] not in pricefm["regions"]:
        raise ValueError("Pilot region is not in configured regions.")


def pricefm_block(cfg):
    return cfg["pricefm"]


def now_utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def sha256_file(path, block_size=2 ** 20):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            block = f.read(block_size)
            if not block:
                break
            h.update(block)
    return h.hexdigest()


def write_json(path, payload):
    path = repo_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w") as f:
        json.dump(payload, f, indent=2, sort_keys=True)
        f.write("\n")


def read_json(path):
    with open(repo_path(path), "r") as f:
        return json.load(f)


def refuse_incompatible(path, force=False):
    path = repo_path(path)
    if path.exists() and not force:
        raise FileExistsError(
            "{} already exists. Re-run with --force true to overwrite.".format(path)
        )


def require_modules(names):
    missing = []
    for name in names:
        try:
            __import__(name)
        except ImportError:
            missing.append(name)
    if missing:
        raise RuntimeError(
            "Missing Python packages: {}. See application/scripts/pricefm/README.md.".format(
                ", ".join(missing)
            )
        )


def run_command(cmd, cwd=None):
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        check=False,
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stdout)
        sys.stderr.write(proc.stderr)
        raise RuntimeError("Command failed: {}".format(" ".join(cmd)))
    return proc.stdout.strip()


def raw_csv_path(cfg):
    p = pricefm_block(cfg)
    return repo_path(Path(p["raw_dir"]) / p["filename"])


def interim_parquet_path(cfg):
    return repo_path(Path(pricefm_block(cfg)["interim_dir"]) / "FINAL.parquet")


def processed_dir(cfg):
    return repo_path(pricefm_block(cfg)["processed_dir"])


def expected_region_columns(cfg):
    p = pricefm_block(cfg)
    cols = []
    for region in p["regions"]:
        for feature in p["features"]["raw"]:
            cols.append("{}-{}".format(region, feature))
    return cols


def fold_spec(cfg, fold):
    for spec in pricefm_block(cfg)["splits"]:
        if int(spec["fold"]) == int(fold):
            return spec
    raise ValueError("Unknown fold: {}".format(fold))


def summarize(path, payload):
    print(json.dumps({"path": str(path), "summary": payload}, indent=2, sort_keys=True))
