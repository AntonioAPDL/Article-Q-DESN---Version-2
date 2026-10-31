"""Prepare additive R scientific CODE carriers without executing a runtime.

Reuses the already verified base-R archive and unchanged streaming/hash/readback
machinery. Each part is an opaque R startup-code archive; the outer manifest
identifies the distinct scientific-namespace addon purpose. Neither namespace
loading, ABI compatibility, the scientific boundary nor numerical parity is
claimed. No campaign/target files or installed package datasets are included.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import resource
import signal
import time

from . import runtime_archive as archive
from . import runtime_carrier as native
from .local_readiness import runtime_targets

ORIGIN = native.ORIGIN
PRIVATE_LIBRARY = Path('/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_libraries/exdqlm_cran_1p1p1')
BASE_MANIFEST_SHA = '60eb4229602956510631bb6989de7d20ccd47cae7f6ab32bbfd6841d64af28e6'
BASE_ARCHIVE_SHA = 'c94cadf4c75a56113355e86f2e485b1bba0c6e61ffee058bd22f681f4ba7132a'
RUNTIME_BINDING_SHA = 'b365a26fe3c0ec89126193f75e66904f97907bcbf0e89a330cd837ea818fbb14'
MAX_PACKAGES = 96
EXCLUDE = {'data','help','html','doc','demo','tests','include'}
PART_BYTES = 112 * 1024**2
NAME = re.compile(r'[A-Za-z][A-Za-z0-9.]*\Z')


def description(path):
    raw = archive.physical(path).read_bytes()
    archive.require(len(raw) <= 1024**2, 'bounded DESCRIPTION required')
    fields, key = {}, None
    for line in raw.decode().splitlines():
        if line[:1].isspace() and key:
            fields[key] += ' ' + line.strip()
        elif ':' in line:
            key, value = line.split(':',1)
            archive.require(key not in fields, 'duplicate DESCRIPTION field')
            fields[key] = value.strip()
    return fields


def dependencies(fields):
    result = set()
    for field in ('Imports','Depends'):
        for item in fields.get(field,'').split(','):
            name = item.strip().split('(',1)[0].strip()
            if not name or name == 'R': continue
            archive.require(NAME.fullmatch(name), 'unsafe package dependency name')
            result.add(name)
    return sorted(result)


def resolve_package(name):
    archive.require(NAME.fullmatch(name), 'unsafe package name')
    roots = (PRIVATE_LIBRARY, ORIGIN/'library') if name == 'exdqlm' else (ORIGIN/'library',)
    for root in roots:
        path = root/name
        if (path/'DESCRIPTION').is_file(): return archive.physical(path)
    raise ValueError('required installed namespace absent: ' + name)


def package_closure(roots=('exdqlm','digest','jsonlite')):
    pending, found = list(roots), {}
    while pending:
        name = pending.pop()
        if name in found: continue
        path = resolve_package(name); fields = description(path/'DESCRIPTION')
        archive.require(fields.get('Package') == name and fields.get('Version'), 'installed package identity differs')
        if name == 'exdqlm':
            archive.require(fields['Version']=='1.1.1' and fields.get('Repository')=='CRAN', 'fixed CRAN exdqlm1.1.1 required')
        deps = dependencies(fields)
        found[name] = {'path':str(path), 'version':fields['Version'], 'dependencies':deps,
                       'DESCRIPTION':archive.pin(path/'DESCRIPTION'), 'priority':fields.get('Priority'),
                       'LinkingTo_not_needed_for_precompiled_namespace_startup':fields.get('LinkingTo','')}
        archive.require(len(found) <= MAX_PACKAGES, 'scientific package closure exceeds bound')
        pending.extend(deps)
    return found


def code_sources(packages, base):
    sources, excluded = {}, {}
    for name, meta in sorted(packages.items()):
        root = Path(meta['path']); omitted = set()
        for path in sorted(root.rglob('*')):
            if not path.is_file(): continue
            relative = path.relative_to(root)
            if relative.parts[0] in EXCLUDE:
                omitted.add(relative.parts[0]); continue
            archive.require(path.resolve(strict=True).is_relative_to(root), 'package code symlink escapes exact installed package')
            member = 'R_HOME/library/' + name + '/' + str(relative)
            native.validate_source_names(path)
            if member in base:
                archive.require(archive.digest(path) == base[member]['sha256'], 'base package bytes differ')
            else:
                sources[member] = path
        excluded[name] = sorted(omitted)
    return sources, excluded


def native_closure(sources, base):
    sources = dict(sources)
    pending, inspected, glibc, versions = list(sources.values()), set(), set(), set()
    header_pins = {}
    while pending:
        path = pending.pop(); before = archive.binding(path)
        real = before['resolved']
        if real in inspected: continue
        inspected.add(real)
        needed, required = native.dynamic(path)
        archive.require(archive.binding(path) == before, 'native dependency source drift')
        if needed or required: header_pins[real] = dict(before, needed=needed, GLIBC_versions=required)
        versions.update(required)
        for name in needed:
            if native.host_glibc(name):
                glibc.add(name); continue
            source = native.resolve_library(name); native.validate_source_names(source)
            member = 'R_HOME/lib/'+name if 'R_HOME/lib/'+name in base else 'lib/'+name
            if member in base:
                archive.require(archive.digest(source) == base[member]['sha256'], 'base native dependency collision')
            elif member not in sources:
                sources[member] = source; pending.append(source)
    return sources, {'host_glibc_not_bundled':sorted(glibc),'required_GLIBC_versions':sorted(versions),
                     'native_header_bindings':header_pins,'actual_compute_ABI_and_namespace_startup_required':True}


def partition(rows):
    parts, current, size = [], [], 0
    for row in sorted(rows,key=lambda x:x['relative']):
        archive.require(row['bytes'] <= archive.MAX_FILE, 'one code file exceeds unchanged archive file limit')
        if current and (size+row['bytes'] > PART_BYTES or len(current) == archive.MAX_FILES):
            parts.append(current); current=[]; size=0
        current.append(row); size += row['bytes']
    if current: parts.append(current)
    archive.require(0 < len(parts) <= 4, 'bounded additive archive part count required')
    for part in parts: archive.shape_rows(part)
    return parts


def build(config_pin):
    archive.require(os.sched_getaffinity(0)=={31}, 'metadata CPU31 required')
    cfg=archive.read(config_pin); scope=archive.read(cfg['scope'])
    archive.require(scope['issued_epoch'] <= time.time()+300 < scope['expires_epoch']
                    and scope['runtime_code_preparation_CPU'] == 32,
                    'complete new code-only archive preparation scope required')
    archive.require(cfg['base_manifest']['sha256']==BASE_MANIFEST_SHA and cfg['base_archive']['sha256']==BASE_ARCHIVE_SHA,
                    'verified base carrier must be reused without rebuild')
    base_manifest=archive.read(cfg['base_manifest'])
    archive.require(base_manifest['file_count']==680 and archive.pin(cfg['base_archive']['path'])==cfg['base_archive'],
                    'base carrier bytes changed')
    archive.require(cfg['runtime_binding']['sha256']==RUNTIME_BINDING_SHA,'fixed actual installed runtime binding required')
    runtime_binding=archive.read(cfg['runtime_binding'])
    original_runtime_files=runtime_targets(runtime_binding)
    for name,sha in original_runtime_files.items():
        archive.require(archive.digest(name)==sha,'original installed runtime binding drift: '+name)
    base={row['relative']:row for row in base_manifest['files']}
    out=archive.physical(cfg['output']); archive.require(not out.exists() and out.parent.is_dir(),'new code-only output required')
    out.mkdir(mode=0o700)
    archive.write_json(out/'INTENT.json',{'status':'SCIENTIFIC_CODE_CLOSURE_INTENT_NOT_STARTUP_PROOF','scope':cfg['scope'],'source':archive.pin(__file__),'base_manifest':cfg['base_manifest'],'base_archive':cfg['base_archive'],'R_executions':0,'scientific_target_data':False})
    packages=package_closure()
    sources,excluded=code_sources(packages,base)
    sources,abi=native_closure(sources,base)
    rows=[]
    for member,path in sorted(sources.items()):
        before=archive.binding(path); sha=archive.digest(before['resolved'])
        archive.require(archive.binding(path)==before,'source drift during scientific closure hash')
        rows.append(dict(before,relative=member,sha256=sha))
    parts=partition(rows); receipts=[]
    provenance={'specific_purpose':'R179_ADDITIVE_SCIENTIFIC_NAMESPACE_CODE_ONLY','base_archive':cfg['base_archive'],
                'base_manifest':cfg['base_manifest'],'base_R_not_rebuilt':True,'source':archive.pin(__file__),
                'installed_target_data_directories_excluded':True,'no_R_or_numerical_execution':True}
    for i,part in enumerate(parts,1):
        # The unchanged container helper accepts real R startup-code files. The
        # distinct outer purpose is addon preparation, not a base/ABI proof.
        archive.stream_archive(out/('part_%02d'%i),part,'REAL_R46_STARTUP_ARCHIVE',provenance,out)
        receipts.append(archive.read_json(out/('part_%02d'%i)/'RESULT.json'))
    record={'schema':'r179_scientific_code_closure_v1','status':'COMPLETE_ADDITIVE_CODE_CARRIERS_NOT_RUNTIME_OR_NUMERICAL_PROOF',
            'created_epoch':time.time(),'scope':cfg['scope'],'source':archive.pin(__file__),
            'unchanged_archive_helper':archive.pin(Path(archive.__file__)),'unchanged_native_dependency_helper':archive.pin(Path(native.__file__)),
            'base_manifest':cfg['base_manifest'],'base_archive':cfg['base_archive'],'packages':packages,
            'original_runtime_binding':cfg['runtime_binding'],'original_runtime_files_reverified':len(original_runtime_files),
            'excluded_non_runtime_directories':excluded,'native_ABI_requirements':abi,'parts':receipts,
            'file_count':len(rows),'code_bytes':sum(r['bytes'] for r in rows),'base_members_overwritten':[],
            'R_executions':0,'scientific_data_access':False,'namespace_startup_proved':False,'ABI_proved':False,
            'scientific_boundary_proved':False,'numerical_parity_proved':False,
            'actual_compute_qualification_required':['namespace_versions_and_stock_body','loaded_ELF_and_ABI','scientific_TSYNC_boundary','fullstate_toy']}
    archive.write_json(out/'SCIENTIFIC_CLOSURE_MANIFEST.json',record)
    return record


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--config',required=True);p.add_argument('--config-sha256',required=True)
    args=p.parse_args(argv);resource.setrlimit(resource.RLIMIT_CPU,(32,32));signal.alarm(300)
    record=build({'path':args.config,'sha256':args.config_sha256})
    print(json.dumps({k:record[k] for k in ['status','file_count','code_bytes','R_executions','namespace_startup_proved']},sort_keys=True))


if __name__=='__main__':main()
