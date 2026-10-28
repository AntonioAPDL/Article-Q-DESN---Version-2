"""Append-only R154 candidate evidence and explicit future resolution checks.

No model execution, dependency release, service operation, or original packet
mutation exists here. A candidate registration alone never changes resolution.
All public approval-pin arguments must come from the root control plane; a JSON
status string is not an independent authentication mechanism.
"""
from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import math
from pathlib import Path, PurePosixPath
import re

MANIFEST_PATH = '/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r154_certificate_reference_20261026/application/config/pricefm/522_fixed_state_targets.json'
MANIFEST_SHA256 = 'aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8'
NO3 = 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
AT = 'iq_AT_r134_7a422c0c3473f81f_t1.632090846764e-03_s1_al0.50'
ALLOWED_TARGETS = frozenset((NO3, AT))
SOURCE_KIND = 'R154_project_fullstate_consumer_pinned_CRAN111'
LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              predictor_rms=1e-6, sigma_relative=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, elbo_relative=1e-8)
PRIOR = dict(family='rhs_ns', center='zero', shrink_intercept=False,
             sigma_a=1.0, sigma_b=1.0, freeze_tau_iters=0,
             freeze_tau_warmup_iters=0)
UNITS = 'original_design_and_response'
ACCEPTANCE = 'finite AND (formal OR independent)'
OPERATORS = frozenset(('cdf_pool_clipped', 'mean_feature', 'path_specific', 'normal_driver'))
SCORES = ('AQL', 'qdesn_AQL', 'pricefm_AQL', 'operational_pricefm_AQL')

_spec=importlib.util.spec_from_file_location('r157_native_runtime',Path(__file__).with_name('527_native_runtime.py'))
native=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(native)


def require(value, message):
    if not value:
        raise ValueError(message)


def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for chunk in iter(lambda: stream.read(1048576), b''):
            h.update(chunk)
    return h.hexdigest()


def read(path):
    return json.loads(Path(path).read_text())


def pin(path):
    return dict(path=str(Path(path).resolve()), sha256=digest(path))


def verify_pin(value):
    require(isinstance(value, dict) and set(value) == {'path', 'sha256'}, 'invalid file pin')
    path = Path(value['path'])
    require(path.is_absolute() and not path.is_symlink() and path.is_file(), 'pin is not a regular absolute file')
    require(re.fullmatch('[0-9a-f]{64}', value['sha256']) is not None, 'invalid sha256')
    require(digest(path) == value['sha256'], 'file pin differs: ' + str(path))
    return path


def pinned_json(value):
    return read(verify_pin(value))


def immutable_json(path, value):
    encoded = json.dumps(value, sort_keys=True, indent=2, allow_nan=False) + '\n'
    with open(path, 'x', encoding='utf-8') as stream:
        stream.write(encoded)


def load_original_manifest(path=MANIFEST_PATH, expected_sha=MANIFEST_SHA256):
    require(digest(path) == expected_sha, 'original seven-target manifest differs')
    manifest = read(path)
    require(len(manifest['targets']) == 7 and len({t['name'] for t in manifest['targets']}) == 7,
            'original seven-target set missing or duplicated')
    scope = manifest['scope']
    require(scope['limits'] == LIMITS and scope['prior'] == PRIOR and scope['units'] == UNITS,
            'original numerical contract differs')
    require(scope['caps'] == {'Normal': 2000, 'AL': 300} and scope['acceptance'] == ACCEPTANCE,
            'original caps or acceptance logic differ')
    return manifest


def target_record(manifest, name, selected_only=True):
    if selected_only:
        require(name in ALLOWED_TARGETS, 'target outside two-pilot allowlist')
    matches = [t for t in manifest['targets'] if t['name'] == name]
    require(len(matches) == 1, 'target is not uniquely in original manifest')
    return matches[0]


def source_identity(source):
    require(isinstance(source, dict) and source.get('kind') == SOURCE_KIND, 'untruthful pilot source class')
    require(source.get('branch', '').startswith(('work/pricefm-r154-fullstate-pilot-adapter-',
            'work/pricefm-r157-native-bootstrap-')), 'wrong project branch')
    require(re.fullmatch('[0-9a-f]{40}', source.get('head', '')) is not None, 'source commit is not exact')
    return source


