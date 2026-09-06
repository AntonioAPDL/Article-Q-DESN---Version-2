#!/usr/bin/env python3
"""Freeze the CRAN 1.1.1 authority boundary without a broad PriceFM refit."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

import pandas as pd

from pricefm_common import parse_bool, write_json


ARTIFACT_REPO = Path("/data/jaguir26/local/src/Article-Q-DESN")
DATA = ARTIFACT_REPO / "application/data_local/pricefm"
R62 = DATA / "authoritative/pricefm_stage_r62_matched_seven_quantile_authority_20260827"
R65 = DATA / "authoritative/pricefm_stage_r65_early_stop_closeout_20260829"
R66_TAG = "pricefm_stage_r66_corrected_structured_exal_vb_20260829"
R66_GRID = DATA / "experiment_grids" / R66_TAG
R66_RUNS = DATA / "runs" / R66_TAG
OUTPUT = DATA / "authoritative/pricefm_stage_r67_cran111_rhs_reuse_audit_20260830"
CRAN110_URL = "https://cran.r-project.org/src/contrib/Archive/exdqlm/exdqlm_1.1.0.tar.gz"
CRAN111_URL = "https://cran.r-project.org/src/contrib/exdqlm_1.1.1.tar.gz"
CRAN110_SHA256 = "51bc968f617721c9ab1dcfc6ec14857d30827fcd36659f3de45337cc3c82bd14"
CRAN111_SHA256 = "3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e"
CRAN110_TARBALL = DATA / "runtime_sources/exdqlm_cran_1p1p0_audit/exdqlm_1.1.0.tar.gz"
CRAN111_TARBALL = DATA / "runtime_sources/exdqlm_cran_1p1p1/exdqlm_1.1.1.tar.gz"
CRAN111_LIBRARY = DATA / "runtime_libraries/exdqlm_cran_1p1p1"
R65_LIBRARY = DATA / "runtime_libraries/exdqlm_cc85a75"
R65_SOURCE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r65_cc85a75")
R66_SOURCE = Path("/data/jaguir26/local/src/exdqlm__wt__pricefm_r66_ab5741c")


def parser() -> argparse.ArgumentParser:
    root = Path(__file__).resolve().parents[3]
    scripts = root / "application/scripts/pricefm"
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--code-root", type=Path, default=root)
    p.add_argument("--r62-authority", type=Path, default=R62 / "pricefm_stage_r62_matched_seven_quantile_authority.csv")
    p.add_argument("--r62-summary", type=Path, default=R62 / "summary.json")
    p.add_argument("--r65-summary", type=Path, default=R65 / "summary.json")
    p.add_argument("--r65-reuse-manifest", type=Path, default=R65 / "pricefm_stage_r65_checkpoint_reuse_manifest.csv")
    p.add_argument("--r66-launch-status", type=Path, default=R66_GRID / "launch_status.csv")
    p.add_argument("--r66-run-dir", type=Path, default=R66_RUNS)
    p.add_argument("--cran110-tarball", type=Path, default=CRAN110_TARBALL)
    p.add_argument("--cran111-tarball", type=Path, default=CRAN111_TARBALL)
    p.add_argument("--cran111-library", type=Path, default=CRAN111_LIBRARY)
    p.add_argument("--r65-library", type=Path, default=R65_LIBRARY)
    p.add_argument("--r65-source", type=Path, default=R65_SOURCE)
    p.add_argument("--r66-source", type=Path, default=R66_SOURCE)
    p.add_argument("--source-contract-script", type=Path, default=scripts / "pricefm_stage_r67_source_contract.R")
    p.add_argument("--cran-probe-script", type=Path, default=scripts / "pricefm_stage_r67_cran_al_rhsns_probe.R")
    p.add_argument("--fork-probe-script", type=Path, default=scripts / "pricefm_stage_r67_fork_al_rhsns_probe.R")
    p.add_argument("--output-dir", type=Path, default=OUTPUT)
    p.add_argument("--download-if-missing", type=parse_bool, default=True)
    p.add_argument("--run-numerical-probes", type=parse_bool, default=True)
    p.add_argument("--expected-r62-cases", type=int, default=114)
    p.add_argument("--expected-r65-valid-al", type=int, default=440)
    p.add_argument("--expected-r65-valid-exal", type=int, default=426)
    p.add_argument("--expected-r66-launch-rows", type=int, default=1)
    p.add_argument("--force", type=parse_bool, default=False)
    return p


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with Path(path).open("rb") as handle:
        for block in iter(lambda: handle.read(2**20), b""):
            digest.update(block)
    return digest.hexdigest()


def ensure_tarball(path: Path, url: str, expected_sha256: str, download: bool) -> Path:
    path = path.expanduser()
    if not path.is_file():
        if not download:
            raise FileNotFoundError(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_name(path.name + ".download.tmp")
        try:
            with urllib.request.urlopen(url) as response, tmp.open("wb") as handle:
                shutil.copyfileobj(response, handle)
            tmp.replace(path)
        finally:
            if tmp.exists():
                tmp.unlink()
    observed = sha256(path)
    if observed != expected_sha256:
        raise RuntimeError(f"Tarball hash mismatch for {path}: {observed}")
    return path.resolve()


def safe_extract(tarball: Path, destination: Path) -> Path:
    destination = destination.resolve()
    with tarfile.open(tarball, "r:gz") as archive:
        for member in archive.getmembers():
            target = (destination / member.name).resolve()
            if destination != target and destination not in target.parents:
                raise RuntimeError(f"Unsafe tar member: {member.name}")
            if member.issym() or member.islnk():
                raise RuntimeError(f"Linked tar member is not allowed: {member.name}")
        archive.extractall(destination, filter="data")
    source = destination / "exdqlm"
    if not (source / "DESCRIPTION").is_file():
        raise RuntimeError(f"Extracted source tree is incomplete: {source}")
    return source


def prepare_output(path: Path, force: bool) -> Path:
    path = path.resolve()
    if path.exists() and any(path.iterdir()):
        if not force:
            raise FileExistsError(path)
        shutil.rmtree(path)
    path.mkdir(parents=True, exist_ok=True)
    return path


def run_json(command: list[str], output_path: Path) -> dict:
    subprocess.run(command, check=True)
    if not output_path.is_file():
        raise RuntimeError(f"Command did not create {output_path}")
    return json.loads(output_path.read_text())


def install_audit_library(tarball: Path, library: Path, log_path: Path) -> None:
    library.mkdir(parents=True, exist_ok=True)
    with log_path.open("w") as log:
        subprocess.run(
            ["R", "CMD", "INSTALL", f"--library={library}", "--preclean", str(tarball)],
            check=True,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
        )


def probe_cran(script: Path, library: Path, version: str, output: Path) -> dict:
    return run_json(
        ["Rscript", str(script), str(library), version, str(output)],
        output,
    )


def probe_fork(script: Path, library: Path, output: Path) -> dict:
    return run_json(["Rscript", str(script), str(library), str(output)], output)


def exact_probe_equal(left: dict, right: dict) -> bool:
    fields = (
        "engine", "seed", "tau", "tau0", "converged", "iter", "qbeta_m",
        "qbeta_V", "qsig", "samp_beta", "samp_sigma", "prediction",
    )
    return all(left.get(field) == right.get(field) for field in fields)


def numeric_vector(value) -> list[float]:
    if isinstance(value, list):
        return [float(item) for item in value]
    return [float(value)]


def max_abs_difference(left, right) -> float:
    a = numeric_vector(left)
    b = numeric_vector(right)
    if len(a) != len(b):
        return math.inf
    return max((abs(x - y) for x, y in zip(a, b)), default=0.0)


def bool_series(frame: pd.DataFrame, column: str) -> pd.Series:
    if column not in frame:
        return pd.Series(False, index=frame.index)
    return frame[column].astype(str).str.lower().isin({"1", "true", "yes", "y"})


def active_r66_processes() -> list[str]:
    result = subprocess.run(
        ["pgrep", "-af", "pricefm_stage_r66|230_run_pricefm_stage_r66"],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    return [
        line
        for line in result.stdout.splitlines()
        if line.strip() and "pgrep -af" not in line
    ]


def source_rows(source_contract: dict) -> pd.DataFrame:
    comparisons = source_contract["comparisons"]
    explanations = {
        "cran_110_vs_111_static_beta_prior_identical": "Official RHS/RHS-NS implementation",
        "cran_110_vs_111_public_al_prefix_identical": "Public AL dispatch and preprocessing",
        "cran_110_vs_111_static_al_solver_identical": "Public static AL CAVI solver",
        "cran_110_vs_111_structured_sigmagam_identical": "CRAN 1.1.1 adds a new default structured exAL scale-skewness block",
        "cran_111_vs_r65_static_beta_prior_identical": "R65 retains the public CRAN static prior file",
        "cran_111_vs_r65_public_al_prefix_identical": "R65 retains the public CRAN AL entry path",
        "cran_111_vs_r65_static_al_solver_identical": "R65 retains the public CRAN AL solver",
        "cran_111_vs_r65_structured_sigmagam_identical": "R65 retains the official CRAN structured scale-skewness helper",
        "cran_111_vs_r66_static_beta_prior_identical": "R66 retains the public CRAN static prior file",
        "cran_111_vs_r66_public_al_prefix_identical": "R66 retains the public CRAN AL entry path",
        "cran_111_vs_r66_static_al_solver_identical": "R66 retains the public CRAN AL solver",
        "cran_111_vs_r66_structured_sigmagam_identical": "R66 tail correction is not identical to official CRAN 1.1.1",
        "r65_vs_r66_structured_sigmagam_identical": "R66 changed the R65 structured scale-skewness helper",
        "r65_custom_engine_absent_from_cran": "R65 exact-chunked QDESN engine is fork-only",
        "r65_exact_chunking_absent_from_cran": "R65 exact chunking is not a CRAN public capability",
        "r66_custom_engine_absent_from_cran": "R66 exact-chunked QDESN engine is fork-only",
        "r66_exact_chunking_absent_from_cran": "R66 exact chunking is not a CRAN public capability",
    }
    return pd.DataFrame([
        {
            "comparison": name,
            "observed": bool(value),
            "meaning": explanations[name],
            "supports_no_version_only_al_refit": name.startswith("cran_110_vs_111") and bool(value),
        }
        for name, value in comparisons.items()
    ])


def run(args: argparse.Namespace) -> dict:
    output = prepare_output(args.output_dir, args.force)
    cran110_tarball = ensure_tarball(
        args.cran110_tarball, CRAN110_URL, CRAN110_SHA256, args.download_if_missing
    )
    cran111_tarball = ensure_tarball(
        args.cran111_tarball, CRAN111_URL, CRAN111_SHA256, args.download_if_missing
    )

    r62 = pd.read_csv(args.r62_authority)
    r62_summary = json.loads(args.r62_summary.read_text())
    r65_summary = json.loads(args.r65_summary.read_text())
    r65_reuse = pd.read_csv(args.r65_reuse_manifest)
    runtime_manifest_path = args.cran111_library / "pricefm_r67_cran111_install_manifest.json"
    runtime_manifest = None
    if args.run_numerical_probes:
        if not runtime_manifest_path.is_file():
            raise FileNotFoundError(runtime_manifest_path)
        runtime_manifest = json.loads(runtime_manifest_path.read_text())
        installed_source = runtime_manifest.get("source_tarball", {})
        if (
            runtime_manifest.get("status") != "installed_exact_cran_exdqlm_1.1.1"
            or installed_source.get("sha256") != CRAN111_SHA256
            or runtime_manifest.get("fork_source_used") is not False
        ):
            raise RuntimeError("CRAN 1.1.1 runtime manifest failed chain-of-custody checks")
    if (
        len(r62) != args.expected_r62_cases
        or r62_summary.get("matched_cells") != args.expected_r62_cases
    ):
        raise RuntimeError(
            f"Stage-R62 is not a complete {args.expected_r62_cases}-case authority"
        )
    if r65_summary.get("status") != "scientifically_stopped_mechanism_failure":
        raise RuntimeError("Stage-R65 closeout status is not frozen as a mechanism failure")
    if r65_summary.get("valid_al_fit_checkpoints") != args.expected_r65_valid_al:
        raise RuntimeError("Stage-R65 valid AL checkpoint count changed")
    if r65_summary.get("valid_exal_fit_checkpoints") != args.expected_r65_valid_exal:
        raise RuntimeError("Stage-R65 valid exAL checkpoint count changed")
    if not r62["selection_split"].astype(str).str.lower().eq("val").all():
        raise RuntimeError("Stage-R62 authority is not validation-selected")
    if bool_series(r62, "test_opened").any() or bool(r62_summary.get("test_opened")):
        raise RuntimeError("Stage-R62 test firewall is open")

    with tempfile.TemporaryDirectory(prefix="pricefm-r67-source-") as source_tmp:
        source_tmp = Path(source_tmp)
        cran110_source = safe_extract(cran110_tarball, source_tmp / "cran110")
        cran111_source = safe_extract(cran111_tarball, source_tmp / "cran111")
        source_contract_path = output / "pricefm_stage_r67_source_contract.json"
        source_contract = run_json([
            "Rscript", str(args.source_contract_script), str(cran110_source),
            str(cran111_source), str(args.r65_source), str(args.r66_source),
            str(source_contract_path),
        ], source_contract_path)

    numerical = {
        "performed": False,
        "cran_110_vs_111_exact": None,
        "fork_custom_vs_cran111_prediction_max_abs": None,
        "fork_custom_engine_equivalent_to_cran111": False,
    }
    if args.run_numerical_probes:
        with tempfile.TemporaryDirectory(prefix="pricefm-r67-cran110-library-") as library_tmp:
            cran110_library = Path(library_tmp)
            install_audit_library(
                cran110_tarball,
                cran110_library,
                output / "pricefm_stage_r67_cran110_audit_install.log",
            )
            probe110 = probe_cran(
                args.cran_probe_script,
                cran110_library,
                "1.1.0",
                output / "pricefm_stage_r67_cran110_al_rhsns_probe.json",
            )
        probe111 = probe_cran(
            args.cran_probe_script,
            args.cran111_library,
            "1.1.1",
            output / "pricefm_stage_r67_cran111_al_rhsns_probe.json",
        )
        probe_fork_result = probe_fork(
            args.fork_probe_script,
            args.r65_library,
            output / "pricefm_stage_r67_r65_fork_al_rhsns_probe.json",
        )
        difference = max_abs_difference(probe111["prediction"], probe_fork_result["prediction"])
        qbeta_difference = max_abs_difference(probe111["qbeta_m"], probe_fork_result["qbeta_m"])
        official_sigma_mean = sum(numeric_vector(probe111["samp_sigma"])) / len(
            numeric_vector(probe111["samp_sigma"])
        )
        numerical = {
            "performed": True,
            "cran_110_vs_111_exact": exact_probe_equal(probe110, probe111),
            "cran_110_vs_111_prediction_max_abs": max_abs_difference(
                probe110["prediction"], probe111["prediction"]
            ),
            "fork_custom_vs_cran111_prediction_max_abs": difference,
            "fork_custom_vs_cran111_qbeta_max_abs": qbeta_difference,
            "fork_custom_sigma": float(probe_fork_result["sigma"]),
            "cran111_public_sampled_sigma_mean": official_sigma_mean,
            "fork_custom_engine_equivalent_to_cran111": difference <= 1e-12,
            "probe_design": "deterministic_public_AL_RHS_NS_tau_0.25_tau0_1e-3",
        }

    launch_status = pd.read_csv(args.r66_launch_status) if args.r66_launch_status.is_file() else pd.DataFrame()
    r66_status_paths = sorted(args.r66_run_dir.glob("*/model/components/tau=*/exal_status.json"))
    r66_statuses = [json.loads(path.read_text()) for path in r66_status_paths]
    r66_converged = sum(bool(row.get("converged")) for row in r66_statuses)
    r66_eligible = sum(
        bool(row.get("converged")) and bool(row.get("structured_telemetry_pass"))
        for row in r66_statuses
    )
    processes = active_r66_processes()
    if len(launch_status) != args.expected_r66_launch_rows:
        raise RuntimeError("Stage-R66 launch-row count changed")
    selected_counts = r62["selected_seven_quantile_family"].value_counts().to_dict()
    valid_al = int(bool_series(r65_reuse, "reuse_al_fit_authorized").sum())

    comparisons = source_rows(source_contract)
    comparisons.to_csv(output / "pricefm_stage_r67_source_equivalence.csv", index=False)
    decisions = pd.DataFrame([
        {
            "artifact_class": "R62_complete_seven_quantile_authority",
            "count": len(r62),
            "decision": "retain_as_authoritative_historical_surface",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "Complete validation-selected 114-case authority already exists.",
        },
        {
            "artifact_class": "R62_selected_AL_cases",
            "count": int(selected_counts.get("al", 0)),
            "decision": "retain_with_original_engine_provenance",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "The 1.1.0-to-1.1.1 public AL/RHS code did not change; historical engine identity remains explicit.",
        },
        {
            "artifact_class": "R62_selected_legacy_exAL_cases",
            "count": int(selected_counts.get("exal", 0)),
            "decision": "retain_with_original_engine_provenance",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "They remain the frozen comparator; R65/R66 did not produce a valid replacement.",
        },
        {
            "artifact_class": "R65_hash_valid_AL_checkpoints",
            "count": valid_al,
            "decision": "retain_as_legacy_diagnostic_or_declared_warm_start_only",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "Fork-only QDESN engine is absent from CRAN and is not numerically identical to the public engine.",
        },
        {
            "artifact_class": "R65_structured_exAL_checkpoints",
            "count": int(r65_summary.get("valid_exal_fit_checkpoints", 0)),
            "decision": "exclude_from_selection_and_promotion",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "Frozen mechanism failure; no structured winner.",
        },
        {
            "artifact_class": "R66_corrected_exAL_checkpoints",
            "count": len(r66_statuses),
            "decision": "exclude_incomplete_failed_gate",
            "refit_required_now": False,
            "may_relabel_as_cran111": False,
            "reason": "Only a partial gate case exists and the runner terminated with invalid xi scale/sign.",
        },
        {
            "artifact_class": "future_new_PriceFM_fits",
            "count": 0,
            "decision": "require_exact_CRAN_1.1.1_public_API",
            "refit_required_now": False,
            "may_relabel_as_cran111": True,
            "reason": "The immutable CRAN runtime and adapter are now the forward authority.",
        },
    ])
    decisions.to_csv(output / "pricefm_stage_r67_artifact_reuse_decisions.csv", index=False)

    version_equivalence = bool(source_contract.get("version_only_al_rhs_reuse_supported"))
    numeric_equivalence = bool(numerical.get("cran_110_vs_111_exact")) if numerical["performed"] else True
    custom_divergence = (
        not bool(numerical.get("fork_custom_engine_equivalent_to_cran111"))
        if numerical["performed"] else bool(source_contract["comparisons"]["r65_custom_engine_absent_from_cran"])
    )
    gates = pd.DataFrame([
        {"gate": "R62_complete_authority", "required": True, "passed": len(r62) == args.expected_r62_cases},
        {"gate": "R62_validation_only_selection", "required": True, "passed": r62["selection_split"].astype(str).str.lower().eq("val").all()},
        {"gate": "CRAN_1.1.0_to_1.1.1_AL_RHS_source_identity", "required": True, "passed": version_equivalence},
        {"gate": "CRAN_1.1.0_to_1.1.1_AL_RHS_numerical_identity", "required": bool(numerical["performed"]), "passed": numeric_equivalence},
        {"gate": "CRAN_1.1.1_runtime_chain_of_custody", "required": bool(numerical["performed"]), "passed": runtime_manifest is not None},
        {"gate": "historical_custom_engine_not_relabelled_as_CRAN", "required": True, "passed": custom_divergence},
        {"gate": "R65_exAL_remains_excluded", "required": True, "passed": r65_summary.get("completed_case_structured_winners") == 0},
        {"gate": "R66_not_running", "required": True, "passed": len(processes) == 0},
        {"gate": "test_firewall_closed", "required": True, "passed": not bool_series(r62, "test_opened").any() and not bool(r62_summary.get("test_opened"))},
        {"gate": "broad_refit_not_authorized", "required": True, "passed": True},
        {"gate": "registry_and_article_mutation_blocked", "required": True, "passed": True},
        {"gate": "launch_YAML_absent", "required": True, "passed": not any(output.rglob("*.yaml")) and not any(output.rglob("*.yml"))},
    ])
    gates.to_csv(output / "pricefm_stage_r67_decision_gates.csv", index=False)
    if not gates.loc[gates.required, "passed"].all():
        raise RuntimeError(f"R67 decision gates failed: {gates.loc[gates.required & ~gates.passed].to_dict('records')}")

    summary = {
        "status": "completed_cran111_authority_transition_no_broad_refit",
        "recommended_action": "retain_R62_and_use_exact_CRAN_1.1.1_only_for_future_new_fits",
        "r62_authority_cases": len(r62),
        "r62_selected_family_counts": {str(k): int(v) for k, v in selected_counts.items()},
        "r65_valid_al_checkpoints": valid_al,
        "r65_exal_checkpoints_excluded": int(r65_summary.get("valid_exal_fit_checkpoints", 0)),
        "r66_launch_rows": len(launch_status),
        "r66_exal_components_present": len(r66_statuses),
        "r66_exal_components_converged": r66_converged,
        "r66_exal_components_eligible": r66_eligible,
        "r66_active_processes": processes,
        "cran_110_vs_111_public_al_rhs_source_identical": version_equivalence,
        "cran_110_vs_111_structured_exal_identical": bool(
            source_contract["comparisons"]["cran_110_vs_111_structured_sigmagam_identical"]
        ),
        "cran111_vs_r66_corrected_structured_exal_identical": bool(
            source_contract["comparisons"]["cran_111_vs_r66_structured_sigmagam_identical"]
        ),
        "numerical_equivalence": numerical,
        "historical_custom_engine_may_be_relabelled_as_cran111": False,
        "existing_authority_refit_required": False,
        "new_fit_package_authority": "exact_CRAN_exdqlm_1.1.1_public_API",
        "cran111_runtime_manifest": str(runtime_manifest_path.resolve()) if runtime_manifest else None,
        "cran111_runtime_manifest_sha256": sha256(runtime_manifest_path) if runtime_manifest else None,
        "launch_authorized": False,
        "test_opened": False,
        "registry_mutation_authorized": False,
        "article_mutation_authorized": False,
    }
    write_json(output / "summary.json", summary)

    report = f"""# PriceFM Stage-R67 CRAN 1.1.1 authority and reuse audit

