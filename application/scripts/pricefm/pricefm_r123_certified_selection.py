"""Explicit successor selection: complete, certified groups only; never impute a missing split."""
from __future__ import annotations

import math


def certified_groups(cells, expected_candidate_ids, minimum_candidates=3, tau_top_k=10):
    expected = set(expected_candidate_ids)
    if len(expected) != len(expected_candidate_ids) or minimum_candidates < 3 or tau_top_k < 1:
        raise ValueError("invalid declared shortlist or selection bounds")
    groups = {}
    for cell in cells:
        identifier = cell["candidate_id"]
        if identifier not in expected or cell["split"] not in (1, 2, 3):
            raise ValueError("unknown candidate or split")
        key = (identifier, float(cell["tau0"]))
        if not math.isfinite(key[1]) or key[1] <= 0: raise ValueError("invalid fixed prior scale")
        group = groups.setdefault(key, {})
        if cell["split"] in group: raise ValueError("duplicated candidate/scale/split")
        if cell.get("test_opened") is not False: raise ValueError("forbidden or unresolved test access")
        group[cell["split"]] = cell
    accepted, excluded = [], []
    for (identifier, tau0), group in groups.items():
        valid = len(group) == 3 and all(row.get("full_variational_certified") is True and
            math.isfinite(float(row.get("AQL", float("nan")))) and
            math.isfinite(float(row.get("late_AQL", float("nan")))) for row in group.values())
        if not valid:
            excluded.append({"candidate_id": identifier, "tau0": tau0,
                "reason": "incomplete_or_uncertified_three_split_group"})
            continue
        scores = [float(row["AQL"]) for row in group.values()]
        accepted.append({"candidate_id": identifier, "tau0": tau0, "mean_AQL": sum(scores) / 3,
            "mean_late_AQL": sum(float(row["late_AQL"]) for row in group.values()) / 3,
            "worst_AQL": max(scores)})
    accepted.sort(key=lambda row: (row["mean_AQL"], row["mean_late_AQL"], row["worst_AQL"], row["candidate_id"]))
    unique = []
    for row in accepted:
        if row["candidate_id"] not in {item["candidate_id"] for item in unique}: unique.append(row)
    enough = len(unique) >= minimum_candidates
    return {"status": "CERTIFIED_SELECTION_READY" if enough else "CERTIFIED_SELECTION_BLOCKED",
        "ranking": accepted, "excluded": excluded,
        "missing_candidate_ids": sorted(expected - {key[0] for key in groups}),
        "tau_candidate_ids": [row["candidate_id"] for row in unique[:tau_top_k]] if enough else [],
        "al_candidate_ids": [row["candidate_id"] for row in unique[:3]] if enough else [],
        "rule": "explicit_successor_complete_certified_groups_not_legacy_30_of_30",
        "test_opened": False, "launch_authorized": False}
