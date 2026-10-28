"""Portable TEST execution of one sealed forecast chunk using frozen equations.

Importing this module is stdlib only. The callable imports scientific packages
only inside an admitted Slurm execution. It neither calls nor weakens the old
Muscat Git/systemd/ownership wrappers.
"""
from __future__ import annotations

import argparse
import ast
import builtins
import datetime as dt
import hashlib
import importlib.util
import math
import os
from pathlib import Path
import resource
import symtable
import sys
import time

from .fixture import (ARRAY_SHAPES, COMPARISON, FUNCTION_AST_SHA256, FUNCTION_GLOBALS,
    INT_KEYS, SOURCE_PINS, digest, fingerprint, load_fixture, read_json, write_json)
from .environment import require_compute


def _referenced_globals(table):
    result = {s.get_name() for s in table.get_symbols() if s.is_global() and s.is_referenced()}
    for child in table.get_children():
        result.update(_referenced_globals(child))
    return result


def extract_function(path, expected_source_sha, expected_ast_sha, bindings, allowed_globals=FUNCTION_GLOBALS):
    """Compile an unchanged trusted FunctionDef in a new explicit namespace.

    Both the entire source and canonical AST must match. This does not edit,
    monkeypatch or rebind a frozen module; only the original pure function is
    executed with its reviewed dependency bindings.
    """
    if digest(path) != expected_source_sha:
        raise ValueError("frozen function source bytes differ")
    source = Path(path).read_text()
    tree = ast.parse(source, filename=str(path))
    matches = [node for node in tree.body if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "retained_chunk"]
    if len(matches) != 1 or not isinstance(matches[0], ast.FunctionDef) or matches[0].decorator_list:
        raise ValueError("one undecorated original function required")
    function = matches[0]
    actual_ast = hashlib.sha256(ast.dump(function, include_attributes=False).encode()).hexdigest()
    if actual_ast != expected_ast_sha:
        raise ValueError("frozen function AST differs")
    if (function.returns is not None or any(a.annotation is not None for a in (*function.args.posonlyargs, *function.args.args, *function.args.kwonlyargs))
            or any(not isinstance(d, ast.Constant) or d.value is not None for d in function.args.defaults)
            or function.args.kw_defaults):
        raise ValueError("unsupported executable defaults/annotations")
    table = symtable.symtable(ast.get_source_segment(source, function), str(path), "exec").get_children()[0]
    actual_globals = _referenced_globals(table)
    if actual_globals != set(allowed_globals) or set(bindings) != actual_globals:
        raise ValueError("unsupported or incomplete function globals")
    builtin_names = {name: value for name, value in bindings.items() if name in vars(builtins)}
    namespace = {"__builtins__": {**builtin_names, "__import__": builtins.__import__}, **bindings}
    code = compile(ast.Module(body=[function], type_ignores=[]), str(path), "exec")
    exec(code, namespace)
    return namespace["retained_chunk"]


def _load_module(name, path):
    if name in sys.modules:
        raise RuntimeError("fresh scientific execution process required")
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def _assert_frozen_imports(resolver):
    approved = {resolver.path(p).resolve() for p in resolver.assets if p.endswith(".py")}
    for name, module in list(sys.modules.items()):
        if name.startswith("pricefm_") and not name.startswith("pricefm_hb"):
            path = getattr(module, "__file__", None)
            if path is None or Path(path).resolve() not in approved:
                raise RuntimeError("unsealed PriceFM import: " + name)


def _context(manifest, resolver, core, kernel):
    """497/494 load mapping with logical paths resolved before original loaders."""
    runtime = core.dependencies(resolver.directory(manifest["dependency_root"]))
    _assert_frozen_imports(resolver)
    kernel.numerical_threadpools()
    task = manifest["task"]
    raw = core.load_arrays(runtime, resolver.path(task["bank"]["path"]))
    cell = runtime.internal_splits(len(raw.response))[task["split"] - 1]
    if (cell["train"].tolist() != task["train_origin_positions"] or cell["validation"].tolist() != task["validation_origin_positions"]):
        raise RuntimeError("exact frozen inner cohort differs")
    scaled, scaler = runtime.standardize_from_training_origins(raw, cell["train"])
    if fingerprint(scaler) != fingerprint(read_json(resolver.path(task["scaler_path"]))):
        raise RuntimeError("training-only scaler identity differs")
    # The original loader consumes terminal JSON and the two little-endian
    # moment binaries. RDS remains staged and hash verified as opaque provenance.
    fit = runtime.load_normal_fit(resolver.directory(task["parent_fit"]))
    if len(fit["beta_mean"]) != manifest["size"]["normal_dimension"]:
        raise RuntimeError("original Normal moment dimension differs")
    return dict(core=core, runtime=runtime, raw=raw, scaled=scaled, scaler=scaler, fit=fit,
        pools=kernel.numerical_threadpools())


