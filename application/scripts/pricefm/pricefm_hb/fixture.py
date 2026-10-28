"""Prepare the one fixed, sealed EE development fixture without numerical imports.

Planning hashes opaque files and reads JSON/NPY headers only. Staging is a
separate operation; neither operation imports a PriceFM numerical helper.
"""
from __future__ import annotations

import argparse
import ast
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import shutil
import zipfile

SCHEMA = "r156_hb_forecast_fixture_v1"
DATA = Path("/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm")
TRACKERS = Path("/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers")
TAG = "pricefm_stage_r149_ee_origin_coverage_20261023"
TASK = "EE_C0_s1_full_seed0"
CHUNK = "clock00_part000"
PREPARATION = DATA / "launch_prep" / TAG / "preparation.json"
CHUNK_DIR = DATA / "campaigns" / TAG / "checkpoints" / TASK / CHUNK
QUANTILES = [0.1, 0.25, 0.45, 0.5, 0.55, 0.75, 0.9]
SOURCE_PINS = {
    "retained": (str(TRACKERS / "worktrees/pricefm_r149_ee_origin_coverage_20261023/application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py"), "1bd753cf723db7bdaec2eb4bafba763eb21ad5346c05d9bb1e6ee7544b8c2f20"),
    "kernel": (str(TRACKERS / "worktrees/pricefm_r148_ee_parallel_20261023/application/scripts/pricefm/492_run_pricefm_stage_r148_ee_parallel_development.py"), "d29e09ab63d9663b52e33420cf7294efbda0ba1e783ed0de540ffbfd886184ee"),
    "core": ("/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_r141_recovery_20261019/application/scripts/pricefm/pricefm_r134_core.py", "f4dca632c7f4c3a8d1b4d8a396607fd39c28876a197a9cc869f5f22810ff5453"),
    "canonical497": (str(TRACKERS / "worktrees/pricefm_r150_cached_continuation_20261023/application/scripts/pricefm/497_run_pricefm_stage_r150_cached_continuation.py"), "0809eeea65ddb2cab6525974630d031dc6fffbf4ce132184d19693b887bbce21"),
    "canonical502": (str(TRACKERS / "worktrees/pricefm_r151_retirement_aware_20261023/application/scripts/pricefm/502_screen_pricefm_stage_r151_region.py"), "2e0e9dfd8da608d2443c6ac776211e9a8cd10abe6d5d20b48150e4fa7f3084eb"),
    "canonical506": (str(TRACKERS / "worktrees/pricefm_r152_parallel_20261024/application/scripts/pricefm/506_screen_pricefm_stage_r152_region.py"), "c079b5cfa60a3b3c71a33c7caad7da2c630e119bbac4dda750f661651a4544a2"),
}
FUNCTION_AST_SHA256 = "85808b8b09ea29ae129c2b317304d4115231ceafe9d8f8885b5af81e2dbefc72"
FUNCTION_GLOBALS = ["INT_ARRAYS", "RuntimeError", "dict", "dt", "int", "kernel", "len", "round", "str", "validate_arrays"]
REFERENCE_SHA256 = "66ad69ef86a318f0bafbf6482552a9d1fc8069f63b96085c657f8a2f7591a8a0"
INT_KEYS = frozenset(("origin_positions", "clock_offsets", "stable_rng_origin_keys", "origin_timestamps_ns", "weekday_UTC", "month_UTC"))
ARRAY_SHAPES = {**{k: [8] for k in INT_KEYS}, "truth_standardized": [8, 96], "truth_eur": [8, 96],
    **{k: [8, 96, 7] for k in ("deterministic_standardized", "stochastic_standardized", "deterministic_eur", "stochastic_eur")},
    "deterministic_origin_AQL": [8], "stochastic_origin_AQL": [8], "lag_features": [8, 4]}
COMPARISON = {"version": 1, "geometry_and_dtype": "exact", "identity_truth_lag_arrays": "bitwise",
    "prediction_and_AQL_atol": 1e-12, "prediction_and_AQL_rtol": 1e-10,
    "sampler_metadata": "exact_except_reported_floating_diagnostics", "sampler_diagnostic_atol": 1e-12,
    "sampler_diagnostic_rtol": 1e-10, "all_arrays_finite": True, "quantile_crossing_atol": 1e-12,
    "test_evidence_only": True, "campaign_completion_credit": False}


def read_json(path):
    return json.loads(Path(path).read_text())


def digest(path):
    h = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def write_json(path, value):
    Path(path).write_text(json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + "\n")