def certificate_acceptance(terminal):
    require(terminal.get('all_seven_certificate_computed') is True, 'seven-gate certificate missing')
    certificate = terminal['independent_certificate']
    require(certificate['limits'] == LIMITS and set(certificate['measures']) == set(LIMITS),
            'certificate limits or measure set changed')
    checks = []
    for key, limit in LIMITS.items():
        value = certificate['measures'][key]
        if value is None:  # Explicit computed nonfinite/NA value, not a missing gate.
            checks.append(False)
            continue
        require(not isinstance(value, bool) and isinstance(value, (int, float)), 'non-numeric certificate measure')
        require(not math.isfinite(value) or value >= 0, 'negative residual measure')
        checks.append(math.isfinite(value) and value <= limit)
    rhs = certificate['rhs_reconstruction']
    independent = all(checks) and rhs.get('unit_converged') is True and rhs.get('dispersed_converged') is True
    require(certificate.get('certified') is independent, 'independent certificate flag disagrees with gates')
    require(type(terminal.get('finite_core')) is bool and type(terminal.get('formal_converged')) is bool,
            'finite/formal flags are not raw booleans')
    accepted = terminal['finite_core'] and (terminal['formal_converged'] or independent)
    require(terminal.get('computationally_certified') is accepted, 'acceptance differs from finite AND(formal OR independent)')
    require(terminal.get('acceptance_logic') == ACCEPTANCE, 'acceptance expression changed')
    return accepted


def _validate_bridge(terminal, target, expected_source):
    bridge = pinned_json(terminal['initializer']['bridge'])
    require(bridge.get('schema') == 'r154_conditional_state_bridge_v1', 'not a real conditional-state bridge')
    for key in ('target_name', 'posterior_target_sha256', 'source', 'units', 'prior'):
        expected = terminal[key]
        require(bridge.get(key) == expected, 'bridge identity differs: ' + key)
    require(bridge.get('optimizer_updates') == 0, 'bridge ran an optimizer')
    for key in ('full_state_factors_verified', 'explicit_factor_elbo_verified',
                'original_seven_certificate_computed', 'rhs_unit_and_dispersed_verified',
                'source_recipe_reproduced'):
        require(bridge.get(key) is True, 'bridge proof missing: ' + key)
    verify_pin(bridge['factor_state'])
    references = bridge.get('data_references')
    require(isinstance(references, dict) and set(references) == {'X', 'y'}, 'bridge X/y references missing')
    X = verify_pin(references['X']); y = verify_pin(references['y'])
    require(X.name == 'X.bin' and y.name == 'y.bin' and X.parent == y.parent, 'bridge changed design layout')
    design_terminal = X.parent / 'terminal.json'
    require(digest(design_terminal) == target['contract']['design_terminal_sha256'], 'bridge design terminal differs from original target')
    design_files = read(design_terminal)['files']
    require(references['X']['sha256'] == design_files['X.bin'] and references['y']['sha256'] == design_files['y.bin'],
            'bridge X/y differ from the original sealed design')
    if 'baseline_certificate_pin' in bridge:
        baseline = pinned_json(bridge['baseline_certificate_pin'])
        require(set(baseline['measures']) == set(LIMITS) and baseline['limits'] == LIMITS,
                'bridge baseline certificate differs')
    return bridge


def _validate_checkpoints(terminal, bridge):
    index = pinned_json(terminal['checkpoint_index'])
    require(index.get('schema') == 'r154_fullstate_checkpoint_index_v1', 'wrong checkpoint schema')
    for key in ('target_name', 'posterior_target_sha256', 'source'):
        require(index.get(key) == terminal[key], 'checkpoint identity differs: ' + key)
    require(index.get('data_references') == bridge.get('data_references') and index.get('data_references'),
            'checkpoint immutable X/y references differ or missing')
    references = index['data_references']
    require(set(references) == {'X', 'y'}, 'checkpoint data reference surface differs')
    for value in references.values():
        verify_pin(value)
    entries = index['checkpoints']
    sweeps = [item['completed_sweep'] for item in entries]
    require(sweeps == list(range(1, terminal['completed_sweeps'] + 1)), 'checkpoint sequence incomplete')
    for item in entries:
        require(item.get('contains_all_factors_and_schedules') is True, 'checkpoint omitted factors/schedules')
        verify_pin(item['state_pin'])
    return index


