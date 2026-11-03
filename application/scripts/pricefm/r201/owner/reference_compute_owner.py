"""Closed direct Slurm reference owner. Source-only preparation grants no execution."""
from __future__ import annotations
import argparse,datetime,hashlib,importlib.util,json,os,resource,stat,time
from pathlib import Path
_cp=Path(__file__).absolute().with_name("reference_common.py")
# Authenticate one captured fixed-source byte string BEFORE interpretation.
_COMMON_SHA="e9e35192e82bf0669cdbce20614cfc68e195ecd3c4c2655d479b8267544fc870"
if any(v.is_symlink() for v in (_cp,*_cp.parents)):
    raise ValueError("fixed common source requires physical nonsymlink path")
_cfd=os.open(_cp,os.O_RDONLY|os.O_NONBLOCK|os.O_NOFOLLOW)
try:
    _cbefore=os.fstat(_cfd)
    if not (stat.S_ISREG(_cbefore.st_mode) and _cbefore.st_nlink==1
            and _cbefore.st_uid==os.getuid() and 0<_cbefore.st_size<=1024**2):
        raise ValueError("bounded owned regular single-link common source")
    _craw=b""
    while len(_craw)<=1024**2:
        _cblock=os.read(_cfd,min(65536,1024**2+1-len(_craw)))
        if not _cblock:break
        _craw+=_cblock
    _cafter=os.fstat(_cfd)
finally:
    os.close(_cfd)
_cstate=lambda v:(v.st_dev,v.st_ino,v.st_size,v.st_mtime_ns,v.st_ctime_ns,
                  v.st_mode,v.st_uid,v.st_nlink)
if (_cstate(_cbefore)!=_cstate(_cafter) or _cstate(_cafter)!=_cstate(_cp.lstat())
        or len(_craw)!=_cbefore.st_size or hashlib.sha256(_craw).hexdigest()!=_COMMON_SHA):
    raise ValueError("exact captured common source SHA and physical lifetime")
_cs=importlib.util.spec_from_file_location("_r201_owner_common",_cp)
c=importlib.util.module_from_spec(_cs);exec(compile(_craw,str(_cp),"exec"),c.__dict__)
m=c.m
_UNREAPED_LOCK_FDS=[]
_job=c.job
_kernel_physical=c.physical
def _load_source(pin,name):
    raw=m.source_bytes(pin);s=importlib.util.spec_from_file_location(name,pin["path"])
    obj=importlib.util.module_from_spec(s);exec(compile(raw,pin["path"],"exec"),obj.__dict__);return obj

def _prelaunch_peer_leases(source_review,owner_review,authority_issued,now):
    """Pure metadata check for FIRST child launch, never post-ACK renewal."""
    m.finite(authority_issued,"authority issue for prelaunch peer lease")
    m.finite(now,"current prelaunch clock")
    for label,record in (("source",source_review),("owner",owner_review)):
        issued=m.finite(record.get("issued_epoch"),label+" peer issued")
        expiry=m.finite(record.get("expires_epoch"),label+" peer expiry")
        m.require(issued<=authority_issued<=now<expiry,
                  "fresh "+label+" independent peer lease and authority issuance before first child")