def npz_headers(path):
    """Read bounded NPY headers, never array payloads (including covariances)."""
    result = {}
    with zipfile.ZipFile(path) as packet:
        names = packet.namelist()
        if len(names) != len(set(names)) or any("/" in n or not n.endswith(".npy") for n in names):
            raise ValueError("invalid NPZ members")
        for name in names:
            with packet.open(name) as stream:
                lead = stream.read(8)
                if lead[:6] != b"\x93NUMPY" or lead[6:8] not in (b"\x01\x00", b"\x02\x00"):
                    raise ValueError("unsupported NPY version")
                width = 2 if lead[6] == 1 else 4
                length = int.from_bytes(stream.read(width), "little")
                if not 0 < length <= 65536:
                    raise ValueError("invalid NPY header size")
                header = ast.literal_eval(stream.read(length).decode("latin1").strip())
            if set(header) != {"descr", "shape", "fortran_order"} or header["fortran_order"] is not False:
                raise ValueError("unsupported NPY order/header")
            shape = list(header["shape"])
            if any(type(n) is not int or n < 0 for n in shape):
                raise ValueError("invalid NPY shape")
            result[name[:-4]] = {"dtype": header["descr"], "shape": shape,
                "uncompressed_bytes": packet.getinfo(name).file_size}
    return result


def scientific_context(task, source):
    """Exact nonnumerical R149 checkpoint_context identity field mapping."""
    return dict(source=source, task_sha256=fingerprint(task),
        scientific_identity_sha256=task["scientific_identity_sha256"], original_parent_source=task["parent_source"],
        parent_seal_sha256=task["parent_seal_sha256"], scaler_sha256=task["scaler_sha256"], bank=task["bank"],
        forecast_seed=task["forecast_seed"], paths=task["paths"], horizon_steps=96, quantiles=QUANTILES,
        kernel_sha256=task["kernel_sha256"])


def validate_scientific_identity(task, descriptor, metadata, seal, source):
    """Reject subchunks, changed clocks, changed seed and nondevelopment input."""
    if (task["name"] != TASK or task["region"] != "EE" or task["role"] != "C0" or task["seed_index"] != 0
            or task["split"] != 1 or task["paths"] != 100 or task["forecast_seed"] != 2026101502
            or task["test_opened"] is not False or task["posterior_updated"] is not False or task["new_model_fits"] != 0
            or task["clock_offsets_steps"] != [0, 24, 48, 72]):
        raise ValueError("fixed training-only C0 seed0 scientific identity differs")
    positions = list(range(506, 514))
    timestamps = [(dt.datetime(2023, 6, 25, tzinfo=dt.timezone.utc) + dt.timedelta(days=i)).isoformat() for i in range(8)]
    expected = dict(name=CHUNK, clock_offset_steps=0, start=0, origin_positions=positions,
        origin_timestamps=timestamps, stable_rng_origin_keys=[p * 96 for p in positions])
    if descriptor != expected or descriptor != metadata.get("descriptor"):
        raise ValueError("whole fixed eight-origin clock descriptor differs")
    if (task["daily_origin_positions"][:8] != positions or task["origin_timestamps"]["0"][:8] != timestamps
            or not set(positions) <= set(task["validation_origin_positions"])
            or set(task["train_origin_positions"]) & set(task["validation_origin_positions"])):
        raise ValueError("original training/inner-validation cohort differs")
    context = scientific_context(task, source)
    if (metadata.get("certified") is not True or metadata.get("context") != context
            or metadata.get("posterior_updated") is not False or metadata.get("new_model_fits") != 0
            or seal.get("metadata") != dict(certified=True, context=context)
            or set(seal.get("artifacts", {})) != {"chunk.json", "predictions.npz"}
            or seal["artifacts"]["predictions.npz"] != REFERENCE_SHA256):
        raise ValueError("sealed original scientific context differs")