def compare_nested(expected, actual, path="audit"):
    """Strict sampler identity, with predeclared diagnostic-float tolerance."""
    if isinstance(expected, dict):
        if not isinstance(actual, dict) or set(expected) != set(actual):
            raise RuntimeError("sampler audit members differ: " + path)
        return {key: compare_nested(expected[key], actual[key], path + "." + key) for key in expected}
    if isinstance(expected, list):
        if not isinstance(actual, list) or len(expected) != len(actual):
            raise RuntimeError("sampler audit length differs: " + path)
        return [compare_nested(e, a, path + "[" + str(i) + "]") for i, (e, a) in enumerate(zip(expected, actual))]
    if type(expected) is float:
        diagnostic = path.rsplit(".", 1)[-1] in ("relative_asymmetry", "relative_reconstruction_error")
        accepted = (math.isclose(expected, actual, abs_tol=COMPARISON["sampler_diagnostic_atol"],
            rel_tol=COMPARISON["sampler_diagnostic_rtol"]) if diagnostic and type(actual) in (float, int)
            else type(actual) is float and expected == actual)
        if type(actual) not in (float, int) or not math.isfinite(actual) or not accepted:
            raise RuntimeError("sampler diagnostic differs: " + path)
        return dict(reference=expected, actual=actual, absolute_difference=abs(expected - actual))
    if type(expected) is not type(actual) or expected != actual:
        raise RuntimeError("sampler identity differs: " + path)
    return dict(equal=True)


def compare_arrays(reference, actual, np):
    if set(reference) != set(ARRAY_SHAPES) or set(actual) != set(reference):
        raise RuntimeError("retained array members differ")
    comparison = {}
    for key, shape in ARRAY_SHAPES.items():
        old, new = reference[key], actual[key]
        dtype = "<i8" if key in INT_KEYS else "<f8"
        if (list(old.shape) != shape or list(new.shape) != shape or old.dtype.str != dtype or new.dtype.str != dtype
                or not np.isfinite(old).all() or not np.isfinite(new).all()):
            raise RuntimeError("retained array geometry/dtype/finiteness differs: " + key)
        bitwise = old.tobytes(order="C") == new.tobytes(order="C")
        exact = key in INT_KEYS or key.startswith("truth_") or key == "lag_features"
        accepted = bitwise if exact else bool(np.allclose(new, old,
            atol=COMPARISON["prediction_and_AQL_atol"], rtol=COMPARISON["prediction_and_AQL_rtol"]))
        delta = np.abs(new - old)
        comparison[key] = dict(shape=shape, dtype=dtype, bitwise_equal=bitwise, accepted=accepted,
            maximum_absolute_difference=float(delta.max()), reference_array_sha256=hashlib.sha256(old.tobytes(order="C")).hexdigest(),
            actual_array_sha256=hashlib.sha256(new.tobytes(order="C")).hexdigest())
    return comparison