def validate(spec_pin, authority_pin, source_review_pin):
    job,node=_job()  # Actual kernel job gate BEFORE supplied records.
    initial=m.linked(spec_pin)
    if initial.get("role")==c.INITIAL:
        review=m.linked(source_review_pin)
        boundary=c.load("qualification/qualification_boundary.py",review["source_pins"])
        spec,authority,review,price,launch,physical=boundary.validate_prelaunch(spec_pin,authority_pin,source_review_pin)
        c.validate_launch(spec,review,price,launch)
        c.load("owner/reference_return.py",review["source_pins"]).plan(spec,price)
        return spec,authority,review,price,launch,boundary,physical
    m.require(initial.get("role")==c.PRODUCTION,"closed production reference role")
    review = m.linked(source_review_pin)
    bp = review.get('source_pins', {}).get('owner/compute_boundary.py')
    m.require(bp is not None and bp['path'] ==
              str(Path(__file__).absolute().with_name('compute_boundary.py')),
              'actual fixed sibling boundary belongs to current installed source review')
    boundary = _load_source(bp, '_r200_owner_actual_boundary')
    spec = m.linked(spec_pin)
    m.closed(spec, boundary.SPEC_KEYS | {'reference_request'}, 'exact pilot owner spec')
    m.require(spec['schema'] == 'r200_owned_compute_spec_v1'
              and spec['role'] == 'LT_NO4_REFERENCE'
              and (spec['job_id'], spec['node'], spec['uid']) == (job, node, os.getuid())
              and spec['role_request'] == spec['reference_request']
              and spec['case_sha256'] == m.digest(spec['case']), 'exact actual pilot purpose')
    parent = boundary._proc(os.getpid())
    boot = Path('/proc/sys/kernel/random/boot_id').read_text().strip()
    m.require(spec['owner'] == {'pid': os.getpid(), 'start_ticks': parent['start_ticks'],
                               'boot_id': boot} and parent['TracerPid'] == 0,
              'same READY worker owns scientific trace, outside administrative H')
    spec = dict(spec, _spec_pin=spec_pin)
    authority = m.linked(authority_pin)
    m.closed(authority, boundary.AUTHORITY_KEYS, 'separate Root runtime authority')
    boundary._same(authority, spec)
    m.require(authority['schema'] == 'r200_compute_authority_v1'
              and authority['status'] == 'ROOT_ADMITTED_NEW_R200_COMPUTE_PURPOSE'
              and authority['spec'] == spec_pin and authority['source_review'] == source_review_pin
              and type(authority['maximum_calls']) is int and authority['maximum_calls'] == 1
              and type(authority['optimizer_invocations']) is int
              and authority['optimizer_invocations'] == 0,
              'one new pilot attempt, never a metadata/source grant')
    for key in ('case_sha256', 'source_map_sha256', 'source_publication',
                'runtime_qualification', 'price', 'scope', 'ledger'):
        m.require(authority[key] == spec[key], 'same current authority ' + key)
    actual_review = boundary._validate_sources(spec, source_review_pin)
    qualification = boundary._qualification(spec['runtime_qualification'], spec)
    qualified_result = m.linked(qualification['result'])
    price = boundary._price_and_funding(spec)
    boundary._pilot_science(spec)
    provenance = boundary._input_provenance(spec, actual_review)
    owner_review = m.linked(authority['owner_review'])
    m.require(owner_review.get('status') == 'PASS_REVIEWED_R200_OWNER_RELEASE'
              and owner_review.get('spec') == spec_pin
              and owner_review.get('source_review') == source_review_pin
              and owner_review.get('source_map_sha256') == spec['source_map_sha256'],
              'actual separately authored second peer phase')
    ready = m.linked(owner_review['owner_ready'])
    m.require(ready.get('status') == 'READY_R200_OWNED_AWAIT_ROOT_RELEASE_NO_PAYLOAD'
              and ready.get('owner') == spec['owner']
              and ready.get('job_id') == job and ready.get('node') == node
              and ready.get('resource_lock_fd') == spec['resource_lock_fd']
              and ready.get('resource_lock_path') == spec['resource_lock_path'],
              'actual matching READY worker and inherited resource lock')
    now = time.time()
    _prelaunch_peer_leases(actual_review,owner_review,authority["issued_epoch"],now)
    m.require(type(ready.get('created_epoch')) in (int, float)
              and 0 <= now - ready['created_epoch'] < 120
              and spec['issued_epoch'] <= authority['issued_epoch'] <= now
              and now + price['whole_wall_seconds'] < authority['expires_epoch']
              <= spec['expires_epoch'], 'unchanged 120-second READY and complete remaining schedule')
    runtime_owner = {'job_id': job, 'node': node, 'uid': os.getuid(),
                     'parent_pid': os.getpid(), 'parent_birth_ticks': parent['start_ticks'],
                     'resource_lock_fd': spec['resource_lock_fd'], 'expires_epoch': spec['expires_epoch']}
    m.require(spec['runtime_owner'] == runtime_owner, 'same current R/native owner contract')
    fd = spec['resource_lock_fd']
    held = os.fstat(fd)
    lock = m.physical(spec['resource_lock_path']).stat()
    m.require(stat.S_ISREG(held.st_mode) and held.st_uid == os.getuid()
              and (held.st_dev, held.st_ino) == (lock.st_dev, lock.st_ino),
              'already held same-inode one-attempt resource lock')
    # Read only this owner's exact FD info, not a global lock/process census.
    m.require('FLOCK' in Path('/proc/self/fdinfo/' + str(fd)).read_text()
              and 'WRITE' in Path('/proc/self/fdinfo/' + str(fd)).read_text(),
              'actual existing exclusive owner FLOCK')
    launch=m.linked(spec['owner_launch'])
    c.validate_launch(spec,actual_review,price,launch)
    writer=c.load("owner/reference_return.py",actual_review["source_pins"])
    writer.plan(spec,price)
    physical=_kernel_physical(spec,price,initial_reservation=True)
    return spec,authority,actual_review,price,launch,boundary,physical