class Resolver:
    """Resolve only declared logical files inside an immutable staged fixture."""
    def __init__(self, root, manifest):
        self.root = Path(root).resolve()
        self.manifest = manifest
        self.assets = manifest["assets"]

    def path(self, logical, verify=True):
        entry = self.assets[str(logical)]
        relative = Path(entry["path"])
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError("unsafe staged path")
        candidate = self.root / relative
        if candidate.is_symlink() or not candidate.resolve().is_relative_to(self.root):
            raise ValueError("staged path escaped fixture")
        if verify and (not candidate.is_file() or candidate.stat().st_size != entry["bytes"] or digest(candidate) != entry["sha256"]):
            raise ValueError("staged bytes differ: " + str(logical))
        return candidate

    def directory(self, logical):
        children = [p for p in self.assets if Path(p).is_relative_to(Path(logical))]
        if not children:
            raise ValueError("unmapped logical directory")
        physical = self.root / "files" / Path(logical).relative_to("/")
        if not physical.resolve().is_relative_to(self.root):
            raise ValueError("unsafe staged directory")
        for child in children:
            if self.path(child).relative_to(physical) != Path(child).relative_to(logical):
                raise ValueError("directory alias does not preserve layout")
        return physical

    def verify_all(self):
        for logical in self.assets:
            self.path(logical)


def load_fixture(manifest_path, verify_files=True):
    path = Path(manifest_path)
    expected = path.with_suffix(".sha256").read_text().strip()
    if digest(path) != expected:
        raise ValueError("fixture manifest seal differs")
    manifest = read_json(path)
    if manifest.get("schema") != SCHEMA or manifest.get("comparison") != COMPARISON:
        raise ValueError("unsupported fixture schema/comparison")
    if manifest.get("sources") != {k: dict(logical=p, sha256=h) for k, (p, h) in SOURCE_PINS.items()}:
        raise ValueError("frozen helper identities differ")
    if manifest.get("function") != dict(name="retained_chunk", ast_sha256=FUNCTION_AST_SHA256, allowed_globals=FUNCTION_GLOBALS):
        raise ValueError("frozen function identity differs")
    resolver = Resolver(path.parent, manifest)
    for ledger in manifest["ledgers"].values():
        for logical, sha in ledger.items():
            if resolver.assets[logical]["sha256"] != sha:
                raise ValueError("manifest dropped/replaced an original ledger member")
    if verify_files:
        resolver.verify_all()
        prep = read_json(resolver.path(manifest["preparation"]))
        task = next(t for t in prep["tasks"] if t["name"] == TASK)
        if task != manifest["task"] or prep["source"] != manifest["source"]:
            raise ValueError("manifest scientific task/source differs from original preparation")
        for key in ("source_sha256", "input_sha256"):
            if manifest["ledgers"][key] != prep[key]:
                raise ValueError("original preparation ledger membership changed")
        if manifest["ledgers"]["parent_input_sha256"] != task["parent_input_sha256"]:
            raise ValueError("original parent ledger membership changed")
        metadata = read_json(resolver.path(manifest["reference"]["metadata"]))
        seal = read_json(resolver.path(manifest["reference"]["seal"]))
        validate_scientific_identity(task, manifest["descriptor"], metadata, seal, prep["source"])
        for name, sha in seal["artifacts"].items():
            logical = str(Path(manifest["reference"]["seal"]).parent / name)
            if resolver.assets[logical]["sha256"] != sha:
                raise ValueError("original reference artifact seal differs")
    return manifest, resolver


