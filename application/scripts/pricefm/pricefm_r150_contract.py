"""Standard-library contracts for the bounded, cached R150 experiment.

No model or numerical library is imported here. Positive gain means lower loss
than the actual frozen control. All selections are development selections.
"""
from __future__ import annotations

import array
import ast
import datetime as dt
import hashlib
import json
import math
import sys
import zipfile

QUANTILES = (.10, .25, .45, .50, .55, .75, .90)
INT_KEYS = {"origin_positions", "clock_offsets", "stable_rng_origin_keys", "origin_timestamps_ns"}


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                    allow_nan=False).encode()).hexdigest()


def practical_margin(control):
    if isinstance(control, bool) or not math.isfinite(control) or control <= 0:
        raise ValueError("positive finite matched control loss required")
    return max(.10, .01 * control)


def select_branch(b1_cpu, b2_cpu, available_cpu):
    if any(not math.isfinite(v) or v <= 0 for v in (b1_cpu, b2_cpu, available_cpu)):
        raise ValueError("finite positive branch costs and service budget required")
    branch = "B2" if b2_cpu <= 1.5*b1_cpu and b2_cpu <= available_cpu else "B1"
    cost = b2_cpu if branch == "B2" else b1_cpu
    return branch, ("ADMITTED_"+branch if cost <= available_cpu else "DEFERRED_NEITHER_FULL_BRANCH_FITS")


def audit_permutation(packages, key="pricefm_continuation_plan_20261023|audit_v1"):
    return sorted((p["package_id"] for p in packages),
                  key=lambda p: (hashlib.sha256((key+"|"+p).encode()).hexdigest(), p))


def strongest(losses, excluded=()):
    eligible = {p: loss for p, loss in losses.items() if p not in excluded}
    minimum = min(eligible.values())
    return min(p for p, loss in eligible.items() if loss <= minimum+1e-10)


def audit_for_A(packages, a, control, negative,
                key="pricefm_continuation_plan_20261023|audit_v1"):
    by_id = {p["package_id"]: p for p in packages}
    excluded = {by_id[control]["candidate_id"], by_id[negative]["candidate_id"], by_id[a]["candidate_id"]}
    eligible = [p for p in audit_permutation(packages, key) if by_id[p]["candidate_id"] not in excluded]
    if not eligible:
        raise ValueError("no geometry-distinct audit candidate")
    return eligible


def choose_nominees(packages, losses, control, negative,
                    key="pricefm_continuation_plan_20261023|audit_v1"):
    """A is strongest noncontrol; B is a prospectively SHA-ordered geometry.

    B does not depend on losses. Excluding all packages of A's geometry also
    excludes the alternate C0 scale when A has the control geometry.
    """
    by_id = {p["package_id"]: p for p in packages}
    if set(losses) != set(by_id) or any(not math.isfinite(x) for x in losses.values()):
        raise ValueError("complete finite deterministic pool required")
    a = by_id[strongest(losses, [control])]
    order = audit_permutation(packages, key)
    eligible = audit_for_A(packages, a["package_id"], control, negative, key)
    return {"A": a["package_id"], "B": eligible[0], "audit_key": key,
            "audit_order": order, "eligible_audit_order": eligible,
            "audit_rule": "SHA256(key|package_id), excludes C0/C5/A geometries"}


