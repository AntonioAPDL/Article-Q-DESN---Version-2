"""Separate one-attempt pilot control journal; never an automatic grant issuer.

The immutable old toy/bridge role table is not changed. Journal events record
already earned, pinned evidence. They do not submit jobs, manufacture a Root
authority, run an optimizer, or promote a candidate into production.
"""
from __future__ import annotations
import copy
import hashlib
import importlib.util
import os
from pathlib import Path
import re
import time

_mp = Path(__file__).absolute().with_name('metadata.py')
_mraw = _mp.read_bytes()
if hashlib.sha256(_mraw).hexdigest() != '6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b':
    raise ValueError('exact metadata helper')
_ms = importlib.util.spec_from_file_location('_r200_dispatch_metadata', _mp)
m = importlib.util.module_from_spec(_ms)
exec(compile(_mraw, str(_mp), 'exec'), m.__dict__)

TARGET = 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              elbo_relative=1e-8, predictor_rms=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, sigma_relative=1e-6)
CASE = dict(target=TARGET, n=48576, p=417, tau=.75, tau0=.0022915214919211734,
            max_iter=300, seed=819509105, max_rhs_iter=20000, tol=1e-5,
            n_samp=20, n_samp_xi=20, maximum_pilot_attempts=1,
            maximum_optimizer_invocations=1, units='original_design_and_response',
            exact_optimizer_resume=False,
            prior=dict(family='rhs_ns', center='zero', shrink_intercept=False,
                       sigma_a=1.0, sigma_b=1.0, freeze_tau_iters=0,
                       freeze_tau_warmup_iters=0),
            acceptance='finite AND(formal OR independent)', limits=LIMITS,
            both_RHS_starts=True, official_test_selection=False)
REQUEST_KEYS = {'schema', 'purpose', 'nonce', 'case', 'scientific_source',
                'controller_source', 'io_request', 'accepted_bridge',
                'price', 'runtime_qualification', 'scope', 'ledger',
                'issued_epoch', 'expires_epoch'}
TRANSITIONS = {
    'PREPARED': {'SOURCE_PHYSICAL_REVIEWED', 'FAILED'},
    'SOURCE_PHYSICAL_REVIEWED': {'OWNER_RELEASE_REVIEWED', 'FAILED'},
    'OWNER_RELEASE_REVIEWED': {'ROOT_RELEASED', 'FAILED'},
    'ROOT_RELEASED': {'RETURNED', 'FAILED'},
    'RETURNED': {'ACCEPTED', 'FAILED'},
    'ACCEPTED': set(), 'FAILED': set(),
}
EXPECTED = {
    'SOURCE_PHYSICAL_REVIEWED': 'PASS_REVIEWED_R200_COMPUTE_SOURCE_PHYSICAL',
    'OWNER_RELEASE_REVIEWED': 'PASS_REVIEWED_R200_OWNER_RELEASE',
    'ROOT_RELEASED': 'ROOT_ADMITTED_NEW_R200_COMPUTE_PURPOSE',
    'RETURNED': 'RETURNED_COMPLETE_R200_PILOT_CANDIDATE',
    'ACCEPTED': 'ACCEPTED_COMPLETE_R200_PILOT_DIAGNOSTIC',
}
BRIDGE_NAMES = {'accepted', 'outer_accept_guard', 'result', 'accounting',
                'independent_review', 'full_return_manifest', 'finalization',
                'bridge_validation', 'factor_state', 'baseline_certificate'}


def exact(value, expected, label):
    m.require(type(value) is type(expected), label + ': exact type')
    if isinstance(expected, dict):
        m.closed(value, expected, label)
        for key in expected:
            exact(value[key], expected[key], label + '.' + key)
    elif isinstance(expected, list):
        m.require(len(value) == len(expected), label + ': exact length')
        for a, b in zip(value, expected):
            exact(a, b, label)
    else:
        m.require(value == expected, label + ': exact value')


