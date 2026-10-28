"""Metadata-only FI/DK2 cost-panel plans; no execution is authorized here.

The current HB controller admits environment and EE TEST parity only. These
plans preserve the canonical 506 schedule and complete provenance allowlists
while remaining NOT_ADMITTED until fresh positive proofs and a new regional
finite authority pass the implemented cost controller's admission checks.
"""
from __future__ import annotations

import argparse
import ast
import collections
import hashlib
import json
from pathlib import Path
import uuid

from .fixture import DATA, TRACKERS, SOURCE_PINS, digest, fingerprint, write_json

SCHEMA = "r156_hb_cost_panel_plan_v1"
CONFIGS = {
    "FI": TRACKERS / "worktrees/pricefm_r152_parallel_20261024/application/config/pricefm_stage_r152_fi_20261024.json",
    "DK2": TRACKERS / "worktrees/pricefm_r151_retirement_aware_20261023/application/config/pricefm_stage_r151_retirement_aware_region_20261023.json",
}
SOURCE_HEADS = {"FI": "cba0b6c861f20ebdffcd970d59b0fa38afd80a42", "DK2": "57f9bc8931b67fbafd68c894599ac7c0ca519fab"}
COUNTS = {"FI": dict(packages=20, geometries=19, parents=60, tasks=240, D=60, S0=9, maximum=87),
    "DK2": dict(packages=21, geometries=20, parents=63, tasks=252, D=63, S0=9, maximum=90)}
BENCHMARK_PACKAGES = {
    "FI": ["C0", "r134_75c4492b5ef11634", "r134_819baf69f92b36e7", "r134_8f8f3beb4b5a3c42"],
    "DK2": ["C0", "r134_63c759406920cd63", "r134_6a0e5dfa466ab98c", "r134_5240ecffd2394d15"],
}
REQUIRED_GATES = ["EE_complete_disposition_delivered_and_drained", "HB_scientific_parity_sealed_and_accepted",
    "Python_runtime_attested", "cost_panel_runtime_bridge_reviewed_and_tested", "fresh_cross_server_no_overlap_claim",
    "new_region_specific_1200CPU_1200wall_authority", "current_account_memory_disk_calendar_admission"]
LIMITS = dict(cpus=1, numerical_threads=1, concurrent_jobs=1, wall_seconds=1200, aggregate_cpu_seconds=1200,
    include_all_parent_preflight=True, include_setup_imports_context_serialization_cleanup=True,
    automatic_retry=False, incomplete_panel_admits_science=False, new_AQL=False, scientific_selection=False,
    new_fits=0, posterior_updates=0, official_origins=0, automatic_prefix_admission=False)


def read_metadata(path):
    path = Path(path)
    if path.suffix != ".json" or path.stat().st_size > 16 * 1024 * 1024:
        raise ValueError("bounded JSON metadata required")
    return json.loads(path.read_text())


def method_pin(path, class_name, method_name):
    """Inspect a method AST without importing or compiling its source."""
    tree = ast.parse(Path(path).read_text())
    classes = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == class_name]
    methods = [n for n in classes[0].body if isinstance(n, ast.FunctionDef) and n.name == method_name] if len(classes) == 1 else []
    if len(methods) != 1 or methods[0].decorator_list:
        raise ValueError("one canonical undecorated method required")
    node = methods[0]
    return dict(source=str(path), source_sha256=digest(path), entry=class_name + "." + method_name,
        ast_sha256=hashlib.sha256(ast.dump(node, include_attributes=False).encode()).hexdigest(),
        first_line=node.lineno, last_line=node.end_lineno)


