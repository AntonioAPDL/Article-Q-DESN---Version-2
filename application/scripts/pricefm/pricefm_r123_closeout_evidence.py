"""Evidence-only validation; no fitting, scoring, or parent writes."""
from __future__ import annotations

import math
from pathlib import Path

import pricefm_r123_recovery as REC


RECEIPT_FILES = ("source_identity.json", "cadence_audit.json", "parent_evidence.json", "terminal.json")


def active_fit_processes(campaign, prep, proc=Path("/proc")):
    writers = []
    roots = (str(Path(campaign).resolve()) + "/", str(Path(prep).resolve()) + "/")
    for entry in proc.iterdir():
        if not entry.name.isdigit(): continue
        try:
            argv = (entry / "cmdline").read_bytes().decode().split("\0")
        except (OSError, UnicodeError):
            continue
        if not argv or Path(argv[0]).name not in ("R", "Rscript"): continue
        if (any(name in arg for arg in argv for name in
                ("420_fit_pricefm_stage_r121_quantile_atom.R", "442_fit_pricefm_stage_r123_certified_normal.R"))
                and any(arg.startswith(roots) for arg in argv)):
            writers.append(int(entry.name))
    return sorted(writers)


def finish_receipt(output):
    output = Path(output)
    REC.verify_evidence(REC.read(output / "parent_evidence.json"))
    REC.verify_evidence(REC.read(output / "cadence_audit.json"))
    expected = {str(output / name): REC.digest(output / name) for name in RECEIPT_FILES}
    ledger = output / "completed_evidence.json"
    if ledger.exists():
        value = REC.read(ledger)
        if value["evidence_sha256"] != expected:
            raise RuntimeError("completed receipt closure differs")
        REC.verify_evidence(value)
    else:
        # A crash after terminal installation is recoverable only from the
        # previously frozen, still matching parent evidence, never a new hash.
        REC.immutable(ledger, dict(evidence_sha256=expected))
    return REC.read(output / "terminal.json")


def authorized_ladders(root):
    value = REC.read(Path(root) / "al_launch_authorization.json")
    if (value.get("test_opened") is not False or value.get("independent_al_authorized") is not True
            or any(value.get(name) is not False for name in
                ("exal_authorized", "joint_authorized", "mcmc_authorized"))):
        raise RuntimeError("AL authorization scope differs")
    selected = value["selected"]
    if len(selected) != 3 or len({row["candidate_id"] for row in selected}) != 3:
        raise RuntimeError("AL authorization must contain three distinct structures")
    expected = {}
    for row in selected:
        candidate = row["candidate_id"]
        if not candidate or Path(candidate).name != candidate or candidate in (".", ".."):
            raise RuntimeError("invalid authorized candidate path")
        tau0 = float(row["tau0"])
        if not math.isfinite(tau0) or tau0 <= 0:
            raise RuntimeError("invalid authorized global scale")
        for split in (1, 2, 3):
            expected[(candidate, split)] = tau0
    return expected


def verified_atom(args, m, control, root, candidate, split, tau0, tau, normal, *, companion=False):
    parent_tau = m.B.PARENT[tau]
    parent = normal if parent_tau is None else root / f"quantiles/al/tau={parent_tau:.2f}"
    cap = int(control["al_companion_max_iter"] if companion else control["al_final_max_iter"])
    atom = root / (f"companions/cap={cap}/tau={tau:.2f}" if companion else f"quantiles/al/tau={tau:.2f}")
    contract = root / (f"contracts/companions/tau={tau:.2f}.json" if companion else f"contracts/final/tau={tau:.2f}.json")
    expected = m.quantile_contract(args.parent_prep, control, candidate, split, tau, tau0,
        root / "design", parent, "normal_rhs" if parent_tau is None else "quantile", atom, cap)
    if REC.read(contract) != expected:
        raise RuntimeError("AL contract differs from independently reconstructed authorization")
    if not m.quantile_valid(atom, expected["posterior_target_sha256"]):
        raise RuntimeError("AL output target/hash differs from authorized contract")
    terminal = REC.read(atom / "terminal.json")
    for name in ("atom_id", "tag", "stage", "readout", "family", "fold", "split", "tau", "tau0"):
        if terminal.get(name) != expected[name]:
            raise RuntimeError(f"AL terminal identity differs: {name}")
    if (terminal.get("initialization_only") is not True
            or any(terminal.get(name) is not False for name in
                ("prior_center_from_initializer", "initializer_changes_prior", "test_opened",
                 "registry_mutated", "article_mutated", "joint_model_fitted", "mcmc_fitted", "exal_fitted"))
            or terminal.get("package_version") != "1.1.1"
            or terminal.get("package_repository") != "CRAN"):
        raise RuntimeError("AL prior/API/scope declaration differs")
    return REC.read(atom / "diagnostics.json")


def audit_ladder(args, m, control, path, expected, rows):
    root = path.parent
    key = (root.parent.name, int(root.name.removeprefix("split=")))
    if key not in expected:
        raise RuntimeError("unexpected AL ladder outside frozen authorization")
    candidate, split = key
    tau0 = expected[key]
    value = REC.read(path)
    if (value.get("candidate_id") != candidate or value.get("split") != split
            or value.get("tau0") != tau0 or value.get("test_opened") is not False):
        raise RuntimeError("AL ladder identity differs from frozen authorization")
    matched = [r for r in rows if r["candidate_id"] == candidate and int(r["split"]) == split
        and math.isclose(float(r["tau0"]), tau0, rel_tol=1e-10, abs_tol=0)]
    if len(matched) != 1 or not m.normal_valid(matched[0]["output_dir"]):
        raise RuntimeError("AL ladder lacks a unique certified Normal initializer")
    accepted = value["accepted_quantiles"]
    levels = [float(q["tau"]) for q in accepted]
    order = list(m.B.QUANTILE_ORDER)
    if not levels or levels != order[:len(levels)]:
        raise RuntimeError("AL levels are duplicated, missing, or not in the frozen nested order")
    if value["eligible"] and (levels != order or not all(q["accepted"] is True for q in accepted)
            or value.get("score_scope") != "fold1_training_internal_validation_only"):
        raise RuntimeError("eligible ladder lacks seven accepted levels in the declared scope")
    for q in accepted:
        tau = float(q["tau"])
        diagnostics = verified_atom(args, m, control, root, candidate, split, tau0, tau,
            Path(matched[0]["output_dir"]))
        raw = diagnostics["external_gate_passed"]
        if q["raw_external_gate_passed"] is not raw:
            raise RuntimeError("AL raw acceptance contradicts saved diagnostics")
        method = q["acceptance_method"]
        if method == "raw_external_gate":
            if q["accepted"] is not raw:
                raise RuntimeError("AL raw acceptance was relabelled")
        elif method == "paired_cap_fitted_function_gate_v1":
            if raw: raise RuntimeError("unnecessary AL cap companion")
            verified_atom(args, m, control, root, candidate, split, tau0, tau,
                Path(matched[0]["output_dir"]), companion=True)
            pair = REC.read(root / f"paired_cap/tau={tau:.2f}.json")
            if q["accepted"] is not pair["passed"] or q["pair_classification"] != pair["classification"]:
                raise RuntimeError("AL cap acceptance contradicts saved score-blind gate")
        else:
            raise RuntimeError("unknown AL acceptance method")
    return value
