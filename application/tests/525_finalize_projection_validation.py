#!/usr/bin/env python3
"""Metadata-only finalizer, after the admitted synthetic R child is reaped."""
import argparse
import hashlib
import json
import os
from pathlib import Path


def require(ok, message):
    if not ok:
        raise ValueError(message)


def digest(path):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'regular nonsymlink file required')
    result = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            result.update(block)
    return result.hexdigest()


def pin(path):
    return dict(path=str(Path(path).resolve()), sha256=digest(path))


def read(value):
    require(type(value) is dict and set(value) == {'path', 'sha256'}, 'exact file pin required')
    require(digest(value['path']) == value['sha256'], 'file pin changed')
    return json.loads(Path(value['path']).read_text())


def finalize(core_pin, grant_pin, guard_pin, output):
    core, grant, guard = read(core_pin), read(grant_pin), read(guard_pin)
    require(grant.get('status') == 'ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY' and
            grant.get('authorizes_toy_optimizer') is True and
            grant.get('authorizes_production_fits') is False and
            grant.get('authorizes_production_acceptance') is False,
            'not an admitted synthetic projection run')
    require(core.get('schema') == 'r154_project_adapter_validation_core_v1' and
            core.get('status') == 'NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF' and
            core.get('root_grant_pin') == grant_pin and core.get('source') == grant['source'],
            'core schema/admission/source mismatch')
    require(core.get('actual_R_runtime_binding') == grant['actual_R_runtime_binding'] ==
            guard.get('actual_R_runtime_binding'), 'actual execution runtime differs')
    read(grant['actual_R_runtime_binding'])
    require(guard.get('schema') == 'r154_owned_stage_guard_receipt_v1' and
            guard.get('status') == 'EXITED' and type(guard.get('returncode')) is int and
            guard['returncode'] == 0 and guard.get('source') == grant['source'] and
            guard.get('root_grant_sha256') == grant_pin['sha256'] and
            guard.get('launcher') == 'pinned_native_ELF_no_Rscript_shell_wrapper' and
            guard.get('validation_kind') == 'synthetic_project_projection_only' and
            guard.get('validation_core_pin') == core_pin,
            'exact completed numerical owned-guard run is unproved')
    flags = ('reaped', 'drained', 'CPU_accounting_complete',
             'preexec_kernel_boundary_proved', 'subprocess_creation_kernel_denied')
    require(all(guard.get(key) is True for key in flags), 'owned guard aborted or incomplete')
    for binding in grant['source_bindings']:
        require(digest(binding['path']) == binding['sha256'], 'frozen validation source changed')
    entry = guard.get('entrypoint_pin')
    require(entry in grant['source_bindings'] and
            Path(entry['path']).name == '525_project_projection_toy_validation.R',
            'guard did not bind the exact numerical entrypoint')
    required_flags = ('toy_default_and_import_parity_pass',
                      'checkpoint_all_factors_schedules_RNG_IO_verified',
                      'stock_AST_exactly_preserved', 'no_production_data_used',
                      'production_gate_unchanged_and_rejects_synthetic')
    require(all(core.get(key) is True for key in required_flags), 'numerical/AST/checkpoint proof incomplete')
    require(core.get('toy_optimizer_invocations') == grant.get('maximum_optimizer_invocations') == 8 and
            core.get('total_toy_optimizer_iterations') == grant.get('maximum_total_optimizer_iterations') == 30 and
            core.get('maximum_n') == grant.get('maximum_n') == 128 and
            core.get('maximum_p') == grant.get('maximum_p') == 32 and
            core.get('production_fit_invocations') == 0 and core.get('production_passflags_written') == 0,
            'toy resource/call scope changed')
    require(core.get('stock_body_sha256') == grant['expected_stock_body_sha256'], 'stock AST pin differs')
    checkpoints = core.get('checkpoints')
    require(isinstance(checkpoints, list) and [x.get('count') for x in checkpoints] == [4, 4, 1, 4],
            'exact checkpoint inventory missing')
    for group in checkpoints:
        require(str(group.get('label', '')).startswith('synthetic_NONCANDIDATE_'), 'real target checkpoint forbidden')
        require([x.get('completed_sweep') for x in group['entries']] == list(range(1, group['count'] + 1)),
                'checkpoint history not contiguous')
        for item in group['entries']:
            value = item['state_pin']
            require(Path(core_pin['path']).parent in Path(value['path']).resolve().parents and
                    digest(value['path']) == value['sha256'], 'synthetic checkpoint bytes/hash differ')
    result = dict(core, schema='r154_project_adapter_validation_v1',
                  status='PASS_SYNTHETIC_PROJECT_ADAPTER_VALIDATION_ONLY',
                  validation_core_pin=core_pin, owned_guard_receipt_pin=guard_pin,
                  native_R_ELF_seccomp_startup_pass=True,
                  actual_owned_guard_Rscript_launch_pass=False,
                  Rscript_shell_wrapper_used=False)
    destination = Path(output)
    fd = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(result, stream, indent=2, sort_keys=True, allow_nan=False)
        stream.write('\n')
    return pin(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    for name in ('core', 'root-grant', 'root-grant-sha256', 'owned-guard-receipt',
                 'owned-guard-receipt-sha256', 'output'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    print(json.dumps(finalize(pin(args.core),
          dict(path=str(Path(args.root_grant).resolve()), sha256=args.root_grant_sha256),
          dict(path=str(Path(args.owned_guard_receipt).resolve()), sha256=args.owned_guard_receipt_sha256),
          args.output), sort_keys=True))