def validate_metadata(study, config, preparation):
    if study not in COUNTS:
        raise ValueError("only FI and canonical DK2 plans are supported")
    expected = COUNTS[study]
    region = "FI" if study == "FI" else "DK_2"
    if (preparation["source"]["head"] != SOURCE_HEADS[study] or config["region"] != region or preparation["region"] != region
            or len(preparation["packages"]) != expected["packages"] or len(preparation["tasks"]) != expected["tasks"]
            or len({p["candidate_id"] for p in preparation["packages"]}) != expected["geometries"]
            or config["control"] != "C0" or preparation["control"] != "C0"):
        raise ValueError("canonical scientific lineage/package universe differs")
    if (config["benchmark_D_packages"] != BENCHMARK_PACKAGES[study] or config["benchmark_S_packages"] != BENCHMARK_PACKAGES[study]
            or config["benchmark_D_repeats"] != 3 or config["benchmark_S_repeats"] != 1
            or config["benchmark_max_seconds"] != 1200 or config.get("benchmark_CPU_seconds", 1200) != 1200
            or config["chunk_origins"] != 8 or config["clock_offsets_steps"] != [0, 24, 48, 72]
            or config["horizon_steps"] != 96 or config["paths"] != 100
            or config["quantiles"] != [.1, .25, .45, .5, .55, .75, .9]):
        raise ValueError("exact 18-call H96/7-quantile/100-path benchmark protocol differs")
    if any(config.get(key) is not False for key in ("AL_authorized", "official_evaluation_authorized", "promotion_authorized", "test_used_for_selection")):
        raise ValueError("cost-only preparation cannot authorize scientific expansion")
    if preparation["test_opened"] is not False or preparation["posterior_updated"] is not False or preparation["new_model_fits"] != 0:
        raise ValueError("training-only cached Normal preparation required")
    keys = [(t["package_id"], t["split"], t["mode"], t["seed_index"]) for t in preparation["tasks"]]
    if len(keys) != len(set(keys)):
        raise ValueError("duplicate canonical task key")


def first_descriptor(task):
    offset = task["clock_offsets_steps"][0]
    positions = task["daily_origin_positions"][:8]
    timestamps = task["origin_timestamps"][str(offset)][:8]
    if offset != 0 or len(positions) != 8 or len(timestamps) != 8 or len(set(positions)) != 8:
        raise ValueError("complete canonical first eight-origin midnight chunk required")
    return dict(name="clock00_part000", clock_offset_steps=0, origin_positions=positions,
        origin_timestamps=timestamps, stable_rng_origin_keys=[p * 96 for p in positions])


def make_schedule(study, config, preparation):
    """Exact original 506 loop order, including both immediate C0 replays."""
    by = {(t["package_id"], t["split"], t["mode"], t["seed_index"]): t for t in preparation["tasks"]}
    schedule = []
    row = 0
    for mode in ("D", "S"):
        for package in config["benchmark_" + mode + "_packages"]:
            task = by[package, 3, mode, 0]
            descriptor = first_descriptor(task)
            context_id = mode + ":" + package + ":split3"
            for repetition in range(config["benchmark_" + mode + "_repeats"]):
                row += 1
                base = dict(task=task["name"], task_sha256=fingerprint(task), scientific_identity_sha256=task["scientific_identity_sha256"],
                    package_id=package, candidate_id=task["candidate_id"], p=task["p"], mode=mode, split=3, seed_index=0,
                    forecast_seed=task["forecast_seed"], region=task["region"], repetition=repetition, descriptor=descriptor,
                    context_id=context_id, source_call="Study.predict -> original502.predict -> original kernel492/core.normal_predictions",
                    seed_derivation=dict(function="runtime.BASE.deterministic_seed", region_arguments=[task["forecast_seed"], task["region"], 3],
                        clock_arguments=["derived_regional_seed", "clock", 0]))
                schedule.append(dict(base, sequence=len(schedule) + 1, kind="timed_prediction", timed_row=row,
                    cold_context_before_call=repetition == 0, warm_repeat_equal_previous=repetition > 0,
                    serialization=dict(compute_loss=False, zero_origin_AQL=True, retained_packet=mode + "_" + package + "_" + str(repetition) + ".npz")))
                if package == "C0" and repetition == 0:
                    schedule.append(dict(base, sequence=len(schedule) + 1, kind="control_replay", timed_row=None,
                        cold_context_before_call=False, source_call="original506.Study.legacy_control_replay",
                        reference_to_prediction_sequence=len(schedule), comparison="bitwise" if mode == "S" else "atol1e-12_rtol1e-10",
                        new_candidate_AQL=False))
    if len(schedule) != 18 or row != 16 or collections.Counter(e["kind"] for e in schedule) != {"timed_prediction": 16, "control_replay": 2}:
        raise ValueError("incomplete original 18-call schedule")
    return schedule


