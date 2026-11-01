"""Frozen525 numerical-purpose contracts. No execution or grant is issued here.

Metadata is the only input to this module. Target arrays are never opened by
the administrative preparation path. Mathematical producers remain unchanged.
"""
from pathlib import Path, PurePosixPath
import hashlib
import math
import re

ROLES = ('TOY_PARITY', 'ZERO_UPDATE_BRIDGE')
TARGET = 'iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
ORIGINAL_MANIFEST_SHA = 'aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8'
STOCK_BODY_SHA = '3637a96c29305a0e3f7df19ecf96f85b77f98f0dbb0e783773d217ba2be6dde6'
TRACE_SHA = '914d7d369d68579b7149c5130e3bba5d59f3b8f09a5bf691e1557ccbcd40c963'
BOUNDARY_SHA = 'bab70fe340dadb350228d37eaa0ac4521f2c1d100b2a5a8b5f8843cbecb8a6fe'
NATIVE_SHA = '9d76330f01cace4574a9ec7a5407ca50b9faacc9813bbf4339595582e5c33c27'
FIXEDPOINT_SHA = 'c573066109eef78cd19e8c60f2630ecad29d433ae9d95150d0a0fe4f7ee21571'
SCIENCE_HASHES = {
 'application/R/pricefm_r129_al_fixedpoint_certificate.R':FIXEDPOINT_SHA,
 'application/R/524_toy_fullstate_consumer.R':'0d17bb507281ca96f17a8ea2f8a60cebcba11ccee846ed666d3127321ad2df9a',
 'application/R/525_project_fullstate_consumer.R':'57566e90f15ec8c44c72800d79ba3c2979f78a9c4799a154cf542a7f627c11b2',
 'application/tests/r179_hb_toy.R':'662a48dbed4908b563ff9c24ea0e74fa35ee8cbe406ee1e973b40ed8ea77b190',
 'application/scripts/pricefm/r179_hb_bridge_or_pilot.R':'1f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3'}
DELIVERY_HASHES = {
 'contract/target.json':'35c93150286b67c3d522b587d732536df64110498fe6c31c0aa9507e85556ec1',
 'fit/beta_cov.bin':'0bb1b7fdebaa4a85ecbb371e30913f25479de175544c9050f76aaf55804d0fb9',
 'fit/beta_mean.bin':'e39e1145ced10241e2416f567d9966cc388990031e5fad684692f4a923cc8668',
 'fit/fixedpoint_certificate.json':'d5b22a44864d3a82f3e448a5c11a688fe77f21e5fc2882e8fa415a75967d0680',
 'fit/terminal.json':'f2875eaa7af4765769b9bec34eea249fe21e8a3f4b69f93a75d0e7e03d150901',
 'fit/vb_trace.csv':'305d8ef67886d1617f0a10a20d09e82d91cb7cfd576f36c1920590393586ee3e',
 'design/terminal.json':'735b18e40a305340a88f0953ff4fca914419b95ef69564cb1873afde0e4797c3',
 'parent/terminal.json':'a0528d7de54585a689628cb73b185eb20296758fa5f28267bfed8bea1e2c351f',
 'code/cran_adapter.R':'679e6c929b09b710d412962b7ccaf965885065dfce08eacb5279834b3db9a554',
 'code/cran_manifest.json':'30cd4a7eac5a59e32aa788427347962b2312aca744977e5a186e341a1a6ef4c8',
 'code/fixedpoint_helper.R':FIXEDPOINT_SHA,
 'design/X.bin':'ac7835f74bfeb6b833d15c8738d391f6cf6461770d4bfa1d0962af4941907234',
 'design/y.bin':'50ec829d66f3dad98ffe41619c09b12475823a4d93546bace702da5678c66736',
 'design/design.json':'e0a4ee224b54c7ef08250f13cce4335a1c6da2a4e4ba0b639ac1435103f95286',
 'design/scaler.json':'c11fbbef36b504a489f364f36232b54c4d5d7403da09f67acbece2bfa8bf6da8'}
DELIVERY_BYTES = {'code/cran_adapter.R':7389,'code/cran_manifest.json':2927,'code/fixedpoint_helper.R':7519,
 'contract/target.json':2595,'design/X.bin':162049536,'design/design.json':24878,'design/scaler.json':260,
 'design/terminal.json':454,'design/y.bin':388608,'fit/beta_cov.bin':1391112,'fit/beta_mean.bin':3336,
 'fit/fixedpoint_certificate.json':1860,'fit/terminal.json':2661,'fit/vb_trace.csv':35662,'parent/terminal.json':2694}
LIMITS = dict(beta_posterior_sd_rms=1e-4, covariance_whitened_rms=1e-4,
              elbo_relative=1e-8, predictor_rms=1e-6, rhs_joint_log_rates=1e-6,
              rhs_start_log_precision=1e-6, sigma_relative=1e-6)
MAX_TARGET_FILE = 192*1024**2
MAX_TARGET_TOTAL = 256*1024**2
MAX_RETURN_FILE = 16*1024**2
MAX_RETURN_TOTAL = 64*1024**2
MAX_RETURN_FILES = 256
TOY_MARKER = "source(file.path(root, 'application/R/pricefm_r129_al_fixedpoint_certificate.R'))\n"
BRIDGE_MARKER = 'read64 <- function(path, n) {\n'