def _execute_fixture(manifest, resolver, output):
    import numpy as np
    from threadpoolctl import threadpool_info

    # No historical module may have been imported from another checkout.
    _assert_frozen_imports(resolver)
    core = _load_module("_pricefm_hb_frozen_r134", resolver.path(SOURCE_PINS["core"][0]))
    kernel = _load_module("_pricefm_hb_frozen_r148", resolver.path(SOURCE_PINS["kernel"][0]))
    original = _load_module("_pricefm_hb_frozen_r149", resolver.path(SOURCE_PINS["retained"][0]))
    context = _context(manifest, resolver, core, kernel)
    task, descriptor = manifest["task"], manifest["descriptor"]
    execution_task = dict(task, scaler_path=str(resolver.path(task["scaler_path"])))
    def validate_arrays(original_task, arrays, original_descriptor):
        if original_task != task or original_descriptor != descriptor:
            raise RuntimeError("pure-function task/descriptor identity changed")
        return original.validate_arrays(execution_task, arrays, original_descriptor)
    bindings = {"INT_ARRAYS": frozenset(original.INT_ARRAYS), "dt": dt, "kernel": lambda: kernel,
        "validate_arrays": validate_arrays,
        **{name: vars(builtins)[name] for name in FUNCTION_GLOBALS if name in vars(builtins)}}
    retained = extract_function(resolver.path(SOURCE_PINS["retained"][0]), SOURCE_PINS["retained"][1],
        FUNCTION_AST_SHA256, bindings)
    reference_path = resolver.path(manifest["reference"]["arrays"])
    with np.load(reference_path, allow_pickle=False) as packet:
        reference = {key: packet[key] for key in packet.files}
    original.validate_arrays(execution_task, reference, descriptor)
    write_json(output / "saved_array_validation.json", dict(status="PASS_SEALED_SAVED_ARRAYS", arrays=manifest["reference"]["headers"],
        reference_sha256=digest(reference_path), new_model_fits=0, official_origins=0))
    events = []
    arrays, audit = retained(context, task, descriptor, events.append)
    pools = kernel.numerical_threadpools()
    np.savez_compressed(output / "predictions.npz", **arrays)
    array_comparison = compare_arrays(reference, arrays, np)
    write_json(output / "array_comparison.json", array_comparison)
    metadata = read_json(resolver.path(manifest["reference"]["metadata"]))
    write_json(output / "sampler_audit.json", dict(reference=metadata["sampler_audit"], actual=audit))
    audit_comparison = compare_nested(metadata["sampler_audit"], audit)
    from pricefm_r127_contract import common_metrics
    reference_metrics = {mode: common_metrics(reference["truth_eur"], reference[mode + "_eur"]) for mode in ("deterministic", "stochastic")}
    actual_metrics = {mode: common_metrics(arrays["truth_eur"], arrays[mode + "_eur"]) for mode in ("deterministic", "stochastic")}
    metrics_pass = all(np.allclose(actual_metrics[mode][key], value,
        atol=COMPARISON["prediction_and_AQL_atol"], rtol=COMPARISON["prediction_and_AQL_rtol"])
        for mode, metrics in reference_metrics.items() for key, value in metrics.items())
    _assert_frozen_imports(resolver)
    accepted = all(c["accepted"] for c in array_comparison.values()) and metrics_pass
    return dict(status="PASS_TEST_FORECAST_PARITY" if accepted else "FAIL_TEST_FORECAST_PARITY", accepted=accepted,
        array_comparison=array_comparison, sampler_audit=audit, sampler_audit_comparison=audit_comparison,
        reference_metrics=reference_metrics, actual_metrics=actual_metrics, metrics_accepted=bool(metrics_pass),
        numerical_threadpools=pools, loaded_threadpools=threadpool_info(), events=events,
        executed_math=dict(function="retained_chunk", source=manifest["sources"]["retained"], ast_sha256=FUNCTION_AST_SHA256,
            original_host_wrapper_executed=False, adapter_patched_frozen_module_globals=False),
        predictions_sha256=digest(output / "predictions.npz"))


def run_fixture(manifest_path, output_dir):
    """Execute once into a fresh TEST directory, under the external finite grant."""
    allocation = require_compute()
    output = Path(output_dir).resolve()
    if "TEST" not in output.parts or any(part in ("tasks_done", "checkpoints", "training_banks") for part in output.parts):
        raise ValueError("fresh separate TEST output namespace required")
    for name in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS", "BLIS_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
        if os.environ.get(name) != "1":
            raise RuntimeError("one numerical thread required: " + name)
    manifest, resolver = load_fixture(manifest_path)
    output.mkdir(parents=True, exist_ok=False)
    started, cpu0 = time.monotonic(), time.process_time()
    identity = dict(namespace="TEST", slurm_job_id=os.environ["SLURM_JOB_ID"], host=os.uname().nodename,
        pid=os.getpid(), allocation=allocation, fixture_manifest_sha256=digest(manifest_path), original_source=manifest["source"],
        original_scientific_context=read_json(resolver.path(manifest["reference"]["metadata"]))["context"],
        descriptor=manifest["descriptor"], no_campaign_credit=True, new_model_fits=0, posterior_updated=False, official_origins=0)
    write_json(output / "execution_identity.json", identity)
    try:
        result = _execute_fixture(manifest, resolver, output)
        result.update(execution=identity, comparison=COMPARISON, elapsed_seconds=time.monotonic() - started,
            cpu_seconds=time.process_time() - cpu0, peak_RSS_KiB=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
        write_json(output / "parity.json", result)
        if result["accepted"] is not True:
            raise RuntimeError("forecast parity failed; discrepancies retained")
        write_json(output / "completed_evidence.json", dict(status="COMPLETE_TEST_ONLY", execution=identity,
            artifacts={str(path.relative_to(output)): digest(path) for path in sorted(output.rglob("*")) if path.is_file()}))
        return result
    except BaseException as error:
        write_json(output / "failure.json", dict(status="FAILED_TEST_NO_RETRY", error_type=type(error).__name__,
            error=str(error), execution=identity, elapsed_seconds=time.monotonic() - started, cpu_seconds=time.process_time() - cpu0))
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest")
    parser.add_argument("output_dir")
    args = parser.parse_args()
    result = run_fixture(args.manifest, args.output_dir)
    print(result["status"])


if __name__ == "__main__":
    main()