def make_preflight(preparation):
    by = {(t["package_id"], t["split"], t["mode"], t["seed_index"]): t for t in preparation["tasks"]}
    rows = []
    for package in preparation["packages"]:
        for split in (1, 2, 3):
            task = by[package["package_id"], split, "D", 0]
            rows.append(dict(sequence=len(rows) + 1, task=task["name"], task_sha256=fingerprint(task),
                package_id=task["package_id"], candidate_id=task["candidate_id"], split=split, p=task["p"],
                parent_task=task["parent_task"], parent_fit=task["parent_fit"], parent_seal_sha256=task["parent_seal_sha256"],
                scaler_path=task["scaler_path"], scaler_sha256=task["scaler_sha256"], bank=task["bank"],
                covariance_bytes=8 * task["p"] ** 2,
                parent_input_sha256=task["parent_input_sha256"],
                checks=["exact cohort and training scaler", "mean/covariance dimensions and finiteness", "symmetry_rtol1e-10_atol1e-12_times_scale",
                    "eigvalsh_minimum_at_least_minus1e-10_times_scale", "nonnegative_covariance_diagonal", "positive_finite_omega_shape_and_rate"],
                forecasts=0, new_model_fits=0, included_in_whole_1200CPU_1200wall=True))
    return rows


def make_allowlist(config_path, prep_path, config, preparation):
    """Union all original ledgers; stat files, but never read numerical bytes."""
    entries = {}
    def add(path, sha, membership, metadata_verified=False):
        path = str(path)
        if path in entries:
            if entries[path]["sha256"] != sha:
                raise ValueError("conflicting original allowlist digest")
            entries[path]["memberships"].append(membership)
            if metadata_verified:
                entries[path]["verification"] = "METADATA_BYTES_HASH_VERIFIED"
            return
        target = Path(path)
        exists = target.is_file()
        entries[path] = dict(sha256=sha, bytes=target.stat().st_size if exists else None, exists=exists,
            staged_relative_path=str(Path("files") / target.relative_to("/")), memberships=[membership],
            verification="METADATA_BYTES_HASH_VERIFIED" if metadata_verified else "ORIGINAL_LEDGER_SHA_ONLY_NOT_REHASHED",
            opaque_provenance=target.suffix.lower() == ".rds")
    for ledger_name in ("source_sha256", "input_sha256"):
        for path, sha in preparation[ledger_name].items():
            add(path, sha, ledger_name)
    for task in preparation["tasks"]:
        for path, sha in task["parent_input_sha256"].items():
            if path not in entries:
                add(path, sha, "task_parent_input_sha256")
            elif entries[path]["sha256"] != sha:
                raise ValueError("task parent digest conflicts with preparation ledger")
        add(task["scaler_path"], task["scaler_sha256"], "scaler")
    for bank in preparation["banks"].values():
        add(bank["path"], bank["sha256"], "training_bank")
    add(config_path, digest(config_path), "original_config", True)
    add(prep_path, digest(prep_path), "original_preparation", True)
    for role, (path, sha) in SOURCE_PINS.items():
        if digest(path) != sha:
            raise ValueError("canonical Python call source changed: " + role)
        add(path, sha, "canonical_forecast_call_source", True)
    # The parent preparation is metadata, not a requirement for R execution.
    if digest(config["parent_preparation"]) != config["parent_preparation_sha256"]:
        raise ValueError("canonical parent preparation changed")
    add(config["parent_preparation"], config["parent_preparation_sha256"], "original_parent_preparation", True)
    for entry in entries.values():
        entry["memberships"] = sorted(set(entry["memberships"]))
    return dict(sorted(entries.items()))


def allowlist_summary(assets):
    extensions = {}
    for logical, entry in assets.items():
        extension = Path(logical).suffix.lower() or "<none>"
        group = extensions.setdefault(extension, dict(files=0, bytes=0))
        group["files"] += 1
        group["bytes"] += entry["bytes"] or 0
    return dict(files=len(assets), bytes=sum(e["bytes"] or 0 for e in assets.values()),
        missing_files=[p for p, e in assets.items() if not e["exists"]], extensions=extensions,
        numerical_bytes_rehashed=False, bytes_staged=0, all_original_ledger_members_retained=True,
        RDS_policy="opaque bytes retained and hash verified at future staging; never parsed by cached Normal forecast")