def require(ok, message):
    if not ok:
        raise ValueError(message)


def strict_pin(value):
    require(type(value) is dict and set(value)=={'path','sha256'}
            and type(value['path']) is str and value['path'].startswith('/')
            and '..' not in PurePosixPath(value['path']).parts
            and re.fullmatch('[0-9a-f]{64}',value['sha256']) is not None,
            'strict absolute source pin required')
    return value


def validate_role(role, value):
    require(role in ROLES, 'pilot and unbounded numerical roles are unsupported')
    require(type(value.get('production_fits')) is int and value['production_fits']==0
            and value.get('production_acceptance') is False,
            'no production fit or promotion authority')
    if role=='TOY_PARITY':
        require(all(type(value.get(k)) is int for k in ['optimizer_invocations','combined_iterations','maximum_n','maximum_p']),
                'integer toy counters, not JSON booleans')
        require(value.get('scientific_target_data') is False
                and value.get('optimizer_invocations')==8
                and value.get('combined_iterations')==30
                and value.get('maximum_n')==128 and value.get('maximum_p')==32,
                'exact bounded frozen525 synthetic toy required')
    else:
        require(all(type(value.get(k)) is int for k in ['optimizer_invocations','optimizer_updates','n','p']),
                'integer bridge dimensions/counters')
        require(value.get('scientific_target_data') is True
                and value.get('optimizer_invocations')==value.get('optimizer_updates')==0
                and value.get('target_name')==TARGET and value.get('n')==48576
                and value.get('p')==417 and value.get('tau')==.75
                and value.get('tau0')==.0022915214919211734
                and value.get('certificate_limits')==LIMITS
                and value.get('both_RHS_starts') is True,
                'exact one NO3 zero-update target and original seven gates required')
    return True


def validate_delivery(role, delivery):
    """Validate opaque delivery metadata only, never read target bytes."""
    require(type(delivery) is list and len(delivery)<=32, 'finite delivery manifest')
    require(role in ROLES and (role!='TOY_PARITY' or delivery==[]), 'toy cannot receive real data')
    seen=set();total=0
    for row in delivery:
        strict_pin(row['source']);strict_pin(row['remote'])
        require(row['source']['sha256']==row['remote']['sha256'], 'delivery aliases retain bytes')
        rel=PurePosixPath(row['relative'])
        require(not rel.is_absolute() and '..' not in rel.parts and str(rel) not in seen,
                'unique safe delivery paths')
        require(type(row['bytes']) is int and 0<=row['bytes']<=MAX_TARGET_FILE,
                'finite target file size')
        seen.add(str(rel));total+=row['bytes']
    require(total<=MAX_TARGET_TOTAL, 'finite total opaque target envelope')
    if role=='ZERO_UPDATE_BRIDGE':
        require({r['relative']:r['source']['sha256'] for r in delivery}==DELIVERY_HASHES,
                'exact closed fifteen-file NO3 delivery; no extra target or substituted byte')
        require({r['relative']:r['bytes'] for r in delivery}==DELIVERY_BYTES and total==163921491,
                'every original opaque member has its frozen exact byte length')
        required={'design/X.bin':(162049536,'ac7835f74bfeb6b833d15c8738d391f6cf6461770d4bfa1d0962af4941907234'),
                  'design/y.bin':(388608,'50ec829d66f3dad98ffe41619c09b12475823a4d93546bace702da5678c66736'),
                  'fit/beta_cov.bin':(1391112,'0bb1b7fdebaa4a85ecbb371e30913f25479de175544c9050f76aaf55804d0fb9'),
                  'fit/beta_mean.bin':(3336,'e39e1145ced10241e2416f567d9966cc388990031e5fad684692f4a923cc8668')}
        actual={row['relative']:(row['bytes'],row['source']['sha256']) for row in delivery}
        require(all(actual.get(k)==v for k,v in required.items()), 'exact frozen NO3 opaque array identities')
    return dict(files=len(delivery),bytes=total,scientific_arrays_opened=False)


def validate_opaque_delivery_authority(value,scope,delivery,original_manifest):
    require(type(delivery) is list,'closed original opaque source metadata required')
    # The actual remote scope nonce is created later by prepare. This admission
    # validates closed source bytes; it does not claim a remote alias exists.
    validate_delivery('ZERO_UPDATE_BRIDGE',[dict(row,remote=row.get('remote') or row['source']) for row in delivery])
    strict_pin(scope);strict_pin(original_manifest)
    require(value.get('status')=='ROOT_ADMITTED_EXACT_NO3_OPAQUE_DELIVERY_ONLY'
            and value.get('scope')==scope and value.get('target_name')==TARGET
            and value.get('files')==delivery and value.get('no_optimizer_or_science_execution') is True
            and value.get('allow_opaque_transport') is True
            and all(type(value.get(key)) is int for key in ['maximum_files','maximum_file_bytes','maximum_total_bytes'])
            and value['maximum_files']==15 and value['maximum_file_bytes']==MAX_TARGET_FILE
            and value['maximum_total_bytes']==MAX_TARGET_TOTAL
            and value.get('original_manifest')==original_manifest and original_manifest['sha256']==ORIGINAL_MANIFEST_SHA,
            'fresh separately funded closed-input opaque checksum/copy/transfer authority with exact byte caps required')
    for row in delivery:
        require(type(row.get('logical_path')) is str and row['logical_path'].startswith('/')
                and '..' not in PurePosixPath(row['logical_path']).parts,'explicit original logical source alias required')
    return True