def plan_fixture(destination, preparation_path=PREPARATION, task_name=TASK, chunk_dir=CHUNK_DIR):
    """Write a sealed byte inventory; call stage_fixture separately after sizing."""
    if task_name != TASK or Path(preparation_path) != PREPARATION or Path(chunk_dir) != CHUNK_DIR:
        raise ValueError("selection is fixed before replay; arbitrary fixture selection is disabled")
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=False)
    prep = read_json(preparation_path)
    task = next(t for t in prep["tasks"] if t["name"] == task_name)
    metadata_path, seal_path = Path(chunk_dir) / "chunk.json", Path(chunk_dir) / "completed_evidence.json"
    metadata, seal = read_json(metadata_path), read_json(seal_path)
    descriptor = metadata["descriptor"]
    validate_scientific_identity(task, descriptor, metadata, seal, prep["source"])
    ledgers = {k: prep[k] for k in ("source_sha256", "input_sha256")}
    ledgers["parent_input_sha256"] = task["parent_input_sha256"]
    combined = {}
    def pin(logical, sha=None):
        logical = str(logical)
        actual = digest(logical)
        if sha is not None and actual != sha:
            raise ValueError("original immutable bytes differ: " + logical)
        if logical in combined and combined[logical] != actual:
            raise ValueError("conflicting original ledger")
        combined[logical] = actual
    for ledger in ledgers.values():
        for logical, sha in ledger.items():
            pin(logical, sha)
    pin(preparation_path)
    task_path = DATA / "campaigns" / TAG / "tasks" / (TASK + ".json")
    pin(task_path)
    if read_json(task_path) != task:
        raise ValueError("original task packet differs from preparation")
    pin(task["bank"]["path"], task["bank"]["sha256"])
    pin(task["scaler_path"], task["scaler_sha256"])
    for logical, sha in SOURCE_PINS.values():
        pin(logical, sha)
    pin(metadata_path, seal["artifacts"]["chunk.json"])
    prediction_path = Path(chunk_dir) / "predictions.npz"
    pin(prediction_path, REFERENCE_SHA256)
    pin(seal_path)
    headers = npz_headers(prediction_path)
    if set(headers) != set(ARRAY_SHAPES) or any(headers[k]["shape"] != shape or headers[k]["dtype"] != ("<i8" if k in INT_KEYS else "<f8") for k, shape in ARRAY_SHAPES.items()):
        raise ValueError("sealed reference geometry/dtype differs")
    terminal = read_json(Path(task["parent_fit"]) / "terminal.json")
    p = int(terminal["p"])
    assets = {logical: dict(path=str(Path("files") / Path(logical).relative_to("/")), sha256=sha,
        bytes=Path(logical).stat().st_size) for logical, sha in sorted(combined.items())}
    assets[str(prediction_path)]["path"] = "reference/local_predictions.npz"
    manifest = dict(schema=SCHEMA, namespace="TEST", selection=dict(rule="first_lexicographic_complete_sealed_actual_C0_EE_seed0_eight_origin_training_chunk_carried_into_initial87", task=TASK, chunk=CHUNK),
        preparation=str(preparation_path), task_path=str(task_path), source=prep["source"], task=task,
        descriptor=descriptor, dependency_root=prep["dependency"], dependency_head=prep["dependency_head"],
        sources={k: dict(logical=logical, sha256=sha) for k, (logical, sha) in SOURCE_PINS.items()},
        function=dict(name="retained_chunk", ast_sha256=FUNCTION_AST_SHA256, allowed_globals=FUNCTION_GLOBALS),
        ledgers=ledgers, assets=assets, comparison=COMPARISON,
        reference=dict(arrays=str(prediction_path), metadata=str(metadata_path), seal=str(seal_path), headers=headers),
        size=dict(files=len(assets), bytes=sum(x["bytes"] for x in assets.values()), normal_dimension=p,
            covariance_bytes=8*p*p, selected_bank_headers=npz_headers(task["bank"]["path"])),
        scientific_authorization=dict(new_fits=0, posterior_updates=0, official_origins=0, AL=False,
            full_FI_or_DK2_screening=False, campaign_completion_credit=False))
    path = destination / "manifest.json"
    write_json(path, manifest)
    path.with_suffix(".sha256").write_text(digest(path) + "\n")
    return path


def stage_fixture(manifest_path):
    """Copy and hash every declared byte; never follow an undeclared alias."""
    manifest, resolver = load_fixture(manifest_path, verify_files=False)
    for logical, entry in manifest["assets"].items():
        target = resolver.path(logical, verify=False)
        if target.exists():
            resolver.path(logical)
            continue
        if digest(logical) != entry["sha256"]:
            raise ValueError("source changed before staging: " + logical)
        target.parent.mkdir(parents=True, exist_ok=True)
        with Path(logical).open("rb") as source, target.open("xb") as output:
            shutil.copyfileobj(source, output, length=1024 * 1024)
        resolver.path(logical)
        target.chmod(0o444)
    load_fixture(manifest_path)
    return dict(status="STAGED_HASH_VERIFIED_NO_NUMERICAL_IMPORTS", manifest_sha256=digest(manifest_path), **manifest["size"])


def build_fixture(preparation_path, task_name, chunk_dir, destination):
    """Compatibility entry point: plan only, intentionally separate from staging."""
    return plan_fixture(destination, preparation_path, task_name, chunk_dir)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    sub.add_parser("plan").add_argument("destination")
    sub.add_parser("stage").add_argument("manifest")
    sub.add_parser("verify").add_argument("manifest")
    args = parser.parse_args()
    if args.action == "plan":
        path = plan_fixture(args.destination)
        print(json.dumps(dict(manifest=str(path), sha256=digest(path), size=read_json(path)["size"]), sort_keys=True))
    elif args.action == "stage":
        print(json.dumps(stage_fixture(args.manifest), sort_keys=True))
    else:
        manifest, _ = load_fixture(args.manifest)
        print(json.dumps(dict(status="VERIFIED", sha256=digest(args.manifest), size=manifest["size"]), sort_keys=True))


if __name__ == "__main__":
    main()
