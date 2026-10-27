#!/usr/bin/env python3
"""Synthetic JSON/byte-file finalizer tests; no R, optimizer or arrays."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('projection_finalize',
    Path(__file__).with_name('525_finalize_projection_validation.py'))
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


class Finalize(unittest.TestCase):
    def fixture(self, root):
        root.mkdir()
        def write(name, value):
            path = root / name; path.write_text(json.dumps(value)); return module.pin(path)
        source = dict(kind='R154_project_fullstate_consumer_pinned_CRAN111', branch='fixture', head='a' * 40)
        runtime = write('runtime.json', {'fixture': 'no execution'})
        entry = root / '525_project_projection_toy_validation.R'; entry.write_text('# synthetic source fixture\n')
        grant = dict(status='ROOT_ADMITTED_PROJECT_PROJECTION_TOY_ONLY', source=source,
            authorizes_toy_optimizer=True, authorizes_production_fits=False,
            authorizes_production_acceptance=False, actual_R_runtime_binding=runtime,
            maximum_optimizer_invocations=8, maximum_total_optimizer_iterations=30,
            maximum_n=128, maximum_p=32, expected_stock_body_sha256='b' * 64,
            source_bindings=[module.pin(entry)])
        grant_pin = write('grant.json', grant)
        checkpoints = []
        for group, count in enumerate((4, 4, 1, 4)):
            entries = []
            for sweep in range(1, count + 1):
                path = root / ('synthetic_%d_%d.rds' % (group, sweep)); path.write_bytes(b'not real RDS')
                entries.append(dict(completed_sweep=sweep, state_pin=module.pin(path)))
            checkpoints.append(dict(label='synthetic_NONCANDIDATE_%d' % group, count=count, entries=entries))
        core = dict(schema='r154_project_adapter_validation_core_v1',
            status='NUMERICAL_PASS_AWAIT_OWNED_GUARD_REAP_PROOF', root_grant_pin=grant_pin,
            source=source, actual_R_runtime_binding=runtime, toy_default_and_import_parity_pass=True,
            checkpoint_all_factors_schedules_RNG_IO_verified=True, stock_AST_exactly_preserved=True,
            no_production_data_used=True, production_gate_unchanged_and_rejects_synthetic=True,
            toy_optimizer_invocations=8, total_toy_optimizer_iterations=30, maximum_n=128, maximum_p=32,
            production_fit_invocations=0, production_passflags_written=0,
            stock_body_sha256='b' * 64, checkpoints=checkpoints)
        core_pin = write('validation_core.json', core)
        guard = dict(schema='r154_owned_stage_guard_receipt_v1', status='EXITED', returncode=0,
            source=source, root_grant_sha256=grant_pin['sha256'], actual_R_runtime_binding=runtime,
            launcher='pinned_native_ELF_no_Rscript_shell_wrapper',
            validation_kind='synthetic_project_projection_only', validation_core_pin=core_pin,
            entrypoint_pin=module.pin(entry), reaped=True, drained=True, CPU_accounting_complete=True,
            preexec_kernel_boundary_proved=True, subprocess_creation_kernel_denied=True)
        guard_pin = write('guard.json', guard)
        return core_pin, grant_pin, guard_pin, guard

    def test_exact_two_phase_metadata_finalize_and_exclusive_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / 'case'; core, grant, guard, _ = self.fixture(root)
            before = Path(core['path']).read_bytes()
            result = module.finalize(core, grant, guard, root / 'validation.json')
            proof = module.read(result)
            self.assertTrue(proof['native_R_ELF_seccomp_startup_pass'])
            self.assertFalse(proof['actual_owned_guard_Rscript_launch_pass'])
            self.assertEqual(Path(core['path']).read_bytes(), before)
            with self.assertRaises(FileExistsError): module.finalize(core, grant, guard, root / 'validation.json')

    def test_failed_guard_runtime_source_or_core_never_produces_proof(self):
        changes = [(key, False) for key in ('reaped', 'drained', 'CPU_accounting_complete',
            'preexec_kernel_boundary_proved', 'subprocess_creation_kernel_denied')]
        changes += [('status', 'ABORTED'), ('returncode', -9), ('launcher', 'Rscript_shell_wrapper'),
            ('validation_kind', 'startup_only'), ('actual_R_runtime_binding', {'path': '/wrong', 'sha256': '0' * 64}),
            ('source', {'head': 'wrong'}), ('validation_core_pin', {'path': '/wrong', 'sha256': '0' * 64})]
        with tempfile.TemporaryDirectory() as tmp:
            for i, (key, changed) in enumerate(changes):
                with self.subTest(field=key):
                    root = Path(tmp) / str(i); core, grant, guard_pin, guard = self.fixture(root)
                    guard[key] = changed; Path(guard_pin['path']).write_text(json.dumps(guard))
                    with self.assertRaises(ValueError):
                        module.finalize(core, grant, module.pin(guard_pin['path']), root / 'validation.json')
                    self.assertFalse((root / 'validation.json').exists())


if __name__ == '__main__': unittest.main(verbosity=2)
