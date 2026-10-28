"""Future-only exact AUTHORIZED/PENDING cost refresh; no module mutation.

Constructing this bridge performs no scheduler query, authority or job action.
Calling the returned refresh function retains all stock observation/overlap
checks and finite observer bounds. Only its two named globals are replaced.
"""
import ast
import copy
import inspect
from pathlib import Path


def _legacy_snapshot(admission):
    path = admission.CENTRAL / 'cost_only_registry.json'
    lock = admission.CENTRAL / 'cost_only_registry.lock'
    if not path.is_file() or not lock.is_file():
        raise admission.AdmissionError('existing canonical cost registry and lock required')
    with admission.r.lock(lock):
        state = admission.rd.metadata(path)
    if (state.get('schema') != admission.cost.SCHEMA or state.get('owner') != admission.policy.OWNER
            or not isinstance(state.get('claims'), dict) or not isinstance(state.get('spent_regions'), dict)):
        raise admission.AdmissionError('canonical legacy cost identity differs')
    return state


def make_refresh_bridge(admission, *, expected_claim, expected_release, expected_legacy_claim,
                        legacy_snapshot):
    """Compile unchanged refresh AST with an exact same-intent held binding.

    The caller must pin/review this helper separately. It does not replace an
    immutable release request, advance either ledger, or issue authority.
    """
    claim = copy.deepcopy(expected_claim)
    release = copy.deepcopy(expected_release)
    legacy = copy.deepcopy(expected_legacy_claim)
    task = claim.get('task', {})
    study = release.get('study')
    legacy_key = claim.get('legacy_cost_key')
    if (study not in {'FI','DK2'} or claim.get('state') != 'AUTHORIZED'
            or task.get('purpose') != 'COST_ONLY' or task.get('study') != study
            or release.get('purpose') != 'COST_ONLY'
            or release.get('task_key') != claim.get('task_key')
            or release.get('plan_sha256') != task.get('plan_sha256')
            or release.get('scientific_exclusion_key') != task.get('scientific_exclusion_key')
            or release.get('resources') != claim.get('resources')
            or release.get('remote_root') != claim.get('remote_root')
            or release.get('policy_pin') != claim.get('policy_pin')
            or release.get('scope_id') != claim.get('scope_id')
            or release.get('resources', {}).get('cpus') != 1
            or release['resources'].get('cpu_seconds') != 1200 or release['resources'].get('wall_seconds') != 1200
            or legacy.get('task_key') != legacy_key or legacy.get('state') != 'AUTHORIZED'
            or legacy.get('job_id') != claim.get('job_id')
            or not admission.re.fullmatch(r'[a-f0-9]{64}',str(claim.get('authority_sha256','')))
            or legacy.get('authority_sha256') != claim.get('authority_sha256')
            or legacy.get('reserved_CPU_seconds') != 1200 or legacy.get('wall_seconds') != 1200
            or legacy.get('scope_id') != claim.get('scope_id')
            or legacy.get('config_sha256') != claim.get('config_sha256')
            or legacy.get('task', {}).get('study') != study
            or legacy['task'].get('plan_sha256') != task.get('plan_sha256')
            or legacy['task'].get('scientific_exclusion_key') != task.get('scientific_exclusion_key')
            or legacy.get('release_sha256') != claim.get('release_sha256')
            or legacy.get('release_path') != claim.get('release_path')
            or legacy.get('remote_root') != claim.get('remote_root')
            or not admission.re.fullmatch(r'[1-9][0-9]*', str(claim.get('job_id', '')))):
        raise admission.AdmissionError('exact authorized cost pair and paid1200 intent required')
    source_pin = release.get('source_hashes', {}).get('admission.py')
    if source_pin != admission.r.digest(Path(admission.__file__)):
        raise admission.AdmissionError('bridge requires the sealed immutable admission source')
    stock_refresh = admission.refresh_request
    stock_selector = admission.select_node

    def canonical_claims(packet, expected_plan_sha, exclusion_key, self_claim=None):
        state = admission._state_snapshot()
        own = state['claims'].get(claim['task_key'])
        if (own != claim or self_claim != claim or expected_plan_sha != task['plan_sha256']
                or exclusion_key != task['scientific_exclusion_key']
                or packet.get('scope_id') is None or admission.policy.hb_concurrency(packet) < 1
                or admission._release(own) != release):
            raise admission.AdmissionError('held self claim/release changed or wrong intent supplied')
        if any(value.get('state') not in admission.FINAL and key != claim['task_key']
                for key, value in state['claims'].items()):
            raise admission.AdmissionError('every other canonical HB claim must be drained')
        # The separately reviewed replacement protocol supplies its complete
        # authoritative readonly legacy view. This helper cannot reserve,
        # replace, rewrite or hide an old spent-region ledger.
        legacy_state = legacy_snapshot()
        if (legacy_state['claims'].get(legacy_key) != legacy
                or legacy_state['spent_regions'].get(study) != legacy_key
                or any(value.get('state') not in admission.cost.FINAL and key != legacy_key
                       for key, value in legacy_state['claims'].items())):
            raise admission.AdmissionError('authorized legacy intent changed or another cost claim is active')
        return state, own, []

    def select_node(snapshot, memory_mib, wall_seconds, self_claim=None, candidates=None, preferred=None):
        if (self_claim != claim or memory_mib != release['resources']['memory_MiB']
                or wall_seconds != release['resources']['wall_seconds']):
            raise admission.AdmissionError('held selector must use exact sealed resources and self')
        job = admission.rd.fields(snapshot['slurm'].get('self_job', ''))
        requested = dict(value.split('=', 1) for value in job.get('ReqTRES', '').split(',') if '=' in value)
        if (job.get('JobId') != claim['job_id'] or job.get('JobState') != 'PENDING'
                or job.get('Reason') != 'JobHeldUser' or job.get('NumCPUs') != '1'
                or job.get('ReqNodeList') != release['node'] or requested.get('cpu') != '1'
                or admission._memory_mib(requested.get('mem', '')) != memory_mib
                or 'MinMemoryNode' in job and admission._memory_mib(job['MinMemoryNode']) != memory_mib
                or candidates is not None and release['node'] not in candidates):
            raise admission.AdmissionError('actual pending held job/node/CPU/requested memory differs')
        # PENDING has no allocation to add back. Preserve stock physical sizing.
        chosen = stock_selector(snapshot, memory_mib, wall_seconds, self_claim=None,
            candidates=[release['node']], preferred=release['node'])
        if chosen.get('self_allocation_added_back') is not False or chosen.get('node') != release['node']:
            raise admission.AdmissionError('held selection must use the sealed node without allocation addback')
        return chosen

    tree = ast.parse(inspect.getsource(stock_refresh))
    if (len(tree.body) != 1 or not isinstance(tree.body[0], ast.FunctionDef)
            or tree.body[0].name != 'refresh_request' or tree.body[0].decorator_list):
        raise admission.AdmissionError('one unchanged undecorated stock refresh function required')
    namespace = dict(stock_refresh.__globals__)
    namespace.update(canonical_claims=canonical_claims, select_node=select_node)
    exec(compile(tree, str(Path(admission.__file__)) + ':held-audit-bridge', 'exec'), namespace)
    bridged = namespace['refresh_request']
    bridged.authorized_bridge_binding = dict(task_key=claim['task_key'], job_id=claim['job_id'],study=study,
        release_sha256=claim['release_sha256'], admission_source_sha256=source_pin,
        overridden_globals=['canonical_claims', 'select_node'], no_allocation_added_back=True)
    return bridged


def refresh_authorized_request(plan_path, config_path, policy_pin, output, *, expected_claim,
                         expected_release, expected_legacy_claim, legacy_snapshot,
                         admission=None,owner_receipt_pin=None):
    """One explicit refresh inside the caller's existing admission_refresh slot.

    The unchanged result includes observer_budget remote CPU accounting. This
    function creates no READY, authority, claim, job or additional refresh slot.
    The caller must reuse the returned fresh request for stock activate after
    release_job/watch_ready; release_and_activate would request a second refresh.
    """
    if admission is None:
        raise ValueError('reviewed future replacement admission binding required; no stock bypass')
    refresh = make_refresh_bridge(admission, expected_claim=expected_claim,
        expected_release=expected_release, expected_legacy_claim=expected_legacy_claim,
        legacy_snapshot=legacy_snapshot)
    return refresh(plan_path, config_path, policy_pin, output, self_claim=expected_claim,
        purpose='COST_ONLY', owner_receipt_pin=owner_receipt_pin,
        execution_plan_sha256=expected_release['plan_sha256'])