def inspect_request(request):
    m.closed(request, REQUEST_KEYS, 'single pilot preparation request')
    m.require(request['schema'] == 'r200_pilot_preparation_request_v1'
              and re.fullmatch('[A-Za-z0-9_]{1,96}', request['purpose'] or '')
              and re.fullmatch('[0-9a-f]{32}', request['nonce'] or ''),
              'new exact pilot purpose/nonce')
    exact(request['case'], CASE, 'fixed NO3 case')
    for key in ('issued_epoch', 'expires_epoch'):
        m.finite(request[key], key)
    m.require(0 < request['expires_epoch'] - request['issued_epoch'] <= 28800,
              'finite fixed at-most-eight-hour purpose')
    source = m.closed(request['scientific_source'], {'kind', 'head', 'branch'}, 'scientific source')
    m.require(type(source['kind']) is str and source['kind']
              and re.fullmatch('[0-9a-f]{40}', source['head'] or '')
              and source['branch'].startswith('work/pricefm-'),
              'preserve complete accepted scientific identity')
    # Missing future evidence is represented by None, never a fabricated PASS.
    for key in ('controller_source', 'io_request', 'accepted_bridge', 'price',
                'runtime_qualification', 'scope', 'ledger'):
        if request[key] is not None:
            m.descriptor(request[key])
    return {'schema': 'r200_pilot_preparation_result_v1',
            'status': 'PREPARED_DESCRIPTORS_NOT_RUNTIME_OR_OPTIMIZER_AUTHORITY',
            'request_sha256': m.digest(request), 'fixed_case': copy.deepcopy(CASE),
            'missing': [key for key in ('controller_source', 'io_request', 'accepted_bridge',
                                       'price', 'runtime_qualification', 'scope', 'ledger')
                        if request[key] is None],
            'runtime_admitted': False, 'can_submit': False, 'can_optimize': False,
            'production_acceptance': False}


def prepare(request, output_root):
    result = inspect_request(request)
    root = m.physical(str(output_root))
    m.require(root.is_dir() and root.stat().st_uid == os.getuid()
              and root.stat().st_mode & 0o077 == 0, 'existing private owned preparation root')
    m.require(not any(root.iterdir()), 'new empty immutable request journal')
    request_pin = m.write_new(root / 'REQUEST.json', request)
    (root / '.transition_claims').mkdir(mode=0o700)
    first = dict(schema='r200_pilot_control_journal_v1', sequence=0, state='PREPARED',
                 request=request_pin, request_sha256=result['request_sha256'],
                 purpose=request['purpose'], nonce=request['nonce'], role='NO3_AL300_PILOT',
                 previous=None, evidence=None, created_epoch=time.time(),
                 record_grants_execution=False, automatic_retry=False)
    return m.write_new(root / '000_PREPARED.json', first)


def _journal(root):
    paths = sorted(root.glob('[0-9][0-9][0-9]_*.json'))
    m.require(1 <= len(paths) <= 7, 'bounded current journal')
    rows = []
    previous = None
    for index, path in enumerate(paths):
        row = m.linked(m.pin_file(path))
        m.require(row.get('schema') == 'r200_pilot_control_journal_v1'
                  and row.get('sequence') == index and type(row.get('sequence')) is int
                  and row.get('previous') == previous
                  and row.get('record_grants_execution') is False
                  and row.get('automatic_retry') is False, 'immutable sequential journal')
        m.require(path.name == '%03d_%s.json' % (index, row['state']), 'exact journal filename')
        if index:
            m.require(row['state'] in TRANSITIONS[rows[-1]['state']]
                      and row['request'] == rows[0]['request']
                      and all(row[k] == rows[0][k] for k in ('purpose', 'nonce', 'role')),
                      'same request, valid forward-only transition')
        else:
            m.require(row['state'] == 'PREPARED', 'first prepared record')
        rows.append(row)
        previous = m.pin_file(path)
    return paths, rows