def _validate_reaped_ledger(value, target_name, expected_source):
    ledger = pinned_json(value)
    require(ledger.get('status') == 'PILOT_REAPED' and ledger.get('source') == expected_source and
            ledger.get('target_name') == target_name, 'unreaped/foreign pilot ledger')
    require(type(ledger.get('returncode')) is int and ledger['returncode'] == 0,
            'pilot ledger did not exit successfully')
    new=native.new_source(expected_source)
    flags = native.FLAGS if new else ('reaped', 'drained', 'CPU_accounting_complete',
             'preexec_kernel_boundary_proved', 'subprocess_creation_kernel_denied')
    require(all(ledger.get(key) is True for key in flags), 'pilot ledger guard/drain proof incomplete')
    guard = pinned_json(ledger['owned_guard_receipt_pin'])
    require(guard.get('schema') == ('r157_traced_bootstrap_guard_receipt_v1' if new else 'r154_owned_stage_guard_receipt_v1') and
            guard.get('status') == 'EXITED' and type(guard.get('returncode')) is int and
            guard['returncode'] == 0 and all(guard.get(key) is True for key in flags),
            'owned child was aborted, unaccounted, unproved or undrained')
    if new:native.require_completed(guard)
    require(guard.get('source') == expected_source and guard.get('target_name') == target_name,
            'owned guard receipt belongs to another source/target')
    if 'root_grant_sha256' in ledger:
        require(guard.get('root_grant_sha256') == ledger['root_grant_sha256'],
                'owned guard receipt belongs to another admission')
    require(ledger.get('all_parent_lineage_costs_paid') is True and ledger.get('original_failed_costs_refunded') is False,
            'lineage CPU costs are unpaid/refunded')
    cost = ledger.get('child_CPU_seconds')
    require(not isinstance(cost, bool) and isinstance(cost, (int, float)) and math.isfinite(cost) and cost >= 0,
            'invalid whole-child CPU cost')
    require(guard.get('child_CPU_seconds') == cost, 'owned guard receipt and ledger CPU differ')
    funding = pinned_json(ledger['funding_pin'])
    reserve = funding.get('reserved_parent_and_finalize_CPU_seconds')
    admin = ledger.get('administrative_CPU_seconds_including_startup_and_reaped_helpers')
    actual = ledger.get('actual_whole_stage_CPU_seconds_at_ledger')
    tail = ledger.get('reserved_finalization_tail_CPU_seconds')
    for value in (reserve, admin, actual, tail):
        require(type(value) in (int, float) and math.isfinite(value) and value >= 0,
                'whole-stage funding/accounting value missing or invalid')
    require(reserve > 0 and admin + tail <= reserve and actual >= cost and
            math.isclose(actual, cost + admin, rel_tol=1e-12, abs_tol=1e-9),
            'whole-stage administrative/finalization cost is underfunded')
    require(ledger.get('whole_stage_debit_CPU_seconds') == max(actual, cost + reserve),
            'whole-stage reservation debit understated')
    return ledger


def _validate_finalization_accounting(value, candidate, expected_source):
    path = verify_pin(value)
    require(path == Path(candidate['root']) / 'finalization_accounting.json',
            'finalization accounting is not the exact candidate accounting file')
    accounting = read(path)
    terminal = candidate['terminal']
    ledger = _validate_reaped_ledger(terminal['ledger_pin'], terminal['target_name'], expected_source)
    funding = pinned_json(ledger['funding_pin'])
    reserve = funding['reserved_parent_and_finalize_CPU_seconds']
    require(accounting.get('status') == 'WITHIN_RESERVED_PARENT_AND_FINALIZATION' and
            accounting.get('source') == expected_source and
            accounting.get('target_name') == terminal['target_name'] and
            accounting.get('candidate_registration_not_yet_started') is True,
            'finalization accounting is failed, foreign or late')
    actual = accounting.get('actual_whole_stage_CPU_seconds')
    admin = accounting.get('administrative_CPU_seconds_including_startup_and_reaped_helpers')
    require(all(type(x) in (int, float) and math.isfinite(x) and x >= 0 for x in (actual, admin)),
            'finalization accounting values invalid')
    require(accounting.get('reserved_parent_and_finalize_CPU_seconds') == reserve and
            admin <= reserve and actual >= ledger['actual_whole_stage_CPU_seconds_at_ledger'] and
            math.isclose(actual, ledger['child_CPU_seconds'] + admin, rel_tol=1e-12, abs_tol=1e-9) and
            accounting.get('whole_stage_debit_CPU_seconds') == max(actual, ledger['child_CPU_seconds'] + reserve),
            'finalization cost/debit exceeds or understates the funded reservation')
    return accounting