def controller_handoff():
    """Explicit operator steps; emitting a plan never executes these commands."""
    prefix = ["python", "-B", "-m", "pricefm_hb.cost_control"]
    return dict(status="IMPLEMENTED_AND_MOCK_TESTED_REQUIRES_FRESH_ADMISSION", automatic_execution=False,
        commands=[
            dict(step="validate_positive_gates_and_prepare", argv=prefix + ["prepare-launch", "--plan", "<sealed-plan.json>",
                "--request", "<fresh-positive-cost-request.json>", "--config", "<reviewed-site-config.json>", "--destination", "<new-release-directory>"]),
            dict(step="claim_and_submit_held", argv=prefix + ["submit-held", "--release", "<new-release-directory>", "--config", "<reviewed-site-config.json>"]),
            dict(step="issue_new_job_bound_authority", argv=prefix + ["issue-authority", "--key", "<claim-task-key>", "--config", "<reviewed-site-config.json>"]),
            dict(step="release_explicitly_authorized_held_job", argv=prefix + ["release-job", "--key", "<claim-task-key>", "--config", "<reviewed-site-config.json>"]),
            dict(step="record_terminal_accounting", argv=prefix + ["status", "--key", "<claim-task-key>", "--config", "<reviewed-site-config.json>", "--receipt", "<new-status.json>"]),
            dict(step="collect_and_verify_cost_only_outputs", argv=prefix + ["collect", "--key", "<claim-task-key>", "--config", "<reviewed-site-config.json>",
                "--receipt", "<new-status.json>", "--incoming", "<fresh-incoming-directory>", "--destination", "<new-cost-publication-directory>"])] )


def feasibility(source):
    methods = {name: method_pin(source, "Study", name) for name in ("benchmark", "numeric_preflight", "predict", "legacy_control_replay")}
    runtime = Path(__file__).with_name("benchmark.py")
    return dict(status="COST_ONLY_RUNTIME_IMPLEMENTED_NOT_ADMITTED_NOT_SCIENTIFICALLY_QUALIFIED",
        current_r156_adapter="fixed EE TEST fixture; separate future COST_ONLY benchmark CLI",
        runtime_source=dict(path=str(runtime), sha256=digest(runtime)),
        adapter_sources={name: digest(Path(__file__).with_name(name)) for name in
            ("benchmark.py", "benchmark_plan.py", "science.py", "fixture.py", "environment.py")},
        runtime_entrypoint="python -B -m pricefm_hb.benchmark",
        cost_controller_source=dict(path=str(Path(__file__).with_name("cost_control.py")), sha256=digest(Path(__file__).with_name("cost_control.py"))),
        cost_controller_role_implemented=True, cost_authority_issuer_implemented=True,
        orchestration_validation="stdlib mocked controller/worker/collection tests passed; regional cost panel not executed",
        prospective_authority_schema="r156_hb_cost_only_authority_v1",
        original_methods=methods, unchanged_method_direct_execution_portable=False,
        reason="Study.benchmark invokes original guard, lease validation, absolute path/source wrappers, prefix pricing and campaign publication; its self/context is tied to the historical host contract.",
        reusable_math="Exact frozen497 context API, original502 predict,492 deterministic kernel, R134 Normal paths, original control replay equations and retained_arrays(compute_loss=False).",
        implemented_bridge=["manifest logical-to-physical resolution and all staged hash checks",
            "exact frozen502 predict/control replay and497 retained_arrays functions in AST-pinned private namespaces",
            "exact506 all-parent numeric_preflight with mapped context and original numerical checks",
            "new cost-only schedule; cold/import/startup/serialization/cleanup and whole wall/CPU accounting",
            "mandatory new COST_ONLY authority, runtime/parity/EE assessment/delivery/drain/cross-server claim evidence"],
        remaining_gates=["pinned review of the final executed source closure and supplied positive gate evidence through cost_control prepare-launch",
            "complete EE delivery and fresh physical drain pins; accepted reference-profile runtime and original-comparison scientific parity seals",
            "complete immutable regional staging, fresh exclusive claim and one new finite region-specific cost authority",
            "actual benchmark runtime qualification and measured full-prefix costs"],
        no_old_guard_removed=True, actual_region_cost_panel_executed=False, no_regional_benchmark_qualification_claim=True)