def record_evidence(root_path, previous_pin, event, evidence_pin):
    root = m.physical(str(root_path))
    paths, rows = _journal(root)
    m.require(previous_pin == m.pin_file(paths[-1]), 'exact latest transition')
    prior = rows[-1]
    m.require(event in TRANSITIONS[prior['state']], 'no retry, restart, skip or terminal reopening')
    request = m.linked(prior['request'])
    inspect_request(request)
    now = time.time()
    m.require(request['issued_epoch'] <= now < request['expires_epoch'], 'unchanged finite purpose')
    proof = m.linked(evidence_pin)
    if event == 'FAILED':
        m.require(proof.get('status') == 'FAILED_R200_PILOT_ATTEMPT_FEES_RETAINED'
                  and proof.get('automatic_retry') is False, 'explicit retained failure')
    else:
        m.require(proof.get('status') == EXPECTED[event], 'actual requested evidence kind')
    for key in ('purpose', 'nonce', 'role'):
        expected = 'NO3_AL300_PILOT' if key == 'role' else request[key]
        m.require(proof.get(key) == expected, 'same exact proof identity')
    if event in {'SOURCE_PHYSICAL_REVIEWED', 'OWNER_RELEASE_REVIEWED', 'ROOT_RELEASED'}:
        m.require(all(request[k] is not None for k in
                      ('controller_source', 'io_request', 'accepted_bridge', 'price',
                       'runtime_qualification', 'scope', 'ledger')),
                  'unissued preparation cannot become an actual runtime transition')
        m.require(proof.get('case_sha256') == m.digest(CASE)
                  and proof.get('spec') is not None, 'complete case/spec binding')
        m.descriptor(proof['spec'])
        # The independently authored peer is required; the dispatcher never
        # creates peer PASS or Root authority records.
        if event != 'ROOT_RELEASED':
            peer = m.descriptor(proof.get('independent_program'))
            m.source_bytes(peer)
            m.require(Path(peer['path']).name == 'pilot_independent_peer.py',
                      'separate independent peer program')
        else:
            m.require(type(proof.get('maximum_calls')) is int and proof['maximum_calls'] == 1
                      and type(proof.get('optimizer_invocations')) is int
                      and proof['optimizer_invocations'] == 1, 'one actual optimizer authority')
    if event in {'RETURNED', 'ACCEPTED'}:
        m.require(proof.get('production_acceptance') is False
                  and proof.get('automatic_dependent_release') is False
                  and proof.get('all_seven_evaluated') is True
                  and proof.get('both_RHS_starts') is True
                  and proof.get('case_sha256') == m.digest(CASE),
                  'candidate diagnostic result, unchanged seven gates')
        for key in ('owned_guard', 'accounting', 'full_retained_inventory',
                    'useful_return_manifest', 'independent_review'):
            m.descriptor(proof.get(key))
    row = dict(prior, sequence=len(rows), state=event, previous=previous_pin,
               evidence=evidence_pin, created_epoch=now)
    # A single fixed create-only claim serializes competing events at this
    # sequence, even when their terminal/event filenames would differ.
    m.write_new(root / '.transition_claims' / ('%03d.json' % len(rows)),
                {'previous': previous_pin, 'event': event, 'evidence': evidence_pin,
                 'purpose': request['purpose'], 'nonce': request['nonce'],
                 'fees_retained_on_partial_failure': True})
    return m.write_new(root / ('%03d_%s.json' % (len(rows), event)), row)


def proof_resolver(aliases):
    """Resolve explicit byte-identical metadata aliases without path rewriting."""
    m.require(type(aliases) is list and 1 <= len(aliases) <= 128, 'finite proof aliases')
    table = {}
    for row in aliases:
        m.closed(row, {'logical', 'physical', 'bytes', 'uid'}, 'proof alias')
        m.descriptor(row['logical']); m.descriptor(row['physical'])
        m.require(row['logical']['sha256'] == row['physical']['sha256']
                  and row['logical']['path'] not in table, 'unique same-byte logical identity')
        m.integer(row['bytes'], 'proof byte length', 1, 16 * 1024**2)
        m.require(type(row['uid']) is int and row['uid'] == os.getuid(), 'actual proof UID')
        table[row['logical']['path']] = row
    def read(pin):
        m.descriptor(pin)
        row = table.get(pin['path'])
        m.require(row is not None and row['logical'] == pin
                  and Path(pin['path']).suffix == '.json', 'closed original metadata proof')
        return m.strict_json(m.read_regular(row['physical']['path'], limit=4 * 1024**2,
                                           expected_sha=pin['sha256'],
                                           expected_uid=row['uid'],
                                           expected_bytes=row['bytes']))
    return read


