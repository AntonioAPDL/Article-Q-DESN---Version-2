#!/usr/bin/env python3
"""I/O-only preparation of the exact NO3 larger-tau snapshot on Muscat.

Reads original Jerez bytes and writes only a new private staging directory.
No model/array numerical operations or production writes are implemented.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import resource
import shlex
import subprocess
import time

TARGET='iq_NO_3_r134_283a8c333135aae3_t2.291521491921e-03_s1_al0.75'
SOURCE_MANIFEST='/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r154_certificate_reference_20261026/application/config/pricefm/522_fixed_state_targets.json'
SOURCE_SHA='aecbee983a05bb4bebbc86b345a8678d1879116c9a273a618ff05dcaaff99af8'


def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
    return h.hexdigest()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output-dir',required=True)
    args=parser.parse_args()
    if os.sched_getaffinity(0)!={31}:raise ValueError('I/O preparation must use administrative CPU31')
    if sha(SOURCE_MANIFEST)!=SOURCE_SHA:raise ValueError('frozen V4 manifest changed')
    manifest=json.loads(Path(SOURCE_MANIFEST).read_text())
    target=next(t for t in manifest['targets'] if t['name']==TARGET)
    out=Path(args.output_dir).resolve()
    allowed=Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_chat_continuation_20261021/r154_parallel_repair_20261026/certificates/expansion')
    if allowed not in out.parents or out.exists():raise ValueError('new private expansion directory required')
    out.mkdir(parents=True)
    contract=target['contract'];source_campaign=Path(contract['output_dir']).parents[2]
    requests={item['path']:item['sha256'] for item in target['bindings']}
    terminal_path=Path(contract['design_dir'])/'terminal.json'
    # Obtain only terminal metadata first. Its original seal determines every
    # design byte expected from Jerez; local hash validation follows each copy.
    command=' '.join(shlex.quote(x) for x in ['taskset','-c','31','nice','-n','10','cat','--',str(terminal_path)])
    raw=subprocess.run(['ssh','-o','BatchMode=yes','jerez',command],capture_output=True,check=True).stdout
    if hashlib.sha256(raw).hexdigest()!=contract['design_terminal_sha256']:raise ValueError('design terminal changed')
    terminal=json.loads(raw)
    for name,digest in terminal['files'].items():
        if Path(name).name!=name:raise ValueError('unsafe design member')
        requests[str(Path(contract['design_dir'])/name)]=digest
    aliases={};receipts=[];total=0;started=time.monotonic()
    canonical_adapter=next(t['contract']['cran_adapter'] for t in manifest['targets'] if t['region']=='LT')
    for source,digest in sorted(requests.items()):
        original=Path(source)
        # A local source is an alias only after its exact expected hash is
        # checked. No claim is made that Jerez paths exist on Muscat.
        candidates=[original]
        if source==contract['cran_adapter']:candidates.append(Path(canonical_adapter))
        existing=next((p for p in candidates if p.is_file() and not p.is_symlink() and sha(p)==digest),None)
        if existing is not None and not original.is_relative_to(source_campaign):
            aliases[source]=str(existing);receipts.append(dict(source_path=source,local_path=str(existing),sha256=digest,kind='exact_existing_local_source_alias'));continue
        if original.is_relative_to(source_campaign):
            destination=out/'campaign'/original.relative_to(source_campaign)
        else:
            destination=out/'sources'/hashlib.sha256(source.encode()).hexdigest()[:16]/original.name
        destination.parent.mkdir(parents=True,exist_ok=True)
        remote=' '.join(shlex.quote(x) for x in ['taskset','-c','31','nice','-n','10','cat','--',source])
        with open(destination,'xb') as f:
            subprocess.run(['ssh','-o','BatchMode=yes','jerez',remote],stdout=f,stderr=subprocess.PIPE,check=True)
        if sha(destination)!=digest:raise ValueError('staged bytes differ: '+source)
        size=destination.stat().st_size;total+=size
        if total>2*1024**3:raise ValueError('staging exceeds original disk ceiling')
        aliases[source]=str(destination)
        receipts.append(dict(source_host='jerez',execution_host='muscat',source_path=source,
            local_path=str(destination),sha256=digest,bytes=size,kind='exact_byte_copy_no_numeric_transformation'))
    for key in ['design_dir','output_dir','parent_dir']:
        aliases[contract[key]]=str(out/'campaign'/Path(contract[key]).relative_to(source_campaign))
    usage=resource.getrusage(resource.RUSAGE_CHILDREN)
    result=dict(schema='r154_exact_NO3_cross_host_alias_v1',target=TARGET,source_host='jerez',
        execution_host='muscat',source_manifest=dict(path=SOURCE_MANIFEST,sha256=SOURCE_SHA),
        aliases=aliases,files=receipts,staged_bytes=total,read_only_originals=True,
        posterior_target_unchanged=True,bitwise_original_intermediate_recovery_claimed=False,
        cross_host_recipe_scalar_reproduction_must_be_measured=True,
        target_numeric_calls=0,posterior_fits=0,wall_seconds=time.monotonic()-started,
        parent_CPU_seconds=time.process_time(),reaped_SSH_CPU_seconds=usage.ru_utime+usage.ru_stime,
        remote_reader_CPU_seconds_not_directly_measured=True)
    with open(out/'alias_manifest.json','x') as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
    print(json.dumps(dict(status='EXACT_BYTES_STAGED_NO_TARGET_MATH',files=len(receipts),staged_bytes=total,
        alias_manifest_sha256=sha(out/'alias_manifest.json'))))


if __name__=='__main__':main()