def prospective_costs(packages, tasks, rows, control, negative, key, startup_cpu,
                      share, headroom=1.5):
    """Prospective task and branch costs; no losses or predictions are inputs.

    Cold setup happens once per component, not once per eight-origin chunk.
    Covered dimension/input envelopes use their maximum measured timings;
    unmeasured envelopes use the global policy maximum and retain uncertainty.
    """
    if not 0 < share <= 1 or startup_cpu < 0 or headroom != 1.5:
        raise ValueError("valid frozen idle service/setup/headroom required")
    estimates = {}
    input_fields = ("m_y", "m_x", "depth", "input_fan_in", "recurrent_sparsity")
    for task in tasks:
        policy = [r for r in rows if r["mode"] == task["mode"]]
        if not policy:
            raise ValueError("benchmark missing numerical policy")
        covered = [r for r in policy if r["p"] >= task["p"]
            and r["spec"]["feature_policy"] == task["spec"]["feature_policy"]
            and all(r["spec"][f] >= task["spec"][f] for f in input_fields)]
        bucket = covered or policy
        setup = startup_cpu+max(r["cold_context_cpu_seconds"] for r in bucket)
        per_window = max((r["arithmetic_cpu_seconds"]+r["serialization_cpu_seconds"])/r["origin_count"] for r in bucket)
        windows = len(task["daily_origin_positions"])*len(task["clock_offsets_steps"])
        cpu = headroom*(setup+windows*per_window) if not task["reuse"] else 0.
        chunk_cpu = headroom*8*per_window if not task["reuse"] else 0.
        estimates[task["name"]] = dict(estimated_cpu_seconds=cpu, estimated_wall_seconds=cpu/share,
            setup_cpu_seconds_once=headroom*setup, cpu_seconds_per_window=headroom*per_window,
            estimated_max_chunk_cpu_seconds=chunk_cpu, estimated_max_chunk_wall_seconds=chunk_cpu/share,
            origin_clock_windows=windows, imported=bool(task["reuse"]),
            cost_bucket="covered_dimension_and_input_envelope" if covered else "global_policy_maximum_fallback",
            unmeasured_geometry_timing_uncertainty=not bool(covered),
            benchmark_packages=sorted({r["package_id"] for r in bucket}))
    def cost(ids, mode, seeds):
        wanted = set(ids)
        return sum(estimates[t["name"]]["estimated_cpu_seconds"] for t in tasks
                   if t["package_id"] in wanted and t["mode"] == mode and t["seed_index"] in seeds)
    package_ids = [p["package_id"] for p in packages]
    d = cost(package_ids, "D", [0])
    s0 = cost(package_ids, "S", [0])
    control_extras = cost([control], "S", [1, 2])
    possibilities = []
    for a in package_ids:
        if a == control:
            continue
        b = audit_for_A(packages, a, control, negative, key)[0]
        b1_s = cost([a, b], "S", [0, 1, 2])+control_extras
        b2_extra = cost([a], "S", [1, 2])+control_extras
        possibilities.append(dict(A=a, B=b, B1_S_cpu_seconds=b1_s, B2_extra_S_cpu_seconds=b2_extra))
    worst1 = max(possibilities, key=lambda p: (p["B1_S_cpu_seconds"], p["A"]))
    worst2 = max(possibilities, key=lambda p: (p["B2_extra_S_cpu_seconds"], p["A"]))
    return dict(task_estimates=estimates, estimated_B1_max_cpu_seconds=d+worst1["B1_S_cpu_seconds"],
        estimated_B2_max_cpu_seconds=s0+worst2["B2_extra_S_cpu_seconds"],
        B1_D_cpu_seconds=d, B1_worst_possible_nomination=worst1,
        B2_original_seed_S_cpu_seconds=s0, B2_worst_possible_finalist=worst2,
        shared_control_extra_seed_CPU_seconds=control_extras,
        prospective_possible_nominations=possibilities,
        cost_policy="cold_once_per_component; covered_input_dimension_max_or_global_fallback; 50pct_contingency",
        no_losses_or_predictions_used=True)


def confirm_gains(control, candidate):
    if len(control) != 3 or len(candidate) != 3:
        raise ValueError("exactly three matched full-cohort seeds required")
    if any(not math.isfinite(x) or x <= 0 for x in control + candidate):
        raise ValueError("finite positive matched losses required")
    gains = [c-a for c, a in zip(control, candidate)]
    mean = sum(gains)/3
    radius = max(abs(g-mean) for g in gains)
    margin = practical_margin(sum(control)/3)
    return dict(seed_gains=gains, mean_gain=mean, gain_range=[min(gains), max(gains)],
                max_absolute_deviation=radius, practical_margin=margin,
                practical_gain=mean >= margin, algorithmic_stability_unresolved=radius >= mean,
                eligible_for_AL_proposal=mean >= margin and radius < mean,
                inferential_confidence_interval=False, independent_confirmation=False)


def array_shapes(n):
    result = {k: (n,) for k in INT_KEYS}
    result.update(truth_standardized=(n, 96), truth_eur=(n, 96),
                  prediction_standardized=(n, 96, 7), prediction_eur=(n, 96, 7), origin_AQL=(n,))
    return result