def validate_accepted_bridge(proofs, aliases, scientific_source):
    """Reconcile real old accepted metadata. RDS contents remain compute-only."""
    m.closed(proofs, BRIDGE_NAMES, 'complete bridge proof set')
    for pin in proofs.values():
        m.descriptor(pin)
    read = proof_resolver(aliases)
    accepted, guard = read(proofs['accepted']), read(proofs['outer_accept_guard'])
    m.require(accepted.get('status') == 'ACCEPTED_COMPLETE_FROZEN525_NUMERICAL_ROLE'
              and accepted.get('role') == 'ZERO_UPDATE_BRIDGE'
              and accepted.get('exact_NO3_zero_update_bridge_proved') is True
              and accepted.get('production_admission') is False
              and accepted.get('pilot_fits') == 0
              and type(accepted.get('pilot_fits')) is int
              and accepted.get('actual_accept_action_guard') == proofs['outer_accept_guard'],
              'actual complete zero-update bridge acceptance')
    flags = ('all_owned_descendants_reaped', 'independent_guardian', 'kernel_escape_filter',
             'orphan_subreaper', 'guardian_included_in_CPU', 'inherited_waited_history_included_once')
    m.require(type(guard.get('returncode')) is int and guard['returncode'] == 0
              and type(guard.get('command_returncode')) is int and guard['command_returncode'] == 0
              and type(guard.get('CPU_limit')) is int and guard['CPU_limit'] == 5
              and guard.get('cap_reason') is None
              and guard.get('guardian_forced_monitor_stop') is False
              and all(guard.get(k) is True for k in flags), 'actual original whole accept guard')
    candidate = m.strict_json(guard['stdout'])
    m.require(dict(candidate, status=accepted['status'],
                   actual_accept_action_guard=proofs['outer_accept_guard']) == accepted,
              'accepted record equals actual guarded candidate')
    for name in ('result', 'accounting', 'independent_review', 'full_return_manifest'):
        m.require(accepted.get(name) == proofs[name], 'exact original accepted proof link')
    result, account, peer, manifest = (read(proofs[x]) for x in
                                      ('result', 'accounting', 'independent_review',
                                       'full_return_manifest'))
    job = accepted['job_id']
    m.require(result.get('status') == 'PASS_COMPLETE_FROZEN525_NUMERICAL_WORKER'
              and result.get('job_id') == account.get('job_id') == peer.get('job_id') == job
              and account.get('terminal') is True and account.get('complete') is True
              and account.get('primary_charge_counted_once') is True
              and peer.get('status') == 'PASS_REVIEWED_COMPLETE_FROZEN525_NUMERICAL_ROLE'
              and peer.get('result') == proofs['result']
              and peer.get('accounting') == proofs['accounting']
              and peer.get('return_manifest') == proofs['full_return_manifest']
              and manifest.get('complete_success') is True, 'complete reviewed actual bridge chain')
    outcome = result.get('outcome', {})
    m.require(outcome.get('status') == 'PASS_HB_EXACT_NO3_ZERO_UPDATE_BRIDGE'
              and outcome.get('current_TSYNC_and_parent_ACK') is True,
              'actual owned bridge computation')
    bridge = read(proofs['bridge_validation'])
    m.require(bridge.get('schema') == 'r154_conditional_state_bridge_v1'
              and bridge.get('status') == 'VERIFIED_ZERO_OPTIMIZER_CONDITIONAL_STATE_BRIDGE'
              and bridge.get('source') == scientific_source and bridge.get('target_name') == TARGET
              and type(bridge.get('optimizer_updates')) is int and bridge['optimizer_updates'] == 0
              and bridge.get('factor_state') == proofs['factor_state']
              and bridge.get('baseline_certificate_pin') == proofs['baseline_certificate']
              and bridge.get('original_failed_state_modified') is False
              and bridge.get('production_acceptance_authority') is False,
              'unchanged scientific identity, factors, prior and original failed state')
    m.require(all(bridge.get(k) is True for k in (
        'full_state_factors_verified', 'explicit_factor_elbo_verified',
        'original_seven_certificate_computed', 'rhs_unit_and_dispersed_verified',
        'source_recipe_reproduced')), 'complete bridge numerical acceptance facts')
    final = read(proofs['finalization'])
    m.require(final.get('status') == 'PRIOR_ACTION_GUARD_VALIDATED'
              and final.get('action') == 'accept'
              and final.get('guard') == proofs['outer_accept_guard'],
              'actual original healthy accept finalization')
    # Manifest hashes establish descriptors only; no RDS/array is opened here.
    rows = manifest.get('files')
    m.require(type(rows) is list and len(rows) == len({x.get('relative') for x in rows}),
              'unique complete bridge return inventory')
    for name, relative in (('factor_state', 'numerical/bridge/full_state.rds'),
                           ('baseline_certificate', 'numerical/bridge/baseline_certificate.json')):
        matches = [x for x in rows if x.get('relative') == relative]
        m.require(len(matches) == 1 and matches[0].get('sha256') == proofs[name]['sha256']
                  and type(matches[0].get('bytes')) is int and 0 < matches[0]['bytes'] <= 16 * 1024**2,
                  'exact retained bridge factor/certificate byte descriptor')
    return {'status': 'PASS_ACTUAL_ACCEPTED_BRIDGE_METADATA_CLOSURE_NOT_RDS_IMPORT',
            'job_id': job, 'scientific_source': scientific_source,
            'scientific_payload_read': False, 'runtime_admitted': False}

