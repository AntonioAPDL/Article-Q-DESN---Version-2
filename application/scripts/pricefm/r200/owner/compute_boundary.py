"""Actual compute-child boundary for new pilot/reference purposes.

Importing this module grants nothing. acquire() rejects administrative processes
before opening supplied records. Metadata fixtures must never substitute a
callback or a claimed ACK for a real Slurm/cgroup/ptrace/kernel boundary.
The source exists before the new runtime/build qualification; no such runtime
qualification is produced by this module or this source preparation.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import time

_METADATA_SHA = "6593a6bbb617375029bee0c692e510cd5621662eaf9fab46445eab433ff0762b"
_path = Path(__file__).absolute().with_name('metadata.py')
_raw = _path.read_bytes()
if _path.is_symlink() or hashlib.sha256(_raw).hexdigest() != _METADATA_SHA:
    raise ValueError('exact pinned metadata helper source required')
_loader = importlib.util.spec_from_file_location('_r200_boundary_metadata', _path)
m = importlib.util.module_from_spec(_loader)
exec(compile(_raw, str(_path), 'exec'), m.__dict__)

ROLES = {'NO3_AL300_PILOT', 'LT_NO4_REFERENCE'}
SCIENCE_HASHES = {
    'application/R/pricefm_r129_al_fixedpoint_certificate.R': 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571',
    'application/R/524_toy_fullstate_consumer.R': '0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a',
    'application/R/525_project_fullstate_consumer.R': '57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2',
    'application/tests/r179_hb_toy.R': '662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190',
    'application/scripts/pricefm/r179_hb_bridge_or_pilot.R': '1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3',
}
THREAD_KEYS = ('OPENBLAS_NUM_THREADS', 'OMP_NUM_THREADS', 'MKL_NUM_THREADS',
               'VECLIB_MAXIMUM_THREADS', 'NUMEXPR_NUM_THREADS', 'BLIS_NUM_THREADS')
SPEC_KEYS = {
    'schema', 'purpose', 'nonce', 'role', 'job_id', 'node', 'uid', 'affinity',
    'root', 'owner', 'case', 'case_sha256', 'source_map_sha256', 'owner_launch',
    'source_publication', 'source_pins', 'runtime_owner', 'scope', 'ledger',
    'input_manifest', 'input_provenance', 'price',
    'runtime_qualification', 'acknowledgement_path', 'resource_lock_fd',
    'resource_lock_path', 'attempt_claim_path', 'issued_epoch', 'expires_epoch', 'role_request',
    'scientific_source', 'controller_source', 'scientific_sources',
}
AUTHORITY_KEYS = {
    'schema', 'status', 'spec', 'purpose', 'nonce', 'role', 'job_id', 'node',
    'case_sha256', 'source_map_sha256', 'source_review', 'owner_review',
    'source_publication', 'runtime_qualification', 'price', 'scope', 'ledger',
    'issued_epoch', 'expires_epoch', 'maximum_calls', 'optimizer_invocations',
}
ACK_KEYS = {
    'schema', 'status', 'spec', 'authority', 'source_review', 'purpose', 'nonce',
    'role', 'job_id', 'node', 'uid', 'owner', 'child', 'source_pins', 'frame',
    'created_epoch', 'kernel_ACK_requires_real_boundary_call',
}
FRAME_KEYS = {
    'status', 'purpose', 'nonce', 'role', 'job_id', 'node', 'source_pins',
    'optimizer_invocations', 'scientific_target_data_read',
}
_SEAL = object()


def _proc(pid):
    m.integer(pid, 'PID', 1)
    base = Path('/proc') / str(pid)
    raw = (base / 'stat').read_text()
    end = raw.rfind(')')
    m.require(end > 0, 'complete proc stat')
    rest = raw[end + 2:].split()
    status = dict(line.split(':', 1) for line in
                  (base / 'status').read_text().splitlines() if ':' in line)
    return {
        'pid': pid, 'start_ticks': int(rest[19]), 'ppid': int(rest[1]),
        'uid': [int(x) for x in status['Uid'].split()],
        'TracerPid': int(status['TracerPid'].strip()),
        'NoNewPrivs': status.get('NoNewPrivs', '').strip(),
        'Seccomp': status.get('Seccomp', '').strip(),
    }


def _job_before_records():
    job = os.environ.get('SLURM_JOB_ID', '')
    node = os.uname().nodename.split('.')[0]
    m.require(re.fullmatch('[1-9][0-9]{0,11}', job or '') is not None
              and os.environ.get('SLURMD_NODENAME') == node
              and re.fullmatch('node-[0-9]{2}', node) is not None,
              'actual Slurm compute node required before supplied record access')
    cgroup = Path('/proc/self/cgroup').read_text()
    m.require(re.search(r'(?:^|/)job_' + re.escape(job) + r'(?:/|$)', cgroup,
                        re.MULTILINE) is not None,
              'actual kernel Slurm job cgroup, not environment-only identity')
    m.require(os.environ.get('SLURM_CPUS_PER_TASK') == '1'
              and os.environ.get('TZ') == 'UTC'
              and all(os.environ.get(k) == '1' for k in THREAD_KEYS),
              'actual one-thread compute environment')
    return job, node


def _same(record, spec):
    for key in ('purpose', 'nonce', 'role', 'job_id', 'node'):
        m.require(record.get(key) == spec[key], 'same current purpose identity: ' + key)


def _guard(record, cpu=5):
    flags = ('all_owned_descendants_reaped', 'independent_guardian',
             'kernel_escape_filter', 'orphan_subreaper',
             'guardian_included_in_CPU', 'inherited_waited_history_included_once')
    m.require(type(record.get('returncode')) is int
              and type(record.get('command_returncode')) is int
              and record.get('returncode') == record.get('command_returncode') == 0
              and type(record.get('CPU_limit')) is int and record['CPU_limit'] == cpu
              and type(record.get('aggregate_CPU_seconds')) in (int, float)
              and 0 <= record['aggregate_CPU_seconds'] < cpu
              and type(record.get('complete_lifecycle_wall_seconds')) in (int, float)
              and 0 <= record['complete_lifecycle_wall_seconds'] <= 180
              and record.get('cap_reason') is None
              and record.get('guardian_forced_monitor_stop') is False
              and all(record.get(k) is True for k in flags),
              'actual whole accepted runtime qualification guard')


def _qualification(pin, spec):
    qualification = m.linked(pin)
    m.require(qualification.get('schema') == 'r200_actual_runtime_qualification_v1'
              and qualification.get('status') == 'ACCEPTED_QUALIFIED_R200_RUNTIME'
              and qualification.get('source_map_sha256') == spec['source_map_sha256']
              and qualification.get('role') == spec['role']
              and qualification.get('node') == spec['node']
              and qualification.get('all_required_build_ABI_boundary_tests_passed') is True,
              'actual qualification of this new source/build/native boundary')
    outer = m.linked(qualification['actual_accept_guard'])
    _guard(outer)
    candidate = m.strict_json(outer['stdout'])
    expected = dict(candidate, status=qualification['status'],
                    actual_accept_guard=qualification['actual_accept_guard'])
    m.require(expected == qualification, 'actual accepted qualification candidate')
    result = m.linked(qualification['result'])
    review = m.linked(qualification['independent_review'])
    accounting = m.linked(qualification['accounting'])
    m.require(result.get('source_map_sha256') == spec['source_map_sha256']
              and result.get('job_id') == qualification.get('job_id')
              and review.get('status') == 'PASS_REVIEWED_R200_RUNTIME_QUALIFICATION'
              and review.get('result') == qualification['result']
              and review.get('accounting') == qualification['accounting']
              and accounting.get('terminal') is True
              and accounting.get('complete') is True
              and accounting.get('primary_charge_counted_once') is True,
              'complete applicable independent runtime result/accounting')
    return qualification


def _price_and_funding(spec):
    price = m.linked(spec['price'])
    m.require(price.get('status') == 'ACCEPTED_MEASURED_R200_WHOLE_CONTEXT_PRICE'
              and price.get('source_map_sha256') == spec['source_map_sha256']
              and price.get('case_sha256') == spec['case_sha256']
              and price.get('role') == spec['role'],
              'new applicable measured whole-context price')
    required = {'startup', 'namespace', 'import', 'optimizer', 'certification',
                'checkpoint', 'return', 'independent_peer', 'closure'}
    m.require(type(price.get('components')) is dict
              and set(price['components']) == required, 'complete price components')
    for component in price['components'].values():
        m.require(type(component) is dict and component.get('covered') is True,
                  'every complete-price component covered')
        m.integer(component.get('CPU_upper_seconds'), 'component CPU', 0)
        m.integer(component.get('wall_upper_seconds'), 'component wall', 0)
        for channel in ('compute_CPU_upper_seconds', 'administrative_CPU_upper_seconds',
                        'remote_unknown_CPU_reservation'):
            m.integer(component.get(channel), channel, 0)
        m.require(component['CPU_upper_seconds'] == component['compute_CPU_upper_seconds']
                  + component['administrative_CPU_upper_seconds']
                  + component['remote_unknown_CPU_reservation'], 'disjoint component CPU channels')
    for key in ('whole_CPU_seconds', 'whole_wall_seconds', 'memory_MiB',
                'child_CPU_seconds', 'owner_CPU_seconds', 'owner_wall_seconds',
                'reserved_filesystem_bytes', 'mandatory_headroom_bytes'):
        m.integer(price.get(key), key, 1)
    m.integer(price.get('compute_CPU_reservation'), 'primary compute reservation', 1)
    m.integer(price.get('administrative_CPU_reservation'), 'administrative reservation', 1)
    m.integer(price.get('remote_unknown_CPU_reservation'), 'remote unknown reservation', 0)
    for component_key, total_key in (
        ('compute_CPU_upper_seconds', 'compute_CPU_reservation'),
        ('administrative_CPU_upper_seconds', 'administrative_CPU_reservation'),
        ('remote_unknown_CPU_reservation', 'remote_unknown_CPU_reservation')):
        m.require(sum(x[component_key] for x in price['components'].values()) <= price[total_key],
                  'whole price covers its distinct CPU channel')
    m.require(price['whole_CPU_seconds'] >= price['compute_CPU_reservation']
              + price['administrative_CPU_reservation'] + price['remote_unknown_CPU_reservation']
              and sum(x['wall_upper_seconds'] for x in price['components'].values())
                  <= price['whole_wall_seconds'], 'complete disjoint whole-purpose price')
    m.require(price['child_CPU_seconds'] <= price['owner_CPU_seconds']
              <= price['compute_CPU_reservation']
              and price['owner_wall_seconds'] <= price['whole_wall_seconds'],
              'nested inclusive price, no double charge or inherited toy price')
    measurement = m.linked(price['measurement'])
    review = m.linked(price['independent_review'])
    m.require(measurement.get('source_map_sha256') == spec['source_map_sha256']
              and measurement.get('case_sha256') == spec['case_sha256']
              and measurement.get('status') == 'COMPLETE_R200_WHOLE_CONTEXT_MEASUREMENT'
              and review.get('status') == 'PASS_REVIEWED_R200_WHOLE_CONTEXT_PRICE'
              and review.get('measurement') == price['measurement'],
              'actual applicable measurement and independent whole-price review')
    scope = m.linked(spec['scope'])
    ledger = m.linked(spec['ledger'])
    m.require(scope.get('schema') == 'r200_compute_runtime_scope_v1'
              and scope.get('purpose') == spec['purpose']
              and scope.get('nonce') == spec['nonce']
              and scope.get('role') == spec['role']
              and scope.get('price') == spec['price']
              and scope.get('input_manifest') == spec['input_manifest']
              and scope.get('remote_namespace') == spec['root']
              and type(scope.get('compute_CPU_reservation')) is int
              and scope.get('compute_CPU_reservation') == price['compute_CPU_reservation']
              and type(scope.get('new_administrative_CPU_reservation')) is int
              and scope['new_administrative_CPU_reservation'] >=
                  price['administrative_CPU_reservation'] + price['remote_unknown_CPU_reservation']
              and type(scope.get('maximum_jobs')) is int and scope.get('maximum_jobs') == 1
              and scope.get('automatic_retry') is False
              and scope.get('requeue') is False
              and scope.get('expires_epoch') == spec['expires_epoch'],
              'separate fully funded runtime purpose, never source preparation')
    roles = ledger.get('compute_roles')
    m.require(type(roles) is list and len([row for row in roles if
        row.get('scope') == spec['scope']
        and row.get('compute_CPU_reservation') == price['compute_CPU_reservation']]) == 1,
        'whole current ledger contains one exact primary compute role')
    rows = [row for row in ledger.get('scopes', []) if row.get('scope') == spec['scope']]
    m.require(len(rows) == 1 and rows[0].get('administrative_CPU_reservation') ==
              scope['new_administrative_CPU_reservation'], 'whole current administrative funding row')
    _whole_ledger_provenance(spec)
    return price


def _whole_ledger_provenance(spec):
    """Conserve every inherited fee/role/null while walking to published provenance.

    Source preparation is not funding. Later runtime grants append their own
    complete disjoint administrative and primary compute reservations exactly once.
    """
    publication = m.linked(spec['source_publication'])
    base = publication.get('source_ledger')
    m.descriptor(base)
    current = spec['ledger']
    seen = set()
    counters = ('total_administrative_reservation', 'total_new_administrative_reservation',
                'total_qualification_compute_reservation',
                'total_new_qualification_compute_reservation')
    for unused in range(64):
        if current == base:
            m.linked(base)
            return True
        m.require(current['sha256'] not in seen, 'acyclic whole ledger lineage')
        seen.add(current['sha256'])
        value = m.linked(current)
        previous_pin = value.get('previous')
        before = m.linked(previous_pin)
        m.require(set(value) == set(before) | {'previous', 'created_epoch'}
                  and type(value.get('scopes')) is list
                  and type(before.get('scopes')) is list
                  and len(value['scopes']) == len(before['scopes']) + 1
                  and value['scopes'][:-1] == before['scopes'],
                  'one appended scope and entire previous ledger retained')
        row = value['scopes'][-1]
        admin = m.integer(row.get('administrative_CPU_reservation'), 'appended admin fee', 1)
        compute = m.integer(row.get('compute_CPU_reservation'), 'appended primary compute fee', 0)
        grant = m.linked(row['scope'])
        m.require(grant.get('previous_ledger', grant.get('ledger_before')) == previous_pin
                  and grant.get('purpose') == row.get('purpose')
                  and grant.get('new_administrative_CPU_reservation') == admin,
                  'new scope binds actual previous whole ledger and full fees')
        expected_compute = grant.get('compute_CPU_reservation',
                                     grant.get('new_compute_CPU_reservation'))
        m.require(type(expected_compute) is int and expected_compute == compute,
                  'compute grant matches its exact new reservation')
        m.require(all(old.get('purpose') != row['purpose'] for old in before['scopes']),
                  'no purpose or spent fee replay')
        for key, delta in zip(counters, (admin, admin, compute, compute)):
            m.require(type(value.get(key)) is int and type(before.get(key)) is int
                      and value[key] == before[key] + delta, 'whole conserved counter ' + key)
        old_roles, new_roles = before.get('compute_roles'), value.get('compute_roles')
        m.require(type(old_roles) is list and type(new_roles) is list
                  and new_roles[:len(old_roles)] == old_roles, 'all old compute roles retained')
        if compute:
            m.require(len(new_roles) == len(old_roles) + 1
                      and new_roles[-1].get('scope') == row['scope']
                      and new_roles[-1].get('compute_CPU_reservation') == compute,
                      'one new primary compute role, charged once')
        else:
            m.require(new_roles == old_roles, 'source-only append cannot change compute roles')
        for key in before:
            if key not in {'previous', 'created_epoch', 'scopes', 'compute_roles', *counters}:
                m.require(value[key] == before[key], 'historical ledger field retained: ' + key)
        current = previous_pin
    raise ValueError('current whole ledger must reach actual published source provenance in <=64 appends')


def _validate_sources(spec, review_pin):
    review = m.linked(review_pin)
    m.require(review.get('schema') == 'r200_compute_source_review_v1'
              and review.get('status') == 'PASS_REVIEWED_R200_COMPUTE_SOURCE_PHYSICAL',
              'separate current physical source review')
    _same(review, spec)
    publication = m.linked(spec['source_publication'])
    m.require(publication.get('schema') == 'r200_source_publication_v1'
              and publication.get('status') == 'PASS_PUBLISHED_R200_SOURCE_PREPARATION'
              and publication.get('remote_readback') == publication.get('commit')
              and re.fullmatch('[0-9a-f]{40}', publication.get('commit', ''))
              and publication.get('branch', '').startswith('work/pricefm-'),
              'exact independently published feature source')
    pins = review.get('source_pins')
    m.require(type(pins) is dict and 1 <= len(pins) <= 128
              and spec['source_pins'] == pins
              and spec['controller_source'] == spec['source_publication']
              and review.get('controller_source') == spec['controller_source']
              and set(pins) == set(publication.get('files', {}))
              and m.digest(publication['files']) == spec['source_map_sha256']
              and review.get('source_map_sha256') == spec['source_map_sha256']
              and review.get('spec') == spec['_spec_pin'],
              'complete exact current installed source map and spec')
    for name, pin in pins.items():
        m.require(not Path(name).is_absolute() and '..' not in Path(name).parts,
                  'relative closed source member')
        m.require(pin['sha256'] == publication['files'][name],
                  'installed source equals reviewed published bytes')
        m.source_bytes(pin)
    own = pins.get('owner/compute_boundary.py')
    m.require(own is not None and own['path'] == str(Path(__file__).absolute()),
              'actual boundary file belongs to this reviewed closure')
    return review


def _pilot_science(spec):
    if spec['role'] != 'NO3_AL300_PILOT':
        return
    science = spec['scientific_sources']
    m.require(type(science) is dict and set(science) == set(SCIENCE_HASHES),
              'exact five original scientific source names')
    for name, expected in SCIENCE_HASHES.items():
        m.require(science[name]['sha256'] == expected, 'unchanged original mathematical source')
        m.source_bytes(science[name])
    io = m.linked(spec['io_request'])
    m.require({(x['path'], x['sha256']) for x in io.get('science_source_pins', [])}
              == {(x['path'], x['sha256']) for x in science.values()},
              'same five actual I/O mathematical source pins')
    context = io.get('scientific_context', {})
    m.require(context.get('fixedpoint_helper') ==
              science['application/R/pricefm_r129_al_fixedpoint_certificate.R']
              and context.get('project_consumer') ==
              science['application/R/525_project_fullstate_consumer.R'],
              'correct unchanged helper and full-state consumer roles')


def _identity(spec, ack):
    job, node = _job_before_records()
    m.require((job, node, os.getuid()) == (spec['job_id'], spec['node'], spec['uid']),
              'actual current compute identity')
    m.require(type(spec['affinity']) is list and len(spec['affinity']) == 1
              and type(spec['affinity'][0]) is int and spec['affinity'][0] >= 0
              and os.sched_getaffinity(0) == set(spec['affinity']), 'actual current one-CPU affinity')
    child = _proc(os.getpid())
    parent = _proc(spec['owner']['pid'])
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    m.require(parent['pid'] == os.getppid() == child['TracerPid']
              and parent['start_ticks'] == spec['owner']['start_ticks']
              and boot == spec['owner']['boot_id']
              and child['uid'] == parent['uid'] == [os.getuid()] * 4
              and child['NoNewPrivs'] == '1' and child['Seccomp'] == '2',
              'actual current parent/ptrace lifetime and kernel filtered child')
    m.require(ack['owner'] == spec['owner']
              and ack['child'] == {'pid': child['pid'], 'start_ticks': child['start_ticks']},
              'parent parse gate binds this exact live child')
    fd = spec['resource_lock_fd']
    m.integer(fd, 'inherited resource lock FD', 3, 2**20)
    actual = os.fstat(fd)
    owner_stat = os.stat('/proc/' + str(parent['pid']) + '/fd/' + str(fd))
    path_stat = m.physical(spec['resource_lock_path']).stat()
    m.require(actual.st_uid == os.getuid()
              and (actual.st_dev, actual.st_ino)
              == (owner_stat.st_dev, owner_stat.st_ino)
              == (path_stat.st_dev, path_stat.st_ino),
              'actual inherited same-inode current-owner permit')
    fdinfo = Path('/proc/self/fdinfo/' + str(fd)).read_text()
    m.require(re.search(r'lock:\s+\d+:\s+FLOCK\s+ADVISORY\s+WRITE\s+'
                        + str(parent['pid']) + r'\s', fdinfo) is not None,
              'actual live owner FLOCKWRITE, no lock acquisition by verifier')
    return child


def _input_provenance(spec, review):
    value = m.linked(spec['input_provenance'])
    if spec['role'] == 'NO3_AL300_PILOT':
        # Pilot provenance is the original ten-name accepted bridge mapping,
        # not a caller-authored PASS flag or a rewritten old proof.
        io = m.linked(spec['io_request'])
        m.require(io.get('accepted_bridge') == value
                  and io.get('scientific_source') == spec['scientific_source'],
                  'same immutable accepted bridge and full scientific identity')
        aliases = io.get('proof_aliases')
        m.require(type(aliases) is list and len(aliases) == 10,
                  'complete exact bridge proof alias sidecar')
        granted = m.linked(spec['input_manifest']).get('files')
        m.require(type(granted) is list, 'complete actual input grant')
        for row in aliases:
            m.closed(row, {'logical', 'physical', 'bytes', 'uid'}, 'bridge alias')
            m.require(any(item.get('logical_path') == row['logical']['path']
                          and item.get('path') == row['physical']['path']
                          and item.get('sha256') == row['logical']['sha256']
                          and item.get('bytes') == row['bytes']
                          and item.get('uid') == row['uid'] for item in granted),
                      'every proof alias is explicitly newly authorized')
        source_pin = review['source_pins'].get('owner/pilot_owner_dispatch.py')
        m.require(source_pin is not None and source_pin['path'] ==
                  str(Path(__file__).absolute().with_name('pilot_owner_dispatch.py')),
                  'fixed reviewed producer-side bridge verifier')
        raw = m.source_bytes(source_pin)
        loader = importlib.util.spec_from_file_location('_r200_accepted_bridge_check', source_pin['path'])
        dispatch = importlib.util.module_from_spec(loader)
        exec(compile(raw, source_pin['path'], 'exec'), dispatch.__dict__)
        # The independent peer separately implements the same bridge policy.
        # This producer check cannot substitute for that independently authored phase.
        return dispatch.validate_accepted_bridge(value, aliases, spec['scientific_source'])
    m.require(value.get('status') == 'ACCEPTED_ACTUAL_R200_REFERENCE_INPUT_EXPORT'
              and value.get('case_sha256') == spec['case_sha256']
              and value.get('input_manifest') == spec['input_manifest']
              and value.get('complete_original_failed_provenance_verified') is True
              and value.get('native_owned_export_and_accounting_independently_reviewed') is True,
              'separate actual original-state export, never snapshot self-provenance')
    guard = m.linked(value['actual_export_guard'])
    _guard(guard)
    candidate = m.strict_json(guard['stdout'])
    m.require(candidate == value.get('actual_export_candidate')
              and candidate.get('case_sha256') == spec['case_sha256']
              and candidate.get('input_manifest') == spec['input_manifest']
              and candidate.get('original_failed_states_unchanged') is True
              and type(candidate.get('optimizer_updates')) is int
              and candidate['optimizer_updates'] == 0,
              'actual zero-update export candidate binds exact state and readset')
    exported_review = m.linked(value['independent_review'])
    account = m.linked(value['accounting'])
    m.require(exported_review.get('status') == 'PASS_REVIEWED_R200_REFERENCE_INPUT_EXPORT'
              and exported_review.get('input_manifest') == spec['input_manifest']
              and exported_review.get('accounting') == value['accounting']
              and account.get('terminal') is True and account.get('complete') is True
              and account.get('primary_charge_counted_once') is True,
              'complete independently accepted original-state export/accounting')
    return value




class OwnedBoundary:
    """Opaque current-child handle. A descriptor or arbitrary callback is insufficient."""
    __slots__ = ('_spec', '_authority', '_review', '_ack', '_inputs', '_created', '_seal', '_proof_pins')

    def __init__(self, spec, authority, review, ack, inputs, proof_pins, seal):
        m.require(seal is _SEAL, 'private verified live boundary construction only')
        self._spec, self._authority, self._review = spec, authority, review
        self._ack, self._inputs, self._created = ack, inputs, time.time()
        self._seal = seal
        self._proof_pins = proof_pins

    def verify_live(self):
        m.require(self._seal is _SEAL, 'verified boundary handle')
        now = time.time()
        m.require(self._authority['issued_epoch'] <= now < self._authority['expires_epoch']
                  <= self._spec['expires_epoch'], 'current fixed owned lifetime')
        _identity(self._spec, self._ack)
        m.require(m.pin_file(self._spec['_spec_pin']['path']) == self._spec['_spec_pin'],
                  'immutable current spec')
        for pin in self._proof_pins:
            m.require(m.pin_file(pin['path']) == pin, 'immutable current authority/ACK/input manifest')
        return {'job_id': self._spec['job_id'], 'node': self._spec['node'],
                'purpose': self._spec['purpose'], 'role': self._spec['role'],
                'expires_epoch': self._spec['expires_epoch']}

    def read_input(self, name):
        self.verify_live()
        m.require(type(name) is str and name in self._inputs, 'exact input allowlist name')
        row = self._inputs[name]
        return m.read_regular(row['path'], limit=row['bytes'],
                              expected_sha=row['sha256'], expected_uid=row['uid'],
                              expected_bytes=row['bytes'])


def acquire(spec_pin, authority_pin, source_review_pin, acknowledgement_pin):
    """Validate real current ownership before any supplied metadata or target read."""
    _job_before_records()
    spec = m.linked(spec_pin)
    role = spec.get('role')
    m.require(role in ROLES, 'separate supported new compute role')
    extra = {'io_request'} if role == 'NO3_AL300_PILOT' else {'reference_request'}
    m.closed(spec, SPEC_KEYS | extra, 'compute spec')
    m.require(spec['schema'] == 'r200_owned_compute_spec_v1'
              and re.fullmatch('[0-9a-f]{32}', spec['nonce'])
              and type(spec['purpose']) is str and 1 <= len(spec['purpose']) <= 128
              and spec['case_sha256'] == m.digest(spec['case'])
              and spec[next(iter(extra))] == spec['role_request'], 'exact versioned case and role request')
    m.integer(spec['uid'], 'UID')
    m.closed(spec['owner'], {'pid', 'start_ticks', 'boot_id'}, 'owner identity')
    spec = dict(spec, _spec_pin=spec_pin)
    authority = m.linked(authority_pin)
    m.closed(authority, AUTHORITY_KEYS, 'Root authority')
    _same(authority, spec)
    m.require(authority['schema'] == 'r200_compute_authority_v1'
              and authority['status'] == 'ROOT_ADMITTED_NEW_R200_COMPUTE_PURPOSE'
              and authority['spec'] == spec_pin
              and authority['source_review'] == source_review_pin
              and authority['maximum_calls'] == 1
              and type(authority['maximum_calls']) is int
              and authority['optimizer_invocations'] == (1 if role == 'NO3_AL300_PILOT' else 0)
              and type(authority['optimizer_invocations']) is int, 'exact single-purpose Root authority')
    for key in ('case_sha256', 'source_map_sha256', 'source_publication',
                'runtime_qualification', 'price', 'scope', 'ledger'):
        m.require(authority[key] == spec[key], 'same authority/spec ' + key)
    now = time.time()
    for key in ('issued_epoch', 'expires_epoch'):
        m.finite(spec[key], key)
        m.finite(authority[key], key)
    m.require(spec['issued_epoch'] <= authority['issued_epoch'] <= now
              < authority['expires_epoch'] <= spec['expires_epoch']
              and 0 < spec['expires_epoch'] - spec['issued_epoch'] <= 28800,
              'new finite fixed compute purpose, no clock renewal')
    m.require(acknowledgement_pin['path'] == spec['acknowledgement_path']
              and m.absolute(spec['acknowledgement_path']).is_relative_to(
                  m.absolute(spec['root'])), 'exact create-only parent acknowledgement path')
    ack = m.linked(acknowledgement_pin)
    m.closed(ack, ACK_KEYS, 'parent parse gate')
    _same(ack, spec)
    m.require(ack['schema'] == 'r200_parent_parse_gate_v1'
              and ack['status'] == 'OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK'
              and ack['spec'] == spec_pin and ack['authority'] == authority_pin
              and ack['source_review'] == source_review_pin
              and ack['uid'] == spec['uid']
              and ack['kernel_ACK_requires_real_boundary_call'] is True,
              'parent approval is not itself a claim that kernel ACK was earned')
    frame = m.closed(ack['frame'], FRAME_KEYS, 'pre-entry parse frame')
    _same(frame, spec)
    m.require(frame['status'] == 'R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT'
              and frame['optimizer_invocations'] == 0
              and type(frame['optimizer_invocations']) is int
              and frame['scientific_target_data_read'] is False,
              'parse-only frame before real native handshake')
    review = _validate_sources(spec, source_review_pin)
    m.require(ack['source_pins'] == frame['source_pins'] == review['source_pins'],
              'same complete parsed installed source closure')
    _identity(spec, ack)
    claim_path = m.absolute(spec['attempt_claim_path'])
    m.require(claim_path.is_relative_to(m.absolute(spec['root'])), 'fixed private attempt claim')
    claim = m.linked(m.pin_file(claim_path))
    m.require(claim.get('schema') == 'r200_compute_attempt_claim_v1'
              and claim.get('status') == 'SPENT_CURRENT_OWNER_ATTEMPT_NO_RETRY'
              and claim.get('spec') == spec_pin and claim.get('authority') == authority_pin
              and claim.get('owner') == spec['owner'], 'actual create-only current owner attempt')
    _same(claim, spec)
    _qualification(spec['runtime_qualification'], spec)
    _price_and_funding(spec)
    _pilot_science(spec)
    _input_provenance(spec, review)
    owner_review = m.linked(authority['owner_review'])
    m.require(owner_review.get('status') == 'PASS_REVIEWED_R200_OWNER_RELEASE'
              and owner_review.get('spec') == spec_pin
              and owner_review.get('source_review') == source_review_pin
              and owner_review.get('source_map_sha256') == spec['source_map_sha256'],
              'distinct actual independent owner-release phase')
    manifest = m.linked(spec['input_manifest'])
    m.require(manifest.get('schema') == 'r200_owned_input_manifest_v1'
              and manifest.get('purpose') == spec['purpose']
              and manifest.get('nonce') == spec['nonce']
              and type(manifest.get('files')) is list and 1 <= len(manifest['files']) <= 64,
              'new explicit exact input grant manifest')
    inputs = {}
    total = 0
    for row in manifest['files']:
        m.closed(row, {'name', 'path', 'sha256', 'bytes', 'uid', 'logical_path'}, 'input row')
        m.require(type(row['name']) is str and re.fullmatch('[A-Za-z][A-Za-z0-9_]{0,63}', row['name'])
                  and row['name'] not in inputs, 'unique closed input name')
        m.descriptor({'path': row['path'], 'sha256': row['sha256']})
        m.absolute(row['logical_path'])
        m.integer(row['bytes'], 'input bytes', 1, 2 * 1024**3)
        m.require(type(row['uid']) is int and row['uid'] == spec['uid'], 'current input UID')
        total += row['bytes']
        inputs[row['name']] = dict(row)
    m.require(type(manifest.get('maximum_total_bytes')) is int
              and total <= manifest['maximum_total_bytes'] <= 4 * 1024**3,
              'complete finite input envelope')
    role_name = 'io_request' if role == 'NO3_AL300_PILOT' else 'reference_request'
    m.require(role_name in inputs and inputs[role_name]['path'] == spec['role_request']['path']
              and inputs[role_name]['sha256'] == spec['role_request']['sha256'],
              'role request is the same explicit immutable input')
    runtime_owner = {'job_id': spec['job_id'], 'node': spec['node'], 'uid': spec['uid'],
                     'parent_pid': spec['owner']['pid'],
                     'parent_birth_ticks': spec['owner']['start_ticks'],
                     'resource_lock_fd': spec['resource_lock_fd'],
                     'expires_epoch': spec['expires_epoch']}
    m.require(spec['runtime_owner'] == runtime_owner, 'same exact R/native owner interface')
    proofs = [authority_pin, source_review_pin, acknowledgement_pin,
              spec['input_manifest'], m.pin_file(claim_path)]
    boundary = OwnedBoundary(spec, authority, review, ack, inputs, proofs, _SEAL)
    boundary.verify_live()
    request_value = m.strict_json(boundary.read_input(role_name))
    if role == 'LT_NO4_REFERENCE':
        m.require(m.digest(request_value) == spec['case_sha256']
                  and request_value == spec['case'], 'exact authorized LT/NO4 request case')
    else:
        m.require(request_value.get('case') == spec['case']
                  and request_value.get('purpose') == spec['purpose']
                  and request_value.get('nonce') == spec['nonce'], 'same exact pilot I/O case')
    return boundary

