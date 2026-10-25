#!/usr/bin/env python3
"""Verify the frozen R153 science-preparation bundle, without dispatching work.

This utility reads JSON/files and scientific source bytes. It imports no model
or runtime module, executes no bundle script, and has no fit/forecast/admission
operation. The manifest hash is a source-pinned evidence identity, not a grant.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import sys

EXPECTED_MANIFEST_SHA256 = '4354ded84fb97d98da34bdfa94086d6bb2f441df81c40b92651a7139ba374c57'
EXPECTED_FILES = frozenset({
    'CERTIFICATE_REPAIR_DOSSIER.json', 'CERTIFICATE_REPAIR_DOSSIER.md',
    'EE_CARRY_FORWARD_READINESS.json', 'EE_CARRY_FORWARD_READINESS.md',
    'JEREZ_SAVED_EVIDENCE.json', 'JEREZ_SAVED_EVIDENCE.stderr',
    'LOCAL_TARGET_INPUTS.json', 'LV_CALIBRATION_DOSSIER.json',
    'LV_CALIBRATION_DOSSIER.md', 'LV_TRAINING_DIAGNOSTIC_MANIFEST.json',
    'READONLY_SOURCE_ALIAS_PROOF.json', 'SCIENCE_IMPLEMENTATION_REPORT.md',
    'SCIENCE_PREPARATION_STATUS.json', 'VALIDATION_RECEIPT.json',
    'capture_jerez_saved_evidence.py', 'capture_local_targets.py',
    'synthesize_science_dossiers.py', 'verify_science_preparation.py',
    'write_science_reports.py',
})
LEVELS = [.1, .25, .45, .5, .55, .75, .9]
LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
    elbo_relative=1e-8, predictor_rms=1e-6, rhs_joint_log_rates=1e-6,
    rhs_start_log_precision=1e-6, sigma_relative=1e-6)
SCOPE_ID = '4afe5e69a49547c7951c5359d3fe44ba'
MASTER_SHA256 = '966f18a2f3410c74c256d7fb2b4407e5531ffa79533f5029b72af6e9514c0098'
T0 = 1792874622.6687887
EXPIRY = 1792917822.6687887
EE_SCIENCE = 1846.990382145998
CACHED_CONTROL = 428.62592073485877
JSON_FILES = tuple(name for name in EXPECTED_FILES if name.endswith('.json'))


def require(value, message):
    if not value:
        raise RuntimeError(message)


def sha256(path):
    value = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def finite_equal(actual, expected):
    return (not isinstance(actual, bool) and isinstance(actual, (int, float))
        and math.isfinite(actual) and math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12))


def stable_seed(*parts):
    raw = json.dumps(parts, sort_keys=True, separators=(',', ':'), default=str).encode()
    return int.from_bytes(hashlib.sha256(raw).digest()[:8], 'little') % (2**63 - 1)


def _safe_relative(name):
    require(isinstance(name, str) and bool(name) and '\\' not in name, 'unsafe artifact path')
    value = PurePosixPath(name)
    require(bool(value.parts) and not value.is_absolute()
        and all(part not in ('', '.', '..') for part in value.parts),
        'artifact path escapes bundle')
    require(str(value) == name, 'noncanonical artifact path')
    return value


def _verify_artifacts(bundle, manifest):
    require(manifest.get('status') == 'SEALED_SCIENCE_AUDIT_AND_PROTOCOL_PREPARATION',
        'unexpected science manifest status')
    require(set(manifest.get('files', {})) == EXPECTED_FILES and manifest.get('file_count') == 19,
        'science artifact inventory differs')
    actual = set()
    for path in bundle.rglob('*'):
        require(not path.is_symlink(), 'science bundle contains a symlink')
        if path.is_file() and path.name != 'artifact_manifest.json':
            actual.add(path.relative_to(bundle).as_posix())
    require(actual == EXPECTED_FILES, 'unsealed or missing science artifact')
    for name, record in manifest['files'].items():
        _safe_relative(name)
        path = bundle / name
        require(path.is_file() and not path.is_symlink(), 'artifact is not a regular file')
        require(type(record.get('bytes')) is int and path.stat().st_size == record['bytes'],
            'science artifact size differs: ' + name)
        require(sha256(path) == record.get('sha256'), 'science artifact hash differs: ' + name)


def _validate_blockers(payloads):
    status = payloads['SCIENCE_PREPARATION_STATUS.json']
    dossier = payloads['CERTIFICATE_REPAIR_DOSSIER.json']
    local = payloads['LOCAL_TARGET_INPUTS.json']
    remote = payloads['JEREZ_SAVED_EVIDENCE.json']
    require(dossier.get('status') == 'PREPARED_VERIFIED_NO_REPAIR_FIT_ADMITTED', 'repair admission differs')
    require(dossier.get('numerical_caps') == {'AL': 300, 'Normal': 2000}, 'scientific caps differ')
    require(dossier.get('historical_600_cap_proposals_selected') is False,
        'historical larger-cap proposal was selected')
    require(dossier.get('target_counts') == {'AT': 4, 'LT': 1, 'NO_3': 2}, 'blocking target census differs')
    raw = {}
    for region, targets in [('AT', local['regions']['AT']['targets']),
            ('LT', local['regions']['LT']['targets']), ('NO_3', remote['NO3']['targets'])]:
        for target in targets:
            require(target['name'] not in raw, 'duplicate failed target')
            raw[target['name']] = (region, target)
    rows = dossier['failed_returned_targets']
    require(len(raw) == len(rows) == 7 and {row['name'] for row in rows} == set(raw),
        'failed target identity list differs')
    for row in rows:
        region, target = raw[row['name']]
        contract, terminal, cert = target['contract'], target['terminal'], target['certificate']
        require(row['region'] == region and target['task']['kind'] in ('al', 'internal_al'),
            'nonblocking or wrong-region target')
        require(row['task'] == target['task'] and row['contract_sha256'] == target['contract_sha256']
            and row['certificate_sha256'] == target['retained_files']['fixedpoint_certificate.json']['sha256']
            and row['parent_certified'] is True, 'failed target provenance differs')
        for key in ('n', 'p', 'tau', 'tau0'):
            require(row[key] == terminal[key], 'failed target dimensions/quantile differ')
        require(row['seed'] == contract['seed'], 'failed target seed differs')
        require(contract['max_iter'] == terminal['iterations'] == row['iteration_cap'] == 300,
            'AL target cap differs')
        require(terminal['computationally_certified'] is False and cert['certified'] is False,
            'failed target was relabelled certified')
        require(terminal['full_fit_object_retained'] is False
            and terminal['exact_optimizer_resumption_supported'] is False
            and row['resume_supported'] is False and row['fit_admitted'] is False,
            'unsupported resumption or repair grant')
        require(contract['prior_center_from_initializer'] is False
            and row['initialization_changes_prior'] is False, 'initializer changes prior')
        require(contract['posterior_target_sha256'] == terminal['posterior_target_sha256']
            == row['posterior_target_sha256'], 'posterior target differs')
        require(contract['certificate_limits'] == cert['limits'] == LIMITS,
            'independent certificate limits differ')
        failed = []
        for key, limit in LIMITS.items():
            ratio = cert['measures'][key] / limit
            require(finite_equal(row['all_limit_ratios'][key], ratio), 'certificate ratio differs')
            require(type(cert['checks'][key]) is bool and cert['checks'][key] == (ratio <= 1),
                'certificate check differs')
            if ratio > 1:
                failed.append(key)
        require(set(row['failed_checks']) == set(failed) and bool(failed), 'failed gate list differs')
    require(status['blocking_AL_targets'] == 7 and status['target_counts'] == dossier['target_counts']
        and dossier['blocked_unsealed_dependants'] == {'AT': 15, 'LT': 10, 'NO_3': 4}
        and dossier['failed_targets_added_to_unsealed_count'] is False, 'blocker accounting differs')


def _validate_training(payloads):
    manifest = payloads['LV_TRAINING_DIAGNOSTIC_MANIFEST.json']
    remote = payloads['JEREZ_SAVED_EVIDENCE.json']['LV']
    saved = payloads['LV_CALIBRATION_DOSSIER.json']
    require(manifest['status'] == 'FROZEN_PROPOSAL_NOT_ADMITTED'
        and manifest['dispatch_authorized'] is False and manifest['admission'] is None,
        'LV protocol is not unadmitted preparation')
    require(all(manifest[key] is False for key in ('candidate_nomination_authorized', 'promotion_authorized'))
        and manifest['new_fits'] == manifest['official_origins_used'] == manifest['official_scores_mutated'] == 0,
        'forbidden LV scientific scope')
    require(manifest['max_forecast_calls'] == 12 and manifest['origin_clock_pairs'] == 144
        and manifest['horizon_steps'] == 96 and manifest['posterior_paths'] == 500
        and manifest['quantiles'] == LEVELS, 'LV finite scientific geometry differs')
    require(manifest['pricing_gate']['status'] == 'NOT_PRICED_NOT_FUNDED'
        and manifest['pricing_gate']['CPU_allowance'] is None
        and manifest['pricing_gate']['wall_allowance'] is None, 'implicit LV resource allocation')
    require(remote['protocol']['paths'] == 500 and remote['protocol']['al_max_iter'] == 300
        and remote['protocol']['normal_max_iter'] == 2000
        and remote['protocol']['quantiles'] == LEVELS
        and remote['protocol']['clock_offsets_steps'] == [0, 24, 48, 72],
        'frozen baseline protocol differs')
    choice = remote['frozen_choice']
    require(manifest['region'] == 'LV' and manifest['candidate_id'] == choice['candidate_id']
        and manifest['tau0'] == choice['tau0']
        and manifest['specification_sha256'] == choice['specification_sha256'], 'LV selected target differs')
    require(manifest['expected_training_bank_sha256'] == remote['bank_expected_sha256']
        and manifest['preparation_sha256'] == remote['preparation_sha256']
        and manifest['operators_generated_by_same_call'] == ['mean_feature', 'path_specific',
            'normal_driver', 'rearranged_path_mean', 'cdf_pool_clipped', 'cdf_pool_linear'],
        'LV bank/preparation/operator protocol differs')
    groups = {row['task']['split']: row for row in remote['prospective_training_groups']}
    require(set(groups) == {1, 2, 3}, 'inner training group census differs')
    calls = manifest['call_manifest']
    require(len(calls) == 12 and len({row['id'] for row in calls}) == 12, 'LV calls duplicated or enlarged')
    keys = set()
    for call in calls:
        split, clock = call['split'], call['clock_offset_steps']
        require(split in groups and clock in (0, 24, 48, 72), 'unknown inner split/clock')
        require((split, clock) not in keys, 'duplicate training split/clock')
        keys.add((split, clock))
        group = groups[split]; task = group['task']
        require(task['kind'] == 'internal_score' and task['name'].startswith('iq_LV_')
            and task['region'] == 'LV' and task['candidate_id'] == choice['candidate_id']
            and task['tau0'] == choice['tau0']
            and call['source_score_task'] == task['name']
            and call['source_score_task_sha256'] == group['task_sha256'], 'official or wrong scorer target')
        require(len(group['parents']) == 8 and set(group['parents'])
            == {task['rhs_name'], *task['al_names'].values()}
            and sorted(map(float, task['al_names'])) == LEVELS,
            'training seven-quantile parent set differs')
        lo, hi = ((506, 631), (631, 766), (766, 940))[split - 1]
        expected = [lo + round(i * (hi - lo - 2) / 11) for i in range(12)]
        require(call['origin_indices'] == expected
            and call['original_origin_clock_positions'] == [i * 96 + clock for i in expected],
            'training cohort differs')
        base = stable_seed(remote['protocol']['forecast_seed'], 'LV', choice['candidate_id'], choice['tau0'], split)
        require(call['call_seed'] == stable_seed(base, 'quantile_clock', clock), 'matched RNG differs')
        require(call['parent_seals'] == group['parents']
            and call['design_terminal_sha256'] == group['design_terminal_sha256']
            and call['scaler_sha256'] == group['scaler_sha256'], 'training parent/scaler identity differs')
    require(keys == {(s, c) for s in (1, 2, 3) for c in (0, 24, 48, 72)}, 'training cohort incomplete')
    require(saved['model_fit_calls'] == saved['forecast_calls'] == saved['official_outputs_changed'] == 0
        and saved['packet_payloads_verified'] == 32 and saved['official_origins_verified'] == 365,
        'saved-output audit scope differs')
    require(len(remote['packet_evidence']) == 32 and len(remote['folds']) == 3
        and [row['origins'] for row in remote['folds']] == [120, 123, 122], 'saved LV cohort differs')


def _validate_cache(payloads):
    proposal = payloads['EE_CARRY_FORWARD_READINESS.json']
    require(proposal['status'] == 'EE_REUSE_PROPOSAL_PREPARED_NOT_ADMITTED'
        and proposal['closed_scope_restart_authorized'] is False and proposal['new_allocation'] is None,
        'closed cached scope was reopened')
    require(proposal['new_fits'] == proposal['new_forecasts'] == proposal['new_admissions'] == 0,
        'cached execution admitted')
    require(proposal['old_C1'] == 'spent' and proposal['old_C2'] == 'unclaimed_but_closed'
        and proposal['checkpoint_packets'] == 225 and proposal['imported_strict_D'] == 20
        and proposal['remaining_D'] == 58 and proposal['new_S0_max'] == 6
        and proposal['new_full_components_initial_max'] == 64
        and proposal['new_full_components_all_max'] == 82, 'EE scientific counts differ')
    cache = proposal['full_cache_verification'];closed = cache['closed_scope'];master = cache['master']
    require(cache['status'] == 'PASS_CLOSED_CACHED_SCOPE_PRESERVED' and not cache['errors']
        and cache['read_only'] is True and closed['manifest_files'] == 75
        and len(closed['current_manifest']) == 75 and not closed['manifest_mismatches']
        and closed['EE_C1_spent'] is True and closed['EE_C2_exists'] is False
        and closed['cached_restart_authorized'] is False, 'closed cache proof differs')
    require(master['scope_id'] == proposal['original_scope_id'] == SCOPE_ID
        and master['sha256'] == MASTER_SHA256
        and master['start_epoch'] == T0 and master['expires_epoch'] == proposal['original_expiry_epoch'] == EXPIRY
        and master['duration_seconds'] == 43200, 'original cached master/clock differs')
    checkpoints = cache['checkpoints']
    packet_rows = [row for attempt in cache['attempts'] for row in attempt['validated_checkpoint_packets']]
    require(checkpoints['retained_and_validated'] == len(checkpoints['seal_sha256']) == len(packet_rows) == 225
        and checkpoints['strict_new_full_components'] == 0, 'cached checkpoint census differs')
    require(len(cache['attempts']) == 6
        and len({row['path'] for row in packet_rows}) == 225
        and {row['path']: row['sha256'] for row in packet_rows} == checkpoints['seal_sha256'],
        'cached checkpoint identities duplicated or changed')
    drain = closed['actual_drain']
    require(drain['cleanup_verified'] is True and drain['owned_pids'] == []
        and len(drain['owned_units']) == 8
        and set(drain['owned_units']) == {row['unit'] for row in drain['cleanup']}
        and all(row['drained'] is True and row['pids'] == [] for row in drain['cleanup']),
        'cached drain proof differs')
    ledger = proposal['carried_ledger'];charges = cache['charges']
    require(finite_equal(ledger['EE_science_reserved_CPU_seconds'], EE_SCIENCE)
        and finite_equal(charges['EE_cumulative_scientific_CPU_seconds'], EE_SCIENCE)
        and finite_equal(ledger['cached_control_closed_CPU_seconds'], CACHED_CONTROL)
        and finite_equal(charges['cached_control_final_CPU_seconds'], CACHED_CONTROL)
        and ledger['all_failed_probe_and_attempt_debits_retained'] is True
        and ledger['later_baseline_control_ledger_kept_separate'] is True, 'closed ledger differs')


def _verify_sources(payloads):
    status = payloads['SCIENCE_PREPARATION_STATUS.json'];aliases = payloads['READONLY_SOURCE_ALIAS_PROOF.json']
    expected = status['source_sha256']
    require(len(expected) == 10 and aliases['source_sha256'] == expected
        and aliases['matched_remote_preparation_pins'] is True, 'scientific source map differs')
    for name in ('CERTIFICATE_REPAIR_DOSSIER.json', 'LV_CALIBRATION_DOSSIER.json',
            'LV_TRAINING_DIAGNOSTIC_MANIFEST.json'):
        require(payloads[name]['source_sha256'] == expected, 'cross-artifact source map differs')
    for remote, local in aliases['remote_to_local_path'].items():
        require(remote in expected and Path(remote).is_absolute() and Path(local).is_absolute(),
            'unknown scientific-source read alias')
    for path, wanted in expected.items():
        observed = aliases['remote_to_local_path'].get(path, path)
        require(sha256(observed) == wanted, 'frozen scientific source bytes differ: ' + path)
    return len(expected), len(aliases['remote_to_local_path'])


def verify_bundle(bundle):
    bundle = Path(bundle)
    require(bundle.is_absolute() and bundle.is_dir() and not bundle.is_symlink(),
        '--bundle must name an absolute nonsymlink directory')
    path = bundle / 'artifact_manifest.json'
    require(path.is_file() and not path.is_symlink() and path.stat().st_size <= 131072,
        'missing or unsafe science manifest')
    require(sha256(path) == EXPECTED_MANIFEST_SHA256, 'science manifest is not the committed pinned identity')
    manifest = json.loads(path.read_text())
    _verify_artifacts(bundle, manifest)
    payloads = {name: json.loads((bundle / name).read_text()) for name in JSON_FILES}
    status = payloads['SCIENCE_PREPARATION_STATUS.json']
    for name, wanted in status['snapshot_inputs_sha256'].items():
        require(name in ('LOCAL_TARGET_INPUTS.json', 'JEREZ_SAVED_EVIDENCE.json')
            and sha256(bundle / name) == wanted, 'frozen capture identity differs')
    for key in ('new_fits', 'new_forecasts', 'new_admissions', 'cap_changes',
            'certificate_recomputations', 'live_runtime_writes'):
        require(type(status[key]) is int and status[key] == 0, 'science execution was admitted')
    _validate_blockers(payloads);_validate_training(payloads);_validate_cache(payloads)
    sources, alias_count = _verify_sources(payloads)
    receipt = payloads['VALIDATION_RECEIPT.json']
    require(receipt['status'] == 'PASS_INDEPENDENT_REPRODUCTION_AND_SCOPE_GUARDS'
        and len(receipt['generated_JSON_byte_identical']) == 6, 'reproduction receipt differs')
    for row in receipt['generated_JSON_byte_identical']:
        require(row['file'] in EXPECTED_FILES and row['byte_identical'] is True
            and sha256(bundle / row['file']) == row['sha256'], 'reproduced output identity differs')
    return dict(status='PASS_R153_FROZEN_SCIENCE_PREPARATION', bundle=str(bundle),
        manifest_sha256=EXPECTED_MANIFEST_SHA256, verifier_sha256=sha256(Path(__file__)),
        sealed_files=19, scientific_source_files=sources, read_only_source_aliases=alias_count,
        blocking_AL_targets=7, LV_saved_packets=32, prospective_training_calls=12,
        prospective_origin_clock_pairs=144, EE_retained_checkpoints=225,
        scope='Frozen captured evidence and local pinned scientific source bytes; no live remote runtime or model state is re-read',
        model_fits_started=0, forecasts_started=0, source_or_runtime_writes=0,
        dispatch_authorized=False, closed_cached_scope_restart_authorized=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bundle', type=Path, required=True)
    args = parser.parse_args()
    try:
        print(json.dumps(verify_bundle(args.bundle), sort_keys=True, allow_nan=False))
    except (RuntimeError, OSError, KeyError, TypeError, ValueError) as error:
        print(json.dumps(dict(status='FAIL_R153_SCIENCE_PREPARATION', error=str(error)), sort_keys=True), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