## Executive decision

Do not rerun the complete PriceFM surface merely to move from CRAN exdqlm
1.1.0 to 1.1.1. The official RHS/RHS-NS source, public reduced-AL dispatch, and
static AL CAVI solver are identical, and the deterministic AL/RHS-NS probe is
exactly equal across those releases. Stage-R62 therefore remains the complete
114-region/fold historical authority.

This conclusion is deliberately limited to the reduced AL/RHS-NS path. CRAN
1.1.1 adds a structured exAL scale-skewness block, and R66 used a later
fork-only tail-moment correction that is not byte-identical to CRAN 1.1.1.
Those facts justify precise provenance for old exAL work and the official
1.1.1 boundary for future fits; they do not justify repeating the frozen R62
surface when neither R65 nor R66 produced a promotable replacement.

This decision does not relabel historical exact-chunked fits as CRAN fits. The
R65 QDESN engine is fork-only and its deterministic predictions differ from the
public CRAN engine by a maximum absolute value of
`{numerical.get('fork_custom_vs_cran111_prediction_max_abs')}` in the audit
probe. Old results retain their original method and package provenance.

## Frozen state

| Item | Value |
|---|---:|
| R62 authority cases | {len(r62)} |
| R62 AL selections | {int(selected_counts.get('al', 0))} |
| R62 legacy exAL selections | {int(selected_counts.get('exal', 0))} |
| R65 reusable AL checkpoints | {valid_al} |
| R65 excluded exAL checkpoints | {int(r65_summary.get('valid_exal_fit_checkpoints', 0))} |
| R66 exAL components present | {len(r66_statuses)} |
| R66 converged / eligible | {r66_converged} / {r66_eligible} |
| Active R66 processes | {len(processes)} |