def read_npz(path, headers_only=False):
    """Strict little-endian numeric packets; no pickle/numerical import."""
    result = {}
    with zipfile.ZipFile(path) as packet:
        names = packet.namelist()
        if len(names) != len(set(names)) or any(not n.endswith(".npy") or "/" in n for n in names):
            raise ValueError("invalid NPZ members")
        for name in names:
            with packet.open(name) as stream:
                lead = stream.read(8)
                if lead[:6] != b"\x93NUMPY" or lead[6:8] not in (b"\x01\x00", b"\x02\x00"):
                    raise ValueError("unsupported NPY")
                width = 2 if lead[6] == 1 else 4
                size = int.from_bytes(stream.read(width), "little")
                if size > 65536:
                    raise ValueError("oversized NPY header")
                head = ast.literal_eval(stream.read(size).decode("latin1").strip())
                key = name[:-4]
                dtype = "<i8" if key in INT_KEYS else "<f8"
                if head["descr"] != dtype or head["fortran_order"] is not False:
                    raise ValueError("wrong dtype or order")
                shape = tuple(head["shape"])
                if any(type(v) is not int or v < 0 for v in shape):
                    raise ValueError("invalid shape")
                if packet.getinfo(name).file_size != 8+width+size+8*math.prod(shape):
                    raise ValueError("truncated or padded NPY")
                values = None
                if not headers_only or key in INT_KEYS:
                    values = array.array("q" if key in INT_KEYS else "d")
                    values.frombytes(stream.read())
                    if sys.byteorder != "little":
                        values.byteswap()
                    if any(not math.isfinite(v) for v in values):
                        raise ValueError("nonfinite packet values")
                result[key] = (shape, values)
    return result


def expected_rows(task, descriptor=None):
    if descriptor is not None:
        return list(zip(descriptor["origin_positions"],
                        [descriptor["clock_offset_steps"]]*len(descriptor["origin_positions"]),
                        descriptor["origin_timestamps"]))
    return [(p, o, s) for o in task["clock_offsets_steps"]
            for p, s in zip(task["daily_origin_positions"], task["origin_timestamps"][str(o)])]


def validate_arrays(task, arrays, scaler, descriptor=None, semantic=True):
    rows = expected_rows(task, descriptor)
    n = len(rows)
    wanted = array_shapes(n)
    if set(arrays) != set(wanted) or any(arrays[k][0] != v for k, v in wanted.items()):
        raise ValueError("array shape/member contract differs")
    expected = dict(origin_positions=[r[0] for r in rows], clock_offsets=[r[1] for r in rows],
                    stable_rng_origin_keys=[r[0]*96+r[1] for r in rows],
                    origin_timestamps_ns=[round(dt.datetime.fromisoformat(r[2]).timestamp()*1e9) for r in rows])
    if len(set(zip(expected["origin_positions"], expected["clock_offsets"]))) != n:
        raise ValueError("duplicate origin/clock")
    for key, values in expected.items():
        if list(arrays[key][1]) != values:
            raise ValueError("ordered cohort identity differs: " + key)
    if not semantic:
        return
    scale, center = scaler["price_scale"], scaler["price_mean"]
    if not math.isfinite(center) or not math.isfinite(scale) or scale <= 0:
        raise ValueError("invalid training scaler")
    for key in ("truth", "prediction"):
        for a, b in zip(arrays[key+"_standardized"][1], arrays[key+"_eur"][1]):
            if not math.isfinite(a) or not math.isfinite(b) or not math.isclose(a*scale+center, b, rel_tol=1e-12, abs_tol=1e-10):
                raise ValueError("EUR transform differs")
    truth, pred, losses = (arrays[k][1] for k in ("truth_eur", "prediction_eur", "origin_AQL"))
    for i in range(n):
        total = 0.0
        for h in range(96):
            previous = -math.inf
            for q, level in enumerate(QUANTILES):
                value = pred[(i*96+h)*7+q]
                if not math.isfinite(value) or value < previous-1e-12:
                    raise ValueError("crossing/nonfinite quantiles")
                previous = value
                error = truth[i*96+h]-value
                total += max(level*error, (level-1)*error)
        if not math.isfinite(losses[i]) or not math.isclose(total/(96*7), losses[i], rel_tol=1e-11, abs_tol=1e-10):
            raise ValueError("retained loss does not equal pinball arithmetic")


def metrics(arrays):
    truth, pred, losses = (arrays[k][1] for k in ("truth_eur", "prediction_eur", "origin_AQL"))
    n = len(losses)
    if not n:
        raise ValueError("empty cohort")
    mae = covered = width = 0.0
    for i in range(n*96):
        base = i*7
        mae += abs(truth[i]-pred[base+3])
        covered += pred[base] <= truth[i] <= pred[base+6]
        width += pred[base+6]-pred[base]
    return dict(AQL=sum(losses)/n, median_MAE=mae/(n*96), coverage_80=covered/(n*96), width_80=width/(n*96))