def _parent_gate(spec_pin, authority_pin, review_pin, spec, review, raw, phase, state):
    m.require(phase == 'SCIENTIFIC_FORK_DENIED' and state.get('state') == 'LIVE'
              and state.get('kernel_trace_owned') is True
              and state.get('scientific_filter_accepted') is True,
              'actual original tracer pre-ACK capture transition')
    m.require(len(raw) <= 1024**2, 'bounded parse-only stdout')
    frames = [m.strict_json(line) for line in raw.splitlines()
              if line.lstrip().startswith(b'{')]
    m.require(len(frames) == 1, 'one exact parse frame before ACK')
    frame = m.closed(frames[0], {
        'status', 'purpose', 'nonce', 'role', 'job_id', 'node', 'source_pins',
        'optimizer_invocations', 'scientific_target_data_read'}, 'parse frame')
    m.require(frame['status'] == 'R200_PINNED_SOURCE_PARSE_PASS_BEFORE_ENTRYPOINT'
              and frame['source_pins'] == review['source_pins']
              and frame['optimizer_invocations'] == 0
              and type(frame['optimizer_invocations']) is int
              and frame['scientific_target_data_read'] is False,
              'all pinned source parsed with zero optimizer/target access')
    for key in ('purpose', 'nonce', 'role', 'job_id', 'node'):
        m.require(frame[key] == spec[key], 'current exact parsed ' + key)
    roots = [x for x in state.get('live_lifetimes', [])
             if x.get('ppid') == os.getpid() and x.get('TracerPid') == os.getpid()]
    m.require(len(roots) == 1, 'one actual directly traced scientific child')
    child = roots[0]
    record = dict(schema='r200_parent_parse_gate_v1',
                  status='OWNER_VALIDATED_EXACT_PARSE_BEFORE_KERNEL_ACK',
                  spec=spec_pin, authority=authority_pin, source_review=review_pin,
                  purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                  job_id=spec['job_id'], node=spec['node'], uid=spec['uid'],
                  owner=spec['owner'], child={'pid': child['pid'], 'start_ticks': child['start_ticks']},
                  source_pins=review['source_pins'], frame=frame, created_epoch=time.time(),
                  kernel_ACK_requires_real_boundary_call=True)
    writer=c.load("owner/reference_return.py",review["source_pins"])
    return writer.write_parent_proof(spec,"ack",record)