def validate_candidate_packet(root, manifest, expected_source):
    """Validate a completed candidate, accepted or failed, without activating it."""
    root = Path(root)
    require(manifest == load_original_manifest(), 'caller changed original seven-target manifest')
    require(root.is_dir() and not root.is_symlink(), 'candidate directory invalid')
    terminal = read(root / 'terminal.json')
    core = read(root / 'terminal_core.json')
    require('ledger_pin' not in core and terminal == dict(core, ledger_pin=terminal.get('ledger_pin')),
            'finalizer changed core acceptance/source evidence or guessed a future ledger')
    require(terminal.get('schema') == 'r154_project_consumer_candidate_v1', 'not a project candidate')
    require(terminal.get('record_kind') == 'pilot_candidate_no_automatic_release' and
            terminal.get('origin') == 'sealed_real_target_project_consumer', 'toy/diagnostic packets cannot be candidates')
    require(source_identity(terminal['source']) == expected_source, 'candidate source differs from reviewed source')
    target = target_record(manifest, terminal['target_name'])
    for key in ('posterior_target_sha256', 'n', 'p', 'tau', 'tau0', 'seed'):
        require(terminal.get(key) == target[key], 'candidate target differs: ' + key)
    require(terminal.get('original_failed') == target['bindings'], 'original failed lineage pins differ')
    require(terminal.get('original_manifest_sha256') == MANIFEST_SHA256, 'original seven-manifest pin differs')
    require(terminal.get('units') == UNITS and terminal.get('prior') == PRIOR, 'units or prior changed')
    require(terminal.get('test_opened') is False and terminal.get('prior_center_from_initializer') is False,
            'test exposure or prior-center contract changed')
    initializer = terminal['initializer']
    require(initializer.get('kind') == 'conditional_reconstruction_new_initialization' and
            initializer.get('exact_optimizer_resume') is False and initializer.get('prior_center_from_initializer') is False,
            'initializer is not the approved new conditional initialization')
    require(terminal.get('max_iter') == 300 and terminal.get('new_attempt_index') == 1 and
            terminal.get('maximum_new_attempts') == 1, 'new-attempt cap/history differs')
    require(terminal.get('prior_attempt_iterations') == target['stored_terminal']['iterations'], 'old iteration history missing')
    sweeps = terminal.get('completed_sweeps')
    require(type(sweeps) is int and 1 <= sweeps <= 300, 'fresh sweep count outside cap')
    require(terminal.get('old_completed_artifacts_modified') is False and terminal.get('automatic_dependant_release') is False,
            'candidate changed old flags or released dependants')
    accepted = certificate_acceptance(terminal)
    for name, size in (('beta_mean.bin', target['p'] * 8), ('beta_cov.bin', target['p'] ** 2 * 8)):
        path = root / name
        require(path.is_file() and not path.is_symlink() and path.stat().st_size == size,
                'candidate compact moment artifact dimensions differ')
    for name in ('vb_trace.csv', 'final_state.rds'):
        require((root / name).is_file() and not (root / name).is_symlink(), 'candidate missing ' + name)
    bridge = _validate_bridge(terminal, target, expected_source)
    admission = pinned_json(terminal['admission_pin'])
    require(admission.get('status') == 'ROOT_ADMITTED_NEW_INITIALIZATION_PILOT_ONLY', 'missing pilot authority')
    for key in ('target_name', 'source', 'max_iter', 'new_attempt_index'):
        require(admission.get(key) == terminal[key], 'admission identity differs: ' + key)
    runtime = pinned_json(terminal['runtime_pin'])
    require(runtime.get('status') == 'VERIFIED_EXECUTION_RUNTIME' and runtime.get('source') == expected_source and
            runtime.get('package_repository') == 'CRAN' and runtime.get('package_version') == '1.1.1' and
            runtime.get('host', '').split('.')[0] == 'muscat', 'runtime provenance differs')
    verify_pin(runtime['actual_R_runtime_binding'])
    _validate_reaped_ledger(terminal['ledger_pin'], terminal['target_name'], expected_source)
    _validate_checkpoints(terminal, bridge)
    return dict(terminal=terminal, accepted=accepted, target=target, bridge=bridge)