def build_plan(study, scope_id=None):
    study = "DK2" if study == "DK_2" else study
    config_path = CONFIGS[study]
    config = read_metadata(config_path)
    prep_path = DATA / "launch_prep" / config["tag"] / "preparation.json"
    prep = read_metadata(prep_path)
    validate_metadata(study, config, prep)
    if digest(config_path) != prep["config_sha256"]:
        raise ValueError("canonical configuration digest differs")
    source = SOURCE_PINS["canonical506"][0]
    schedule = make_schedule(study, config, prep)
    preflight = make_preflight(prep)
    if len(preflight) != COUNTS[study]["parents"]:
        raise ValueError("whole-parent preflight coverage differs")
    assets = make_allowlist(config_path, prep_path, config, prep)
    scope_id = scope_id or uuid.uuid4().hex
    if not isinstance(scope_id, str) or not scope_id or any(not c.isalnum() and c not in "_-" for c in scope_id):
        raise ValueError("safe unique planned scope identity required")
    prep_sha = digest(prep_path)
    protocol_sha = fingerprint(dict(config_sha256=prep["config_sha256"], calls=schedule, limits=LIMITS))
    claim_key = "pricefm:cost-panel:" + study + ":" + prep_sha + ":" + protocol_sha
    return dict(schema=SCHEMA, status="METADATA_PLAN_COMPLETE_BENCHMARK_NOT_ADMITTED", study=study, region=config["region"],
        canonical_preparation=dict(path=str(prep_path), sha256=prep_sha, source=prep["source"]),
        canonical_config=dict(path=str(config_path), sha256=prep["config_sha256"]),
        canonical_dependency=dict(root=prep["dependency"], head=prep["dependency_head"]),
        scientific_universe=COUNTS[study], packages=prep["packages"],
        resources=LIMITS, schedule=schedule, all_parent_preflight=preflight,
        schedule_summary=dict(timed_D_calls=12, timed_S_calls=4, control_replay_calls=2, arithmetic_calls=18,
            timed_rows=16, cold_timing_contexts=8, preflight_contexts=len(preflight),
            cost_only=True, AQL_computed=False, selection_performed=False),
        input_allowlist=assets, inventory=allowlist_summary(assets), adapter_feasibility=feasibility(source),
        claim=dict(scientific_exclusion_key=claim_key, planned_attempt_id=scope_id,
            execution_namespace="BENCHMARK_TEST/" + study + "/" + prep_sha[:16] + "/" + scope_id,
            status="UNCLAIMED_NOT_ADMITTED", same_key_across_hosts=True, same_key_across_new_attempt_ids=True,
            prior_failure_requires_explicit_new_authority=True, no_automatic_retry=True),
        launch_manifest=dict(status="NOT_ADMITTED", executable=None, argv=None, staging_authorized=False,
            actual_model_execution_authorized=False, execution_allowed=False, new_authority_issued=False,
            qualification_controller_roles=["environment", "parity"], cost_controller_role_implemented=True,
            cost_controller_roles=["FI_COST_ONLY_BENCHMARK", "DK2_COST_ONLY_BENCHMARK"],
            required_cost_role=study + "_COST_ONLY_BENCHMARK", required_gates=REQUIRED_GATES,
            future_worker_cli=["python", "-B", "-m", "pricefm_hb.benchmark", "--plan", "<sealed-plan-path>",
                "--authority", "<new-COST_ONLY-authority-path>", "--authority-sha256", "<new-authority-SHA256>",
                "--stage-root", "<complete-hash-verified-regional-stage>", "--output-dir", "<BENCHMARK_TEST/study/prep-prefix/" + scope_id + ">"],
            gate_evidence={gate: None for gate in REQUIRED_GATES}),
        cost_controller_handoff=controller_handoff(),
        future_full_prefix_pricing=dict(status="PENDING_REAL_PANEL", candidate_losses_opened=False,
            headroom=1.5, covered_input_maximum_or_explicit_fallback_required=True,
            conservative_delivered_share_required=True, complete_D_and_all_possible_nine_S0_scenarios_required=True,
            maximum_component_replacement_guardian_assessment_drain_calendar_required=True,
            no_scientific_D_or_S0_admitted_by_this_plan=True),
        dependency_scope=dict(Python="3.11 + NumPy/SciPy/pandas/PyYAML/threadpoolctl with recorded native ABI and one-thread pools",
            R_interpreter_required=False, AL_fitter_required=False, RDS_opaque_provenance_required=True),
        next_actions=["Supply complete accepted EE disposition/delivery and fresh physical-drain pins; preserve existing ownership.",
            "Supply the accepted HB reference-profile Python/runtime and original-comparison whole-eight-origin TEST parity seals.",
            "Pin the final executed-source review and submit fresh positive proofs to the implemented cost_control prepare-launch command.",
            "Hash verify/stage this complete allowlist and reserve a fresh exclusive claim through the cost controller.",
            "Submit held, issue a new job-bound region-specific whole1200CPU/1200wall authority and explicitly release that job.",
            "Execute this exact complete panel once; failure/incompletion admits no D and no implicit retry.",
            "Freeze full-prefix prices and calendar before considering a new science admission."])