def run(spec_pin, authority_pin, source_review_pin):
    spec, authority, review, price, launch, boundary, initial_physical = validate(
        spec_pin, authority_pin, source_review_pin)
    # Spend the attempt before any target interpretation or scientific child.
    claim = dict(schema='r200_compute_attempt_claim_v1',
                 status='SPENT_CURRENT_OWNER_ATTEMPT_NO_RETRY',
                 spec=spec_pin, authority=authority_pin, owner=spec['owner'],
                 purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                 job_id=spec['job_id'], node=spec['node'], created_epoch=time.time())
    m.require(m.absolute(spec['attempt_claim_path']).is_relative_to(m.absolute(spec['root'])),
              'fixed purpose attempt path')
    claim_pin = m.write_new(spec['attempt_claim_path'], claim)
    trace = _load_source(launch['traced_guard'], '_r200_unchanged_native_tracer')
    # r157 exposes its complete internally defined callback protocol; callbacks
    # below are trusted fixed source, not supplied by a request or caller.
    fd = spec['resource_lock_fd']
    output = m.physical(launch['output_root'])
    writer=c.load("owner/reference_return.py",review["source_pins"])
    reservation=writer.reserve_for_owner(spec,price,launch)
    resource.setrlimit(resource.RLIMIT_FSIZE,(16*1024**2,16*1024**2))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    gate_pin = None
    safe = False
    started = time.monotonic()
    def peer(owned):
        _job()
        current = _kernel_physical(spec, price)
        m.require(current['online_thread_siblings'] == initial_physical['online_thread_siblings']
                  and current['effective_job_cpus'] == initial_physical['effective_job_cpus'],
                  'current physical/SMT ownership preserved')
        for prior in owned:
            actual = trace.identity(prior['pid'])
            m.require(trace.same_lifetime(actual, prior)
                      and actual['TracerPid'] == os.getpid()
                      and actual['affinity'] == spec['affinity'],
                      'actual same-lifetime current ptrace ownership')
        return {'job_id': spec['job_id'], 'owned_lifetimes': len(owned)}
    def limits():
        resource.setrlimit(resource.RLIMIT_CPU,
                           (price['child_CPU_seconds'], price['child_CPU_seconds']))
        resource.setrlimit(resource.RLIMIT_FSIZE, (16 * 1024**2, 16 * 1024**2))
        resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    command=[launch['native_executable']['path'],'-I','-B',launch['bootstrap']['path'],
             spec_pin['path'],spec_pin['sha256'],authority_pin['path'],authority_pin['sha256'],
             source_review_pin['path'],source_review_pin['sha256']]
    env = dict(launch['environment'], R154_GLOBAL_PERMIT_LOCK_FD=str(fd))
    try:
        for path, digest in launch['bootstrap_exec_allowlist'].items():
            m.read_regular(path, limit=64 * 1024**2, expected_sha=digest,
                           expected_uid=os.getuid())
        with Path(launch['stdout_path']).open('r+b',buffering=0) as stdout, Path(launch['stderr_path']).open('r+b',buffering=0) as stderr:
            def capture(lock_fd, phase, state):
                nonlocal gate_pin
                if phase == 'SCIENTIFIC_FORK_DENIED' and state.get('state') == 'LIVE' and gate_pin is None:
                    m.require(lock_fd == fd, 'same original owner permit')
                    gate_pin = _parent_gate(spec_pin, authority_pin, source_review_pin,
                                            spec, review, os.pread(stdout.fileno(),min(stdout.tell(),1024**2),0),
                                            phase, state)
            receipt = trace.run_traced(
                command, env=env, stdout=stdout, stderr=stderr, lock_fd=fd,
                affinity=spec['affinity'], wall_seconds=price['owner_wall_seconds'],
                maximum_combined_CPU_seconds=price['owner_CPU_seconds'],
                absolute_deadline_UTC=datetime.datetime.fromtimestamp(
                    authority['expires_epoch'], datetime.timezone.utc).isoformat(),
                peer_callback=peer, bootstrap_exec_allowlist=launch['bootstrap_exec_allowlist'],
                owner_path=launch['owned_tree_path'], scope=spec['purpose'],
                source={'kind': 'SEPARATE_R201_REFERENCE_OWNER_UNCHANGED_R157_TRACER',
                        'source_map_sha256': spec['source_map_sha256']},
                authority_pin=authority_pin, preexec_fn=limits,
                require_science_handshake=True, owner_capture_callback=capture)
            for stream in (stdout,stderr):
                length=stream.tell();m.require(length<=16*1024**2,"bounded prepaid complete stream")
                stream.truncate(length);stream.flush();os.fsync(stream.fileno())
        safe = (receipt.get('reaped') is True and receipt.get('drained') is True
                and receipt.get('remaining_owned_lifetimes') == [])
        guard_pin=writer.write_parent_proof(spec,'guard',receipt)
        flags = ('reaped', 'drained', 'CPU_accounting_complete',
                 'all_newborns_kernel_traced_before_execution',
                 'tracer_death_kernel_EXITKILL_enabled',
                 'postbootstrap_TSYNC_scientific_fork_denial',
                 'scientific_target_access_handshake')
        attestation = receipt.get('scientific_filter_kernel_attestation') or {}
        m.require(receipt.get('schema') == 'r157_traced_bootstrap_guard_receipt_v1'
                  and receipt.get('status') == 'EXITED'
                  and receipt.get('returncode') == 0
                  and all(receipt.get(k) is True for k in flags)
                  and receipt.get('remaining_owned_lifetimes') == []
                  and receipt.get('unexpected_untraced_child_waits') == []
                  and attestation.get('operation') == 'SECCOMP_SET_MODE_FILTER'
                  and attestation.get('flags') == 'TSYNC'
                  and attestation.get('kernel_return') == 0 and gate_pin is not None,
                  'complete actual native kernel ACK/reap/drain proof')
        m.require(time.monotonic() - started < price['owner_wall_seconds']
                  and time.time() < authority['expires_epoch'], 'complete fixed owned interval')
        returned=writer.verify_parent_return(spec,price,launch)
        inventory=writer.retained_inventory(spec,launch)
        inventory_pin=writer.write_parent_proof(spec,"inventory",inventory)
        result = dict(status='R201_REFERENCE_RETURN_CANDIDATE_AWAIT_COMPLETE_INDEPENDENT_ACCEPTANCE',
                      return_payload=returned,retained_inventory=inventory_pin,reservation=reservation,
                      purpose=spec['purpose'], nonce=spec['nonce'], role=spec['role'],
                      job_id=spec['job_id'], node=spec['node'], spec=spec_pin,
                      authority=authority_pin, source_review=source_review_pin,
                      attempt_claim=claim_pin, owned_guard=guard_pin, parent_parse_gate=gate_pin,
                      source_map_sha256=spec['source_map_sha256'], production_acceptance=False,
                      automatic_dependent_release=False,
                      full_inventory_accounting_independent_review_still_required=True)
        writer.write_parent_proof(spec,'candidate',result)
        return result
    except BaseException as error:
        failure = Path(spec['root']) / 'OWNER_FAILED_SPENT.json'
        if failure.exists() and failure.stat().st_size==4*1024**2:
            writer.write_parent_proof(spec,'failure', {'status': 'FAILED_R201_REFERENCE_ATTEMPT_FEES_RETAINED',
                                 'purpose': spec['purpose'], 'nonce': spec['nonce'],
                                 'role': spec['role'], 'automatic_retry': False,
                                 'attempt_claim': claim_pin,
                                 'error': type(error).__name__ + ': ' + str(error)})
        raise
    finally:
        if not safe:
            _UNREAPED_LOCK_FDS.append(fd)
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ("spec","authority","source-review"):
        p.add_argument("--"+name,required=True);p.add_argument("--"+name+"-sha256",required=True)
    a=p.parse_args();pins=[dict(path=getattr(a,k),sha256=getattr(a,k+"_sha256")) for k in ("spec","authority","source_review")]
    print(json.dumps(run(*pins),sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
