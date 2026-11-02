#!/usr/bin/python3.11
"""Exact additive source inventory. Never grants production authority."""
import argparse
import csv
import hashlib
import io
from pathlib import Path
import re
import subprocess

MANIFEST='docs/reproducibility/mq_typed_workflow_v2_sources_20261102.csv'
LEGACY='docs/reproducibility/integrated_forecast_transition_sources_20261031.csv'
LEGACY_SHA='cd6684a6933de85f23d942a538c1efd241e66821b974467afb108379c068887b'
NEW={
 'scripts/check_mq_typed_workflow_v2_sources.py',
 'scripts/forecast_transition_typed_v2.py',
 'scripts/mq_typed_workflow_v2.R',
 'scripts/run_integrated_quantile_forecast_v2.R',
 'scripts/validate_mq_typed_packet_v2.R',
 'application/tests/test_mq_typed_workflow_v2.R',
 'application/tests/test_forecast_transition_typed_v2.py',
 'application/tests/test_mq_typed_workflow_v2_sources.py',
 'docs/implementation_notes/mq_typed_workflow_v2_scaffold_20261102.md'}
DEPENDENCIES={LEGACY,'application/R/integrated_quantile_forecast.R',
 'scripts/mq_forecast_array_methods.R','scripts/mq_independent_cdf_certificate.R',
 'scripts/mq_streaming_cdf_certificate.R','scripts/integrated_quantile_receipts_v2.R',
 'scripts/score_integrated_quantile_forecasts.R'}

def require(ok,why):
    if not ok:raise ValueError('MQ_V2_SOURCE_GUARD: '+why)

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def structure(rows):
    require(rows and list(rows[0])==['path','role','mode','sha256','blob'],'exact manifest columns required')
    require([r['path'] for r in rows]==sorted(NEW|DEPENDENCIES),'exact sorted additive source inventory required')
    for r in rows:
        require(r['role']==('generated_v2_scaffold' if r['path'] in NEW else 'unchanged_dependency'),'source role changed')
        require(r['mode']=='100644' and re.fullmatch('[a-f0-9]{64}',r['sha256']) and
            re.fullmatch('[a-f0-9]{40}',r['blob']),'non-executable source hashes required')

def check(root,manifest_sha256):
    root=Path(root).resolve(strict=True);path=root/MANIFEST
    require(re.fullmatch('[a-f0-9]{64}',manifest_sha256) and path.is_file() and not path.is_symlink() and
        sha(path)==manifest_sha256,'caller manifest pin differs')
    rows=list(csv.DictReader(io.StringIO(path.read_text())));structure(rows)
    require(sha(root/LEGACY)==LEGACY_SHA,'legacy v1 authorization must remain byte-identical')
    def git(*args):
        return subprocess.check_output(['git','--no-replace-objects','-C',str(root),*args],text=True).strip()
    def bytes_match(row):
        p=root/row['path']
        require(p.is_file() and not p.is_symlink() and not p.stat().st_mode&0o111,'missing/symlink/executable source')
        require(sha(p)==row['sha256'] and git('hash-object','--no-filters','--',row['path'])==row['blob'],
            'source bytes differ: '+row['path'])
        stage=git('ls-files','--stage','--',row['path'])
        require(stage=='100644 '+row['blob']+' 0\t'+row['path'],'index/source differs: '+row['path'])
    for row in rows:bytes_match(row)
    # Independently verify all original v1 authorized files, without editing
    # its inventory, wildcard scopes or original R guard.
    legacy=list(csv.DictReader(io.StringIO((root/LEGACY).read_text())))
    require(len(legacy)==27 and len({r['path'] for r in legacy})==27,'legacy inventory changed')
    for row in legacy:bytes_match(row)
    return dict(status='MQ_TYPED_V2_SOURCE_BYTES_MATCH_NOT_PRODUCTION',new_files=len(NEW),
        unchanged_dependencies=len(DEPENDENCIES),legacy_files=len(legacy),production_authorized=False)

def main():
    p=argparse.ArgumentParser();p.add_argument('--manifest-sha256',required=True);a=p.parse_args()
    print(check(Path(__file__).resolve().parents[1],a.manifest_sha256))

if __name__=='__main__':main()