def _guard_new_output_root(root, manifest):
    require(manifest == load_original_manifest(), 'write guard requires exact original seven-target manifest')
    resolved = Path(root).resolve()
    for target in manifest['targets']:
        campaign = Path(target['contract']['output_dir']).parents[2].resolve()
        require(resolved != campaign and campaign not in resolved.parents,
                'append-only pilot output cannot modify an original campaign')


def finalize_terminal_core(root, ledger_pin, manifest, expected_source):
    """Create only terminal.json from immutable R core plus actual reaped ledger.

    Failure after exclusive creation remains an immutable failed finalization;
    no automatic rewrite, retry or acceptance-field repair is attempted.
    """
    root = Path(root); _guard_new_output_root(root, manifest)
    core = read(root / 'terminal_core.json')
    require('ledger_pin' not in core, 'core guessed a future ledger hash')
    _validate_reaped_ledger(ledger_pin, core.get('target_name'), expected_source)
    immutable_json(root / 'terminal.json', dict(core, ledger_pin=ledger_pin))
    return validate_candidate_packet(root, manifest, expected_source)


def _relative_file(root, name):
    part = PurePosixPath(name)
    require(not part.is_absolute() and part.parts and '..' not in part.parts, 'unsafe packet artifact path')
    path = Path(root).joinpath(*part.parts)
    require(path.is_file() and not path.is_symlink(), 'packet artifact is not a regular file')
    require(Path(root).resolve() in path.resolve().parents, 'packet artifact escapes root')
    return path


def seal_candidate_packet(root, manifest, expected_source):
    _guard_new_output_root(root, manifest)
    validated = validate_candidate_packet(root, manifest, expected_source)
    root = Path(root)
    artifacts = {}
    for path in sorted(root.rglob('*')):
        require(not path.is_symlink(), 'candidate tree contains a symlink')
        if path.is_file() and path != root / 'completed_evidence.json':
            artifacts[path.relative_to(root).as_posix()] = digest(path)
    require('terminal.json' in artifacts, 'terminal missing from candidate seal')
    seal = dict(schema='r154_project_candidate_seal_v1', source=expected_source,
                target_name=validated['terminal']['target_name'], accepted=validated['accepted'],
                candidate_only=True, automatic_dependant_release=False, artifacts=artifacts)
    immutable_json(root / 'completed_evidence.json', seal)
    return pin(root / 'completed_evidence.json')


def validate_candidate_seal(value, manifest, expected_source):
    path = verify_pin(value); seal = read(path); root = path.parent
    require(seal.get('schema') == 'r154_project_candidate_seal_v1' and seal.get('source') == expected_source,
            'wrong candidate seal source/class')
    require(seal.get('candidate_only') is True and seal.get('automatic_dependant_release') is False,
            'candidate seal attempted automatic promotion')
    require(isinstance(seal.get('artifacts'), dict) and 'terminal.json' in seal['artifacts'], 'candidate artifact manifest missing')
    for name, expected in seal['artifacts'].items():
        require(digest(_relative_file(root, name)) == expected, 'candidate artifact seal mismatch')
    validated = validate_candidate_packet(root, manifest, expected_source)
    require(seal.get('target_name') == validated['terminal']['target_name'] and seal.get('accepted') is validated['accepted'],
            'candidate seal acceptance/target differs')
    return dict(validated, root=str(root), seal_pin=value)


