"""Predeclared origin-sampler diagnostics using already computed paired losses."""
import hashlib
import json
import math
import random

SAMPLE_SIZES = (4, 12, 24, 48)
REPLICATES = 32
MASTER_SEED = 2026102303
METHODS = ('uniform', 'weekday_stratified', 'month_stratified')


def _mean(values):
    return math.fsum(value / len(values) for value in values)


def _key(value):
    if isinstance(value, bool) or not isinstance(value, (str, int)) or str(value) == '':
        raise ValueError('origin_key must be a nonempty string or integer')
    return str(value)


def _population(paired_days):
    splits = {split: [] for split in (1, 2, 3)}; seen = set()
    for raw in paired_days:
        try:
            split, weekday, month = raw['split'], raw['weekday'], raw['month']
            key = _key(raw['origin_key'])
            losses = [raw['control_loss'], raw['competitor_loss']]
        except (KeyError, TypeError) as exc:
            raise ValueError('every row must contain paired losses and all origin fields') from exc
        if (type(split) is not int or split not in splits or type(weekday) is not int
                or weekday not in range(7) or type(month) is not int or month not in range(1, 13)):
            raise ValueError('split1–3, weekday0–6 and month1–12 must be integers')
        if any(isinstance(x, bool) or not isinstance(x, (int, float)) or not math.isfinite(x) for x in losses):
            raise ValueError('paired losses must be finite numbers')
        if min(losses) < 0:
            raise ValueError('paired AQL losses must be nonnegative')
        if (split, key) in seen:
            raise ValueError('duplicate split/origin_key')
        seen.add((split, key))
        splits[split].append(dict(key=key, weekday=weekday, month=month,
            difference=float(losses[1]) - float(losses[0])))
        if not math.isfinite(splits[split][-1]['difference']):
            raise ValueError('paired loss contrast is nonfinite')
    if any(not rows for rows in splits.values()):
        raise ValueError('all three rolling splits must have paired daily losses')
    return {split: sorted(rows, key=lambda row: row['key']) for split, rows in splits.items()}


def _design(rows, method, size):
    field = {'weekday_stratified': 'weekday', 'month_stratified': 'month'}.get(method)
    groups = {}
    for row in rows:
        groups.setdefault(str(row[field]) if field else 'all', []).append(row)
    groups = dict(sorted(groups.items()))
    if size > len(rows) or size < len(groups):
        return None
    quota = {label: 1 for label in groups}
    for _ in range(size - len(groups)):
        eligible = [h for h in groups if quota[h] < len(groups[h])]
        h = min(eligible, key=lambda h: (quota[h] - size * len(groups[h]) / len(rows), h))
        quota[h] += 1
    weights = {h: len(values) / len(rows) for h, values in groups.items()}
    return groups, quota, weights


def _estimate(rows, method, size, replicate, split, design):
    groups, quota, weights = design
    seed_key = [MASTER_SEED, method, size, replicate, split, [row['key'] for row in rows]]
    seed = int(hashlib.sha256(json.dumps(seed_key, separators=(',', ':')).encode()).hexdigest(), 16)
    rng = random.Random(seed)
    return math.fsum(weights[h] * _mean([row['difference'] for row in rng.sample(groups[h], quota[h])])
                     for h in groups)


def _legacy(population, panels, reference):
    result = {}
    if panels is not None and (not isinstance(panels, dict) or any(not isinstance(k, str) for k in panels)):
        raise ValueError('legacy panels must map string labels to split panels')
    for label, panel in sorted((panels or {}).items()):
        if not isinstance(panel, dict) or len(panel) != 3 or {str(split) for split in panel} != {'1', '2', '3'}:
            raise ValueError('legacy panels must specify exactly three splits')
        estimates = {}; counts = {}
        for split, rows in population.items():
            keys = [_key(k) for k in panel.get(split, panel.get(str(split), []))]
            lookup = {row['key']: row['difference'] for row in rows}
            if not keys or len(set(keys)) != len(keys) or not set(keys).issubset(lookup):
                raise ValueError('legacy panel is empty, duplicated or outside paired population')
            estimates[split] = _mean([lookup[k] for k in sorted(keys)]); counts[str(split)] = len(keys)
        contrast = _mean(list(estimates.values()))
        result[label] = dict(macro_contrast=contrast, error_vs_full=contrast - reference,
            daily_origins_per_split=counts, estimator='fixed unweighted daily means; nonprobability panel')
    return result


def analyze_sampling(paired_days, legacy_panels=None):
    """Contrast is competitor−control; negative favors the competitor.

    Every input loss is the daily mean over the same four clock offsets. Uniform
    draws use no replacement; strata receive at least one origin and capped
    proportional largest-deficit quotas. Stratum means use population weights.
    Historical panels are diagnostics, never automatic choices.
    """
    population = _population(paired_days)
    split_reference = {str(s): _mean([row['difference'] for row in rows]) for s, rows in population.items()}
    reference = _mean(list(split_reference.values()))
    summaries = []
    sign = lambda value: (value > 0) - (value < 0)
    for method in METHODS:
        for size in SAMPLE_SIZES:
            designs = {s: _design(rows, method, size) for s, rows in population.items()}
            record = dict(method=method, daily_origins_per_split=size,
                clock_pairs_per_split=4 * size, total_clock_pairs=12 * size)
            if any(design is None for design in designs.values()):
                summaries.append(dict(record, status='infeasible',
                    reason='sample exceeds a split population or cannot represent every nonempty stratum'))
                continue
            estimates = [_mean([_estimate(rows, method, size, rep, s, designs[s])
                for s, rows in population.items()]) for rep in range(REPLICATES)]
            errors = [value - reference for value in estimates]
            design_summary = {str(s): {h: dict(population=len(groups[h]), quota=quota[h],
                population_weight=weights[h], per_selected_origin_weight=weights[h] / quota[h])
                for h in groups} for s, (groups, quota, weights) in designs.items()}
            summaries.append(dict(record, status='complete', replicates=REPLICATES,
                macro_estimates=estimates, bias=_mean(errors), MAE=_mean([abs(e) for e in errors]),
                sign_agreement=_mean([int(sign(value) == sign(reference)) for value in estimates]),
                design=design_summary))
    return dict(reference_macro_contrast=reference, reference_split_contrasts=split_reference,
        pooled_reference_contrast_diagnostic_only=_mean([row['difference'] for rows in population.values() for row in rows]),
        split_population_sizes={str(s): len(rows) for s, rows in population.items()},
        sample_sizes=list(SAMPLE_SIZES), resampling_replicates=REPLICATES, master_seed=MASTER_SEED,
        bias_definition='empirical mean signed error over 32 panel draws; not evidence of structural estimator bias',
        seed_rule='SHA256(master,method,size,replicate,split,sorted_origin_keys); Python random without replacement',
        primary_estimand='equal-three-split macro mean of competitor-control daily losses',
        samplers=summaries, legacy_panels=_legacy(population, legacy_panels, reference),
        limitations=['two prefitted geometries and one original full-forecast Monte Carlo seed',
            'daily rows are supplied means over four declared clocks',
            '32 origin resamples quantify panel sensitivity, not forecast Monte Carlo uncertainty',
            'development evidence; no new validation claim or automatic panel choice'],
        new_forecasts=0, automatic_panel_choice=False, new_validation_claim=False)
