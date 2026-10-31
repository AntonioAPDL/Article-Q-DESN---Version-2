"""One bounded, read-only JSON/source packet for the exact FR provenance gap.

This file is Python3.6 compatible for Jerez. It has no subprocess, network,
model or numerical imports and never opens a scientific binary. The reviewed
source is shipped as one SSH command; the parent supplies original guarding.
"""
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import resource
import signal
import stat
import time

DATA = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm')
PREFIX = 'iq_FR_r134_19bfb4ca7088512b_t1.000000000000e-03_s1'
ROOTS = tuple(DATA/'campaigns'/name for name in (
    'pricefm_stage_r141_recovery_rollout_20261019__FR',
    'pricefm_stage_r140_frozen_all_region_rollout_20261018__FR',
    'pricefm_stage_r134_pure_qdesn_optimization_20261011',
    'pricefm_stage_r135_r134_fixedpoint_completion_20261012'))
TASKS = tuple(PREFIX+'_al'+tau for tau in ('0.10','0.25','0.45','0.50','0.55','0.75','0.90'))
SUFFIXES = ('completed_evidence.json','result.json','fit/terminal.json','fit/fixedpoint_certificate.json')
MAX_FILES, MAX_BYTES, MAX_TOTAL = 256, 2*1024**2, 12*1024**2

def physical(path):
    if not path.is_absolute() or any(p.is_symlink() for p in (path,)+tuple(path.parents)):
        raise ValueError('nonphysical path')
    return path

def read_one(path):
    physical(path)
    try:
        before = path.stat()
    except FileNotFoundError:
        return {'path':str(path),'exists':False}
    if not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or before.st_nlink < 1 or before.st_size > MAX_BYTES:
        raise ValueError('unsafe source metadata')
    raw = path.read_bytes(); after = path.stat()
    fields = ('st_dev','st_ino','st_size','st_mtime_ns','st_ctime_ns')
    if any(getattr(before,k) != getattr(after,k) for k in fields) or len(raw) != before.st_size:
        raise ValueError('unstable source metadata')
    def unique(pairs):
        result = {}
        for key,value in pairs:
            if key in result: raise ValueError('duplicate JSON key')
            result[key] = value
        return result
    value = json.loads(raw.decode(), object_pairs_hook=unique,
                       parse_constant=lambda x: (_ for _ in ()).throw(ValueError('nonfinite JSON')))
    def finite(value):
        if isinstance(value,float) and not math.isfinite(value): raise ValueError('overflow JSON')
        if isinstance(value,dict):
            for x in value.values(): finite(x)
        elif isinstance(value,list):
            for x in value: finite(x)
    finite(value)
    return {'path':str(path),'exists':True,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
            'base64':base64.b64encode(raw).decode(),'uid':before.st_uid,'nlink':before.st_nlink}

def collect(expires_epoch):
    resource.setrlimit(resource.RLIMIT_CPU,(8,8)); signal.alarm(90)
    if os.sched_getaffinity(0) != {31}:
        raise ValueError('CPU31 metadata lane required')
    if not time.time() < expires_epoch:
        raise ValueError('fresh source-bound observation expired')
    output, total, directories = [], 0, []
    for root in ROOTS:
        physical(root)
        directories.append({'path':str(root),'exists':root.is_dir()})
        if not root.is_dir():
            continue
        paths = [root/'tasks'/(name+'.json') for name in TASKS]
        paths += [root/'tasks_done'/name/suffix for name in TASKS for suffix in SUFFIXES]
        # Inspect only a bounded interrupted-attempt namespace; never recurse.
        interrupted = root/'interrupted_attempts'
        if interrupted.is_dir():
            physical(interrupted)
            entries = []
            for entry in interrupted.iterdir():
                if len(entries) >= 4096:
                    raise ValueError('interrupted namespace exceeds finite inventory')
                entries.append(entry)
            matches = [p for p in entries if any(p.name.startswith(name+'.') for name in TASKS)]
            if len(matches) > 16:
                raise ValueError('too many exact-target interrupted attempts')
            paths += [p/suffix for p in sorted(matches) for suffix in SUFFIXES]
        for path in paths:
            if len(output) >= MAX_FILES:
                raise ValueError('packet file cap')
            row = read_one(path); total += row.get('bytes',0)
            if total > MAX_TOTAL:
                raise ValueError('packet byte cap')
            output.append(row)
    return {'schema':'pricefm_exact_FR_original_metadata_packet_v1','observed_epoch':time.time(),
            'roots':directories,'records':output,'total_payload_bytes':total,'SELF_CPU':sum(resource.getrusage(resource.RUSAGE_SELF)[:2]),
            'source_files_only':True,'new_fits_losses_predictions_models_arrays_writes':0}

if __name__ == '__main__':
    print(json.dumps(collect(PRICEFM_EVIDENCE_EXPIRY),sort_keys=True,allow_nan=False),flush=True)