def register_candidate(registry_root, candidate_seal_pin, manifest, expected_source):
    validated = validate_candidate_seal(candidate_seal_pin, manifest, expected_source)
    accounting_pin = pin(Path(validated['root']) / 'finalization_accounting.json')
    _validate_finalization_accounting(accounting_pin, validated, expected_source)
    root = Path(registry_root); _guard_new_output_root(root, manifest)
    root.mkdir(parents=True, exist_ok=True)
    require(not root.is_symlink(), 'registry directory is a symlink')
    target = validated['terminal']['target_name']
    record = dict(schema='r154_candidate_registration_v1', status='CANDIDATE_ONLY_NO_DEPENDANT_RELEASE',
        target_name=target, posterior_target_sha256=validated['target']['posterior_target_sha256'],
        source=expected_source, original_manifest_sha256=MANIFEST_SHA256,
        candidate_seal_pin=candidate_seal_pin, finalization_accounting_pin=accounting_pin,
        accepted=validated['accepted'],
        automatic_dependant_release=False, original_failed_artifacts_preserved=True)
    path = root / (candidate_seal_pin['sha256'] + '.json')
    immutable_json(path, record)
    return pin(path)


def validate_registration(value, manifest, expected_source):
    record = pinned_json(value)
    require(record.get('schema') == 'r154_candidate_registration_v1' and
            record.get('status') == 'CANDIDATE_ONLY_NO_DEPENDANT_RELEASE' and
            record.get('source') == expected_source, 'not a reviewed-source candidate registration')
    require(record.get('automatic_dependant_release') is False and record.get('original_failed_artifacts_preserved') is True,
            'registration changed original resolution')
    require(record.get('original_manifest_sha256') == MANIFEST_SHA256, 'registration original manifest pin differs')
    candidate = validate_candidate_seal(record['candidate_seal_pin'], manifest, expected_source)
    _validate_finalization_accounting(record['finalization_accounting_pin'], candidate, expected_source)
    require(record.get('target_name') == candidate['terminal']['target_name'] and
            record.get('posterior_target_sha256') == candidate['target']['posterior_target_sha256'] and
            record.get('accepted') is candidate['accepted'], 'registration fields differ from sealed candidate')
    return dict(record=record, candidate=candidate)


def branch_predecessor(target_name, predecessor_registration_pin, manifest, expected_source):
    target_record(manifest, target_name)
    if target_name == NO3:
        require(predecessor_registration_pin is None, 'NO3 first branch has no predecessor')
        return None
    require(predecessor_registration_pin is not None, 'AT blocked until exact NO3 pilot accepts')
    predecessor = validate_registration(predecessor_registration_pin, manifest, expected_source)
    require(predecessor['record']['target_name'] == NO3 and predecessor['candidate']['accepted'] is True,
            'NO3 failure stops this pilot branch')
    return predecessor


def resolve_effective_task(target_name, original_packet, manifest, expected_source,
                           registration_pin=None, root_approval_pin=None):
    """Default returns original packet even when an accepted candidate exists."""
    target_record(manifest, target_name)
    if root_approval_pin is None:
        return dict(packet=str(original_packet), resolution='original_unchanged', candidate_activated=False)
    require(registration_pin is not None, 'explicit resolution lacks candidate registration')
    registered = validate_registration(registration_pin, manifest, expected_source)
    require(registered['record']['target_name'] == target_name and registered['candidate']['accepted'], 'failed/wrong candidate cannot resolve')
    approval = pinned_json(root_approval_pin)
    require(approval.get('schema') == 'r154_explicit_candidate_resolution_v1' and
            approval.get('status') == 'ROOT_APPROVED_EFFECTIVE_TASK_ONLY' and
            approval.get('authorizes_effective_task_resolution') is True and
            approval.get('authorizes_automatic_dependant_release') is False,
            'explicit root resolution authority missing')
    require(approval.get('target_name') == target_name and approval.get('source') == expected_source and
            approval.get('registration_pin') == registration_pin and
            approval.get('candidate_seal_pin') == registered['record']['candidate_seal_pin'], 'stale/foreign effective-task approval')
    return dict(packet=registered['candidate']['root'], resolution='explicit_root_approved_project_candidate',
                candidate_activated=True, source=expected_source, registration_pin=registration_pin,
                candidate_seal_pin=registered['record']['candidate_seal_pin'])