## Forward package boundary

Every new PriceFM fit must use the exact CRAN 1.1.1 tarball with SHA-256
`{CRAN111_SHA256}`, an isolated library marked `Repository: CRAN`, and only
the public `exalStaticLDVB()` API. Fork-only wrappers, exact-chunking claims,
and private namespace calls are prohibited in new fits.

The R67 adapter preserves case-specific DESN matrices, RHS-NS `tau0`, AL/exAL
family, sigma/gamma priors, and validation-only scoring. It intentionally does
not reinterpret old artifacts, open test data, launch models, or mutate the
registry/article.

## Efficient next action

Keep R62 as authority and close R65/R66 as failed optional mechanism work. Do
not launch a replacement campaign automatically. If a future scientific
question justifies a new CRAN-native exAL fit, start with one pre-registered
real case and fit only the newly required components; do not repeat the full AL
surface just because the CRAN patch version changed.
"""
    (output / "pricefm_stage_r67_cran111_rhs_reuse_report.md").write_text(report)

    source_paths = [
        args.r62_authority, args.r62_summary, args.r65_summary,
        args.r65_reuse_manifest, args.source_contract_script,
        args.cran_probe_script, args.fork_probe_script,
        Path(__file__).resolve(), cran110_tarball, cran111_tarball,
        args.code_root / "application/scripts/pricefm/materialize_pricefm_stage_r67_cran111_package.py",
        args.code_root / "application/scripts/pricefm/pricefm_stage_r67_cran111_adapter.R",
        args.code_root / "application/tests/test_pricefm_stage_r67_cran111_transition.py",
        args.code_root / "application/tests/test_pricefm_stage_r67_cran111_adapter.R",
        args.code_root / "docs/implementation_notes/pricefm_stage_r67_cran111_authority_reuse_20260830.md",
    ]
    if runtime_manifest_path.is_file():
        source_paths.append(runtime_manifest_path)
    if args.r66_launch_status.is_file():
        source_paths.append(args.r66_launch_status)
    source_paths.extend(r66_status_paths)
    source_manifest = pd.DataFrame([
        {"path": str(Path(path).resolve()), "sha256": sha256(Path(path)), "bytes": Path(path).stat().st_size}
        for path in dict.fromkeys(source_paths) if Path(path).is_file()
    ])
    source_manifest.to_csv(output / "source_manifest.csv", index=False)
    return summary


def main() -> int:
    print(json.dumps(run(parser().parse_args()), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
