"""Fixed compute-only initial qualification entry. Never imports target kernels on admin."""
import hashlib,json,os
from pathlib import Path
def run(spec_pin,authority_pin,review_pin,ack_pin):
    # First executable gate uses only the actual kernel job identity.
    job=os.environ.get('SLURM_JOB_ID','');node=os.uname().nodename.split('.')[0]
    if not job.isdigit() or os.environ.get('SLURMD_NODENAME')!=node or not node.startswith('node-'):
        raise ValueError('actual Slurm child before supplied records or kernels')
    root=Path(__file__).absolute().parent.parent
    # Fixed boundary source is authenticated by native bootstrap's complete reviewed closure.
    import importlib.util
    p=root/'qualification/qualification_boundary.py';sp=importlib.util.spec_from_file_location('_r201_actual_qualification_boundary',p)
    raw=p.read_bytes()
    if any(v.is_symlink() for v in (p,*p.parents)) or hashlib.sha256(raw).hexdigest()!='67c3d2050521a8c6bbaf378371f3f657df754e747e5325211f8e38b45aa887e0':
        raise ValueError('exact boundary bytes before interpretation')
    boundary=importlib.util.module_from_spec(sp);exec(compile(raw,str(p),'exec'),boundary.__dict__)
    ctx=boundary.acquire(spec_pin,authority_pin,review_pin,ack_pin);ctx.verify_live()
    review=boundary.m.linked(review_pin)
    fixtures=boundary.load_fixed(review,'regional_reference/analytical_fixtures.py')
    kernel=boundary.load_fixed(review,'regional_reference/decimal_reference.py')
    ctx.verify_live()
    result=fixtures._run_compute_only(kernel)
    ctx.verify_live()
    if result.get('cases')!=9 or result.get('precision_evaluations')!=27 or result.get('optimizer_updates')!=0:
        raise ValueError('complete fixed analytical qualification only')
    spec=boundary.m.linked(spec_pin);launch=boundary.m.linked(spec['owner_launch'])
    result.update(role=boundary.c.ROLE,job_id=spec['job_id'],node=spec['node'],
      source_map_sha256=spec['source_map_sha256'],case_sha256=spec['case_sha256'],
      native_build_acceptance=launch['native_build_acceptance'],
      native_deployment_acceptance=launch['native_deployment_acceptance'],
      startup_python=launch['native_executable'],
      canonical_metadata_namespace=boundary.m.linked(boundary.m.linked(spec['deployment_acceptance'])['result'])['canonical_metadata_namespace'],
      native_ACK_and_live_identity_verified=True,production_admission=False,scientific_acceptance=False)
    raw=(json.dumps(result,sort_keys=True,separators=(',',':'),allow_nan=False)+'\n').encode('ascii')
    if len(raw)>16*1024**2:raise ValueError('qualification result exceeds prewrite envelope')
    return dict(schema='r200_reference_owned_return_parts_v1',
      records=[dict(relative_path='qualification_summary.json',sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw),payload=raw)],
      total_bytes=len(raw),complete_full_covariance=False,payloads_are_owned_compute_output_not_admin_fixtures=True,
      scientific_acceptance=False,runtime_admission_transferred=False)