def validate_full_region_packet(root, root_approval_pin, manifest, expected_source):
    """Prepared new-source full-region route; never equates one pilot with closure.

    Read-only metadata must be locally available or materialized as an explicitly
    sealed snapshot. This function performs no remote access or live wiring.
    """
    root = Path(root); approval = pinned_json(root_approval_pin); terminal = read(root / 'terminal.json')
    source_identity(expected_source)
    require(approval.get('schema') == 'r154_full_region_collection_approval_v1' and
            approval.get('status') == 'ROOT_APPROVED_FULL_REGION_COLLECTION_ONLY', 'regional root approval missing')
    region = approval['region']
    require(region in ('AT', 'NO_3') and approval.get('source') == expected_source, 'regional source/region differs')
    require(terminal.get('schema') == 'r154_project_consumer_region_v1' and
            terminal.get('status') == 'R154_PROJECT_CONSUMER_REGION_COMPLETE_NOT_PROMOTED' and
            terminal.get('source') == expected_source and terminal.get('region') == region,
            'regional packet masquerades as historical source')
    require(terminal.get('complete_folds') == 3 and terminal.get('complete_regions') == 1 and
            terminal.get('test_used_for_selection') is False and terminal.get('same_target_relative_to_selected_model') is True,
            'regional completeness or selection contract differs')
    require(terminal.get('selection_labels') == approval.get('selection_labels') and terminal.get('selection_labels'),
            'exposed/nonconfirmatory labels missing or changed')
    require(terminal.get('task_inventory_pin') == approval.get('task_inventory_pin'), 'regional task inventory differs')
    inventory = pinned_json(terminal['task_inventory_pin'])
    require(inventory.get('schema') == 'r154_source_qualified_region_task_inventory_v1' and
            inventory.get('region') == region and inventory.get('source') == expected_source, 'inventory source differs')
    tasks = inventory['tasks']; names = [t['name'] for t in tasks]
    require(len(names) == len(set(names)) and set(names) == set(approval['required_task_names']), 'inventory omitted/duplicated required tasks')
    original_failures = {t['name'] for t in manifest['targets'] if t['region'] == region}
    require(original_failures <= set(names), 'one pilot cannot omit other original regional failures')
    for task in tasks:
        if task['name'] in original_failures:
            require('resolution_approval_pin' in task, 'original failed task needs an explicit accepted resolution')
        if 'resolution_approval_pin' in task:
            resolved = resolve_effective_task(task['name'], task['original_packet'], manifest, expected_source,
                task['registration_pin'], task['resolution_approval_pin'])
            require(task['evidence_pin'] == resolved['candidate_seal_pin'], 'inventory does not bind exact effective packet')
        else:
            evidence_path = verify_pin(task['evidence_pin']); evidence = read(evidence_path)
            require(evidence.get('metadata', {}).get('certified') is True, 'unaccepted original task blocks regional closure')
            require(isinstance(evidence.get('artifacts'), dict) and evidence['artifacts'], 'original task artifact seal missing')
            for name, expected in evidence['artifacts'].items():
                require(digest(_relative_file(evidence_path.parent, name)) == expected, 'original task artifact seal differs')
    seal = read(root / 'closeout/completed_evidence.json')
    require(seal.get('schema') == 'r154_project_region_seal_v1' and seal.get('source') == expected_source and
            seal.get('task_inventory_pin') == terminal['task_inventory_pin'], 'regional seal source/inventory differs')
    artifacts = seal['artifacts']
    require('fold_comparison.csv' in artifacts, 'regional fold table seal missing')
    for name, expected in artifacts.items():
        require(digest(_relative_file(root / 'closeout', name)) == expected, 'regional closeout artifact differs')
    with open(root / 'closeout/fold_comparison.csv', newline='') as stream:
        rows = list(csv.DictReader(stream))
    require(len(rows) == 12, 'regional table must have twelve operator/fold rows')
    keys = set()
    for row in rows:
        require(row['region'] == region and row['operator'] in OPERATORS and row['fold'] in ('1', '2', '3'), 'invalid regional row identity')
        key = (row['fold'], row['operator']); require(key not in keys, 'duplicated regional row'); keys.add(key)
        for field in SCORES:
            score = float(row[field]); require(math.isfinite(score) and score >= 0, 'invalid regional score')
    require(keys == {(str(f), operator) for f in (1, 2, 3) for operator in OPERATORS}, 'regional operator/fold surface incomplete')
    return dict(region=region, source=expected_source, source_class='R154_project_fullstate_pilot_region',
                complete_folds=3, complete_regions=1, rows=rows, promotion_authority=False)