def validate_grant(spec,grant,*,now):
    role=spec['role'];validate_role(role,spec['role_limits'])
    require(all(type(grant.get(k)) is int for k in ['max_new_numerical','attempt_index','memory_MiB']),
            'integer numerical grant counters')
    require(grant.get('schema')=='pricefm_hb_scientific_stage_grant_v1'
            and grant.get('role')==role and grant.get('job_id')==spec['job_id']
            and grant.get('node')==spec['node'] and grant.get('affinity')==spec['affinity']
            and grant.get('scope_id')==spec['scope_id']
            and grant.get('memory_MiB')==8192 and grant.get('max_new_numerical')==1
            and grant.get('attempt_index')==1 and grant.get('old_claims_reused') is False
            and grant.get('old_costs_refunded') is False
            and grant.get('authorizes_production_acceptance') is False,
            'fresh exact numerical purpose grant required')
    require(grant.get('stage_deadline_epoch')==spec['expires_epoch']
            and math.isfinite(spec['expires_epoch']) and now+300<spec['expires_epoch'],
            'complete fresh numerical stage window')
    require(grant.get('conditional_parse_and_current_kernel_ACK_required') is True,
            'root numerical grant is conditional on independent parent parse and current kernel ACK')
    if role=='TOY_PARITY':
        require(grant.get('status')=='ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY'
                and grant.get('maximum_optimizer_invocations')==8
                and grant.get('maximum_total_optimizer_iterations')==30
                and grant.get('maximum_n')==128 and grant.get('maximum_p')==32
                and grant.get('authorizes_toy_optimizer') is True
                and grant.get('authorizes_production_fits') is False,
                'exact synthetic-only toy grant')
    else:
        require(grant.get('status')=='ROOT_ADMITTED_REAL_ZERO_OPTIMIZER_BRIDGE_ONLY'
                and grant.get('mode')=='bridge' and grant.get('target_name')==TARGET
                and grant.get('max_iter')==0 and grant.get('new_attempt_index')==1,
                'bridge cannot grant a pilot')
    require(grant.get('expected_stock_body_sha256')==STOCK_BODY_SHA
            and type(grant.get('maximum_CPU_seconds')) is int and grant['maximum_CPU_seconds']==300,
            'stock body and separately funded child ceiling required')
    return True


def suffix_hash(raw,role):
    marker=TOY_MARKER if role=='TOY_PARITY' else BRIDGE_MARKER
    require(raw.count(marker)==1,'exact frozen mathematical boundary')
    return hashlib.sha256(raw[raw.index(marker):].encode()).hexdigest()


def validate_port(original,ported,role):
    require(role in ROLES and suffix_hash(original,role)==suffix_hash(ported,role),
            'mathematical suffix must remain byte-identical')
    return suffix_hash(original,role)


def ordered_science_pins(mapping):
    require(set(mapping)==set(SCIENCE_HASHES),'closed five-source canonical order')
    return [mapping[name] for name in sorted(mapping)]


def output_inventory(role):
    require(role in ROLES,'supported exact numerical output producer')
    names={'RESULT.json','INVENTORY.json','PHYSICAL_SNAPSHOT.json','EXECUTION_CONTEXT.json',
           'numerical/INTENT.json','numerical/owned_guard.json','numerical/owned_tree.json',
           'numerical/child.stdout','numerical/child.stderr','numerical/RESULT.json',
           'numerical/PHYSICAL_BEFORE_R.json','numerical/PARSE_PARENT_GATE.json'}
    names|={'physical/ALLOCATION_WITNESS.json','physical/PEER_OWNERSHIP_WITNESS.json',
            'physical/PRIORITY_DRAIN_WITNESS.json','physical/NATIVE_OBSERVATIONS.json'}
    binaries=set()
    if role=='TOY_PARITY':
        names.add('numerical/toy/validation_core.json')
        for label,count in [('default_pair',4),('beta_sigma_pair',4),('checkpoint_import',1),('stress_default_pair',4)]:
            for number in range(1,count+1):
                root='numerical/toy/'+label+'/checkpoints/sweep_%04d/'%number
                binaries.add(root+'full_state.rds');names.add(root+'completed_evidence.json')
            for name in ['X.bin','y.bin']:binaries.add('numerical/toy/synthetic_data/'+label+'/'+name)
    else:
        names|={'numerical/bridge/bridge_validation.json','numerical/bridge/baseline_certificate.json'}
        binaries.add('numerical/bridge/full_state.rds')
    return names|binaries,binaries
