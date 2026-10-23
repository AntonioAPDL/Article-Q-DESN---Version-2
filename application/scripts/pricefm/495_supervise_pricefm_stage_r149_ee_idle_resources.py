#!/usr/bin/env python3
"""R149 context for the tested R148 idle-resource kernel.

The inherited 493 copy supplies scheduling, gated admission, zombie lifetime
proof, private-cgroup cleanup, and the nonrenewing lease. R149 changes context
only: its own source, service, campaign, task kinds, and an explicitly authorized
new two-hour lease. The completed original R148 source/runtime stays untouched.

The 0.5-second sleep is a polling target, not a response deadline: source/seal
verification and filesystem operations can delay the next guard check. Final
semantic validation starts after all owned workers exit. During observation
latency SCHED_IDLE protects baseline CPU priority; RSS enforcement stays soft.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
ENTRY = Path(__file__).resolve()
TAG = 'pricefm_stage_r149_ee_origin_coverage_20261023'
CONFIG = ROOT / 'application/config/pricefm_stage_r149_ee_idle_resources_20261023.json'
SCIENCE = ROOT / 'application/scripts/pricefm/494_run_pricefm_stage_r149_ee_origin_coverage.py'
KERNEL_PATH = ROOT / 'application/scripts/pricefm/493_supervise_pricefm_stage_r148_ee_idle_resources.py'
KINDS = ['full_origin_replay', 'mc_panel_replay']


def load_kernel():
    spec = importlib.util.spec_from_file_location('pricefm_r149_idle_kernel', KERNEL_PATH)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    module.ROOT = ROOT; module.ENTRY = ENTRY; module.CONFIG = CONFIG; module.SCIENCE = SCIENCE
    module.STAGE = 'R149'
    module.REQUIRED_BRANCH = 'work/pricefm-r149-ee-origin-coverage-20261023'
    module.REQUIRED_UNIT = 'pricefm-r149-muscat-ee-idle-development.service'
    module.ALLOWED_TASK_KINDS = KINDS
    module.REQUIRE_ALL_TASKS_COMPLETE = True
    module.SOURCE_PATHS = [ENTRY, KERNEL_PATH, CONFIG, SCIENCE,
        ROOT / 'application/scripts/pricefm/pricefm_r149_sampling_analysis.py',
        ROOT / 'application/config/pricefm_stage_r149_ee_origin_coverage_20261023.json',
        ROOT / 'application/tests/test_pricefm_stage_r148_ee_idle_resources.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_ee_idle_resources.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_ee_origin_coverage.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_scientific_review.py',
        ROOT / 'application/tests/test_pricefm_stage_r149_sampling_analysis.py',
        ROOT / 'docs/implementation_notes/pricefm_stage_r149_ee_origin_coverage_20261023.md']
    inherited_validate = module.validate_config
    def validate(config):
        inherited_validate(config)
        data = Path(config['data_root'])
        if (config['tag'] != TAG or config['new_explicit_R149_lease_authorized'] is not True
                or config['min_available_memory_gib'] < 192
                or Path(config['runtime']) != data / 'launch_prep' / TAG / 'muscat_resources'
                or Path(config['campaign_root']) != data / 'campaigns' / TAG):
            raise RuntimeError('R149 must use its separate explicitly authorized lease/campaign and192GiB reserve')
    module.validate_config = validate
    inherited_guard = module.guard
    def guard(config, lease, **kwargs):
        inherited_guard(config, lease, **kwargs)
        predecessor = config['completed_predecessor']
        if module.digest(predecessor['path']) != predecessor['sha256']:
            raise RuntimeError('completed original R148 terminal changed')
        terminal = module.read(predecessor['path'])
        if (terminal['status'] != 'R148_IDLE_TASKS_COMPLETE_NOT_PROMOTED'
                or terminal.get('cleanup_verified') is not True
                or terminal['source']['head'] != predecessor['source_head']
                or terminal.get('baseline_worker_signals') != 0):
            raise RuntimeError('original R148 must remain complete and drained before R149 admission')
    module.guard = guard
    return module


KERNEL = load_kernel()


def main():
    return KERNEL.main()


if __name__ == '__main__':
    raise SystemExit(main())