def write_plan(plan, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    path = destination / (plan["study"] + "_COST_PANEL_NOT_ADMITTED.json")
    if path.exists():
        raise FileExistsError("planned scope already exists; preserve its identity")
    write_json(path, plan)
    path.with_suffix(".sha256").write_text(digest(path) + "\n")
    return path


def dry_run(plan_path):
    path = Path(plan_path)
    if digest(path) != path.with_suffix(".sha256").read_text().strip():
        raise ValueError("cost-panel plan seal differs")
    plan = read_metadata(path)
    if (plan.get("schema") != SCHEMA or plan.get("status") != "METADATA_PLAN_COMPLETE_BENCHMARK_NOT_ADMITTED"
            or plan.get("resources") != LIMITS or plan["launch_manifest"]["status"] != "NOT_ADMITTED"
            or plan["launch_manifest"]["actual_model_execution_authorized"] is not False
            or plan["adapter_feasibility"]["status"] != "COST_ONLY_RUNTIME_IMPLEMENTED_NOT_ADMITTED_NOT_SCIENTIFICALLY_QUALIFIED"
            or len(plan["schedule"]) != 18 or len(plan["all_parent_preflight"]) != COUNTS[plan["study"]]["parents"]):
        raise ValueError("cost-only nonadmission contract differs")
    return dict(status="DRY_RUN_VALID_PLAN_EXECUTION_NOT_ADMITTED", study=plan["study"], plan_sha256=digest(path),
        schedule=plan["schedule_summary"], inventory=plan["inventory"], model_calls_executed=0,
        required_gates=REQUIRED_GATES, runtime_implemented=True, benchmark_scientifically_qualified=False,
        controller_role_implemented=True, authority_issuer_implemented=True, new_authority_issued=False,
        execution_allowed=False, fresh_positive_gate_evidence_required=True, region_benchmark_executed=False,
        cost_controller_handoff=controller_handoff())


def require_execution_admission(plan):
    """This preparation deliberately exposes no executable benchmark bypass."""
    raise RuntimeError("NOT_ADMITTED: a plan cannot issue COST_ONLY authority; supply fresh positive proofs to cost_control prepare-launch")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    prepare = sub.add_parser("prepare")
    prepare.add_argument("study", choices=("FI", "DK2"))
    prepare.add_argument("destination")
    prepare.add_argument("--scope-id")
    sub.add_parser("dry-run").add_argument("plan")
    args = parser.parse_args(argv)
    if args.action == "prepare":
        plan = build_plan(args.study, args.scope_id)
        path = write_plan(plan, args.destination)
        print(json.dumps(dict(plan=str(path), sha256=digest(path), status=plan["status"], inventory=plan["inventory"]), sort_keys=True))
    else:
        print(json.dumps(dry_run(args.plan), sort_keys=True))


if __name__ == "__main__":
    main()
