"""Source-bound conservative stop-decision candidate for startup qualification.

The frozen supervisor remains byte-for-byte unchanged.  Its independent
guardian, owned ancestry/filter, stopped-state proof, hard ceilings, drain,
accounting and receipt publication are used unchanged.  Exactly three AST
comparators inside its monitor's run function gain a fixed stop lead reserve:
two CPU decision comparisons and one wall decision comparison.  Unknown work
is still charged by the original one-core upper bound and fails closed.

This candidate is not qualified by importing it or passing metadata tests.
Actual six-case compute evidence and fresh source-bound authority are required.
"""
from __future__ import annotations

import ast
import copy
import hashlib
import importlib.util
import math
import os
from pathlib import Path
import stat

ORIGINAL_SHA256 = "7d33218f593b0b9677093954f7331cac2b4586f2c428fe08cdf0c784289492a1"
PROFILE = "r176_conservative_stop_lead_v1"
CPU_LEAD_SECONDS = 0.25
WALL_LEAD_SECONDS = 0.25


def require(value, message):
    if not value:
        raise ValueError(message)


def policy():
    return dict(schema=PROFILE, CPU_stop_lead_seconds=CPU_LEAD_SECONDS,
                wall_stop_lead_seconds=WALL_LEAD_SECONDS,
                original_hard_ceilings_and_stop_checks_unchanged=True)


def decision_thresholds(active_ceiling, inner_deadline):
    """Metadata-only policy arithmetic; this never admits work or signals it."""
    require(all(type(x) in (int, float) and math.isfinite(x)
                for x in (active_ceiling, inner_deadline)), "finite decision limits required")
    require(active_ceiling > CPU_LEAD_SECONDS and inner_deadline >= WALL_LEAD_SECONDS,
            "original active limits leave no conservative stop lead")
    return active_ceiling - CPU_LEAD_SECONDS, inner_deadline - WALL_LEAD_SECONDS


def verified_original(path=None):
    path = Path(__file__).absolute().with_name("profile_supervisor.py") if path is None else Path(path)
    require(path.is_absolute() and not any(p.is_symlink() for p in (path, *path.parents)),
            "canonical original supervisor path required")
    before = path.stat()
    require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
            and before.st_uid in (0, os.getuid()) and before.st_size <= 128 * 1024,
            "bounded owned original supervisor required")
    raw = path.read_bytes(); after = path.stat()
    key = lambda s: (s.st_dev,s.st_ino,s.st_uid,s.st_mode,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
    require(key(before) == key(after) and len(raw) == before.st_size
            and hashlib.sha256(raw).hexdigest() == ORIGINAL_SHA256,
            "frozen original supervisor bytes differ")
    return path, raw


class LeadDecisionOnly(ast.NodeTransformer):
    """Change only the three source-reviewed run decision comparators."""
    def __init__(self):
        self.cpu = 0
        self.wall = 0

    def visit_Compare(self, node):
        if len(node.ops) != 1 or not isinstance(node.ops[0], ast.GtE):
            return self.generic_visit(node)
        if isinstance(node.left, ast.Name) and node.left.id == "cpu" \
                and len(node.comparators) == 1 and isinstance(node.comparators[0], ast.Name) \
                and node.comparators[0].id == "active_ceiling":
            self.cpu += 1
            result = copy.deepcopy(node)
            result.comparators[0] = ast.BinOp(left=result.comparators[0], op=ast.Sub(),
                                            right=ast.Constant(value=CPU_LEAD_SECONDS))
            return ast.copy_location(result, node)
        if isinstance(node.left, ast.Call) and isinstance(node.left.func, ast.Attribute) \
                and isinstance(node.left.func.value, ast.Name) and node.left.func.value.id == "time" \
                and node.left.func.attr == "monotonic" and not node.left.args and not node.left.keywords \
                and len(node.comparators) == 1 and isinstance(node.comparators[0], ast.Name) \
                and node.comparators[0].id == "deadline":
            self.wall += 1
            result = copy.deepcopy(node)
            result.comparators[0] = ast.BinOp(left=result.comparators[0], op=ast.Sub(),
                                            right=ast.Constant(value=WALL_LEAD_SECONDS))
            return ast.copy_location(result, node)
        return self.generic_visit(node)


def candidate_run_ast(raw):
    tree = ast.parse(raw)
    functions = [x for x in tree.body if isinstance(x, ast.FunctionDef) and x.name == "run"]
    require(len(functions) == 1, "exact original monitor run function required")
    transformer = LeadDecisionOnly()
    result = transformer.visit(copy.deepcopy(functions[0]))
    require((transformer.cpu, transformer.wall) == (2, 1),
            "original three decision-comparator surface differs")
    return ast.fix_missing_locations(ast.Module(body=[result], type_ignores=[]))


def load_candidate():
    """Load pinned original functions and replace only run's decision policy."""
    path, raw = verified_original()
    spec = importlib.util.spec_from_file_location("_pricefm_r176_original_guard", path)
    guard = importlib.util.module_from_spec(spec)
    # Execute only the exact already-verified bytes, avoiding a second path read.
    exec(compile(raw, str(path), "exec"), guard.__dict__)
    namespace = {}
    exec(compile(candidate_run_ast(raw), str(Path(__file__).absolute())+"<reviewed-run>", "exec"),
         guard.__dict__, namespace)
    transformed = namespace["run"]

    def candidate_run(*args, **kwargs):
        value = transformed(*args, **kwargs)
        value.update(supervision_profile=PROFILE, original_supervisor_sha256=ORIGINAL_SHA256,
                     conservative_stop_policy=policy(),
                     CPU_decision_ceiling=value["CPU_active_ceiling"]-CPU_LEAD_SECONDS)
        return value

    guard.run = candidate_run
    return guard


def require_candidate_receipt(guard):
    require(guard.get("supervision_profile") == PROFILE
            and guard.get("original_supervisor_sha256") == ORIGINAL_SHA256
            and guard.get("conservative_stop_policy") == policy(),
            "actual exact conservative-stop candidate receipt required")
    active = guard.get("CPU_active_ceiling")
    require(type(active) in (int,float) and math.isfinite(active)
            and guard.get("CPU_decision_ceiling") == active-CPU_LEAD_SECONDS,
            "candidate decision ceiling differs from unchanged hard active ceiling")


def main(argv=None):
    return load_candidate().main(argv)


if __name__ == "__main__":
    raise SystemExit(main())
