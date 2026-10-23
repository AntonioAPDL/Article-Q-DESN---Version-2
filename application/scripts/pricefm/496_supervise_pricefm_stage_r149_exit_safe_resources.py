#!/usr/bin/env python3
"""R149 resource-only exit-race correction; science and original lease stay frozen."""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
CONFIG = ROOT / 'application/config/pricefm_stage_r149_exit_safe_resources_20261023.json'
KERNEL_PATH = ROOT / 'application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py'
SCIENCE_ROOT = Path('/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/worktrees/pricefm_r149_ee_origin_coverage_20261023')
SCIENCE = SCIENCE_ROOT / 'application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py'
SCIENCE_HEAD = '0d562470f7112da0e94cc61b4bf18de8a93a5112'
TAG = 'pricefm_stage_r149_ee_origin_coverage_20261023'
UNIT = 'pricefm-r149-muscat-ee-idle-recovery.service'


def load_kernel():
    spec = importlib.util.spec_from_file_location('pricefm_r149_exit_safe_kernel', KERNEL_PATH)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    m.ROOT = ROOT; m.ENTRY = ENTRY; m.CONFIG = CONFIG; m.SCIENCE = SCIENCE
    m.STAGE = 'R149'
    m.REQUIRED_BRANCH = 'work/pricefm-r149-exit-safe-resources-20261023'
    m.REQUIRED_UNIT = UNIT
    m.ALLOWED_TASK_KINDS = ['full_origin_replay', 'mc_panel_replay']
    m.REQUIRE_ALL_TASKS_COMPLETE = True
    # The external science source is pinned explicitly in frozen_baseline_sources;
    # it must not be relabelled as a relative file in this resource worktree.
    m.SOURCE_PATHS = [ENTRY, CONFIG, KERNEL_PATH,
        ROOT / 'application/tests/test_pricefm_stage_r148_ee_idle_resources.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_exit_snapshot.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_exit_safe_resources.py',
        ROOT / 'docs/implementation_notes/pricefm_stage_r149_exit_safe_resources_20261023.md']
    inherited_validate = m.validate_config
    def validate_config(c):
        inherited_validate(c)
        data = Path(c['data_root'])
        scientific_pins = [p for p in c['frozen_baseline_sources'] if p['root'] == str(SCIENCE_ROOT)]
        if (c['tag'] != TAG or c['same_original_lease_required'] is not True
                or c['new_explicit_R149_lease_authorized'] is not False
                or c['scientific_root'] != str(SCIENCE_ROOT) or c['scientific_head'] != SCIENCE_HEAD
                or c['scientific_entry'] != str(SCIENCE) or len(scientific_pins) != 1
                or scientific_pins[0]['head'] != SCIENCE_HEAD or len(scientific_pins[0]['sha256']) != 11
                or Path(c['runtime']) != data / 'launch_prep' / TAG / 'muscat_resources_exit_safe'
                or Path(c['campaign_root']) != data / 'campaigns' / TAG
                or c['min_available_memory_gib'] < 192
                or c['original_resource_unit'] != 'pricefm-r149-muscat-ee-idle-development.service'):
            raise RuntimeError('resource recovery must preserve original scientific source, budget and lease')
    m.validate_config = validate_config

    def pinned(c, key):
        item = c[key]
        if m.digest(item['path']) != item['sha256']:
            raise RuntimeError('immutable recovery pin changed: ' + key)
        return m.read(item['path'])

    def new_lease(c, runtime):
        original = pinned(c, 'lease_import')
        path = Path(runtime) / 'lease.json'
        if not path.is_file() or m.digest(path) != c['lease_import']['sha256']:
            raise RuntimeError('exact original lease bytes must be imported; no new lease is authorized')
        if m.read(path) != original:
            raise RuntimeError('imported original lease differs')
        return original
    m.new_lease = new_lease
    inherited_guard = m.guard
    def guard(c, lease, **kwargs):
        inherited_guard(c, lease, **kwargs)
        if lease != pinned(c, 'lease_import'):
            raise RuntimeError('lease start/expiry/boot/growth budget cannot change on recovery')
        previous = pinned(c, 'stopped_predecessor')
        if (previous['status'] != 'R149_IDLE_LEASE_STOPPED' or previous['cleanup_verified'] is not True
                or previous['baseline_worker_signals'] != 0 or previous['source']['head'] != SCIENCE_HEAD):
            raise RuntimeError('original resource attempt must be stopped and cleanup verified')
        old = m.unit_properties(c['original_resource_unit'])
        if old.get('MainPID') != '0' or old.get('ActiveState') != 'inactive' or old.get('ControlGroup'):
            raise RuntimeError('original private development unit has not fully drained')
        predecessor = c['completed_predecessor']
        if m.digest(predecessor['path']) != predecessor['sha256']:
            raise RuntimeError('completed R148 evidence changed')
        done = m.read(predecessor['path'])
        if (done['status'] != 'R148_IDLE_TASKS_COMPLETE_NOT_PROMOTED'
                or done['cleanup_verified'] is not True or done['baseline_worker_signals'] != 0
                or done['source']['head'] != predecessor['source_head']):
            raise RuntimeError('original R148 must remain complete and drained')
        if kwargs.get('check_sources'):
            snapshot = pinned(c, 'supersession_snapshot')
            if (snapshot['scientific_source']['head'] != SCIENCE_HEAD
                    or snapshot['original_lease_sha256'] != c['lease_import']['sha256']
                    or snapshot['task_descriptor_count'] != 18):
                raise RuntimeError('scientific supersession identity changed')
            for path, expected in snapshot['artifact_sha256'].items():
                if m.digest(path) != expected:
                    raise RuntimeError('existing sealed science changed on resource recovery: ' + path)
    m.guard = guard
    return m


KERNEL = load_kernel()

if __name__ == '__main__':
    raise SystemExit(KERNEL.main())
