"""Private test of the actual stock run_benchmark pre-numerical prefix.

Only metadata/runtime gates are replaced. The function's real unconditional
authority['role'] execution-identity construction and write remain unchanged.
No stock module is imported and no canonical metadata or arrays are read.
"""
import ast
import copy
import hashlib
import json
import os
from pathlib import Path
import resource
import signal
import sys
import tempfile
import time
import types
import unittest

HERE = Path(__file__).resolve().parent
BENCHMARK_SOURCE = HERE.parent / 'pricefm_hb/benchmark.py'
BENCHMARK_SOURCE_SHA256 = 'a39128481f7959795fd41f68e5f627d311bd57fbf3e9a79c3caae9602a0f74ab'


def actual_prefix():
    """Retain stock statements through identity write, ending before load_staged."""
    source = BENCHMARK_SOURCE.read_text()
    if hashlib.sha256(source.encode()).hexdigest() != BENCHMARK_SOURCE_SHA256:
        raise AssertionError('qualified benchmark source changed')
    tree = ast.parse(source)
    original = next(node for node in tree.body
                    if isinstance(node, ast.FunctionDef) and node.name == 'run_benchmark')
    cuts = [index for index, node in enumerate(original.body)
            if isinstance(node, ast.Try) and any(
                isinstance(child, ast.Call) and isinstance(child.func, ast.Name)
                and child.func.id == 'load_staged' for child in ast.walk(node))]
    if len(cuts) != 1:
        raise AssertionError('unique stock pre-load_staged boundary changed')
    prefix = copy.deepcopy(original)
    prefix.body = prefix.body[:cuts[0]]
    if not (isinstance(prefix.body[-1], ast.Expr)
            and isinstance(prefix.body[-1].value, ast.Call)
            and isinstance(prefix.body[-1].value.func, ast.Name)
            and prefix.body[-1].value.func.id == 'write_json'):
        raise AssertionError('stock execution-identity write boundary changed')
    # This return exposes the constructed identity; every earlier stock AST
    # statement, including authority['role'], is byte-for-byte AST identical.
    prefix.body.append(ast.Return(value=ast.Name(id='identity', ctx=ast.Load())))
    return source, original, prefix


class RolePrefixTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.events = []
        self.allocation = dict(job_id='987654', node='node-13', cpus_per_task=1,
                               affinity=[0])
        self.plan_path = self.root / 'private-plan.json'
        self.authority_path = self.root / 'private-authority.json'
        self.plan_sha = 'c' * 64
        self.authority_sha = 'd' * 64
        self.source, self.original, self.prefix = actual_prefix()

    def make_function(self, study, authority):
        plan = dict(study=study,
                    adapter_feasibility=dict(adapter_sources={}),
                    canonical_preparation=dict(source={'head': 'private-source'},
                                               sha256='b' * 64),
                    claim=dict(planned_attempt_id='private-' + study,
                               scientific_exclusion_key=study + '|private-intent'))
        self.plan_path.write_text(json.dumps(plan))
        self.authority_path.write_text(json.dumps(authority))

        def metadata(path):
            self.events.append('metadata:' + Path(path).name)
            if Path(path) == self.plan_path:
                return copy.deepcopy(plan)
            if Path(path) == self.authority_path:
                return copy.deepcopy(authority)
            raise AssertionError('unexpected metadata input')

        def digest(path):
            self.events.append('digest:' + Path(path).name)
            if Path(path) == self.authority_path:
                return self.authority_sha
            if Path(path) == self.plan_path:
                return self.plan_sha
            raise AssertionError('unexpected source or array hash')

        def validate(value, actual_plan, actual_sha, allocation):
            self.events.append('validated-metadata-gates')
            self.assertEqual(actual_plan, plan)
            self.assertEqual(actual_sha, self.plan_sha)
            self.assertEqual(allocation, self.allocation)
            # The stock r157 branch validates these identities but never reads
            # role before returning. Preserve that property so the real stock
            # identity construction is the operation that reveals the bug.
            if (value.get('purpose') != 'COST_ONLY' or value.get('study') != study
                    or value.get('scope_id') != plan['claim']['planned_attempt_id']
                    or value.get('scientific_exclusion_key') != plan['claim']['scientific_exclusion_key']):
                raise ValueError('private metadata scope mismatch')
            return {'parity_runtime': {'private_verified_runtime': True}}

        def write_json(path, value):
            self.events.append('write-execution-identity')
            Path(path).write_text(json.dumps(value))

        class Budget:
            def __init__(self, value):
                self.value = value

            def check(self):
                return None

        thread_env = {'OMP_NUM_THREADS': '1'}
        reference_env = {'PRIVATE_REFERENCE_PROFILE': 'unchanged'}
        namespace = dict(Path=Path, __file__=str(BENCHMARK_SOURCE),
                         os=types.SimpleNamespace(environ=dict(thread_env, **reference_env)),
                         THREAD_ENV=thread_env, REFERENCE_NUMERICAL_ENV=reference_env,
                         require_compute=lambda: copy.deepcopy(self.allocation),
                         planning=types.SimpleNamespace(dry_run=lambda p: self.events.append('dry-run'),
                                                        read_metadata=metadata),
                         digest=digest, validate_authority=validate,
                         validate_actual_runtime=lambda value: self.events.append('runtime-validated'),
                         Budget=Budget, install_hard_limits=lambda budget: self.events.append('limits-installed'),
                         write_json=write_json, BenchmarkError=RuntimeError,
                         WORKER_IMPORT_EPOCH=1234567800.0)
        module = ast.fix_missing_locations(ast.Module(body=[copy.deepcopy(self.prefix)], type_ignores=[]))
        exec(compile(module, str(BENCHMARK_SOURCE) + ':actual-pre-numerical-prefix', 'exec'), namespace)
        return namespace['run_benchmark']

    @staticmethod
    def authority(study, role=None):
        value = dict(schema='r157_hb_execution_authority_v1', purpose='COST_ONLY',
                     study=study, scope_id='private-' + study,
                     scientific_exclusion_key=study + '|private-intent',
                     expires_epoch=1234567890)
        if role is not None:
            value['role'] = role
        return value

    def run_prefix(self, study, authority, suffix):
        function = self.make_function(study, authority)
        output = self.root / suffix / 'BENCHMARK_TEST' / authority['scope_id']
        return function(self.plan_path, self.authority_path, self.authority_sha,
                        self.root / 'unopened-stage', output), output

    def test_stock_missing_role_fails_at_actual_identity_construction_before_numeric_code(self):
        for study in ('FI', 'DK2'):
            with self.subTest(study=study):
                self.events = []
                with self.assertRaisesRegex(KeyError, 'role'):
                    self.run_prefix(study, self.authority(study), 'missing-' + study)
                self.assertIn('limits-installed', self.events)
                self.assertNotIn('write-execution-identity', self.events)

    def test_exact_FI_and_DK2_roles_pass_the_actual_execution_identity_write(self):
        for study in ('FI', 'DK2'):
            with self.subTest(study=study):
                self.events = []
                role = study + '_COST_ONLY_BENCHMARK'
                identity, output = self.run_prefix(study, self.authority(study, role),
                                                   'correct-' + study)
                self.assertEqual(identity['role'], role)
                self.assertEqual(identity['study'], study)
                self.assertEqual(identity['allocation'], self.allocation)
                self.assertEqual(identity['plan_sha256'], self.plan_sha)
                self.assertEqual(json.loads((output / 'execution_identity.json').read_text()), identity)
                self.assertEqual(self.events[-1], 'write-execution-identity')

    def test_only_a_return_is_added_and_no_numerical_or_staging_prefix_is_executed(self):
        for index, node in enumerate(self.prefix.body[:-1]):
            self.assertEqual(ast.dump(node, include_attributes=False),
                             ast.dump(self.original.body[index], include_attributes=False))
        self.assertIsInstance(self.prefix.body[-1], ast.Return)
        calls = [node.func.id for node in ast.walk(self.prefix)
                 if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)]
        self.assertNotIn('load_staged', calls)
        self.assertFalse(any(isinstance(node, (ast.Import, ast.ImportFrom)) for node in ast.walk(self.prefix)))
        role_reads = [node for node in ast.walk(self.prefix)
                      if isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name)
                      and node.value.id == 'authority' and isinstance(node.slice, ast.Constant)
                      and node.slice.value == 'role']
        self.assertEqual(len(role_reads), 1)

    def test_actual_r157_validation_branch_returns_before_any_role_guard(self):
        tree = ast.parse(self.source)
        validator = next(node for node in tree.body
                         if isinstance(node, ast.FunctionDef) and node.name == 'validate_authority')
        branch = next(node for node in validator.body if isinstance(node, ast.If))
        self.assertIn('r157_hb_execution_authority_v1', ast.unparse(branch.test))
        role_constants = [node for node in ast.walk(branch)
                          if isinstance(node, ast.Constant) and node.value == 'role']
        self.assertEqual(role_constants, [])
        self.assertTrue(any(isinstance(node, ast.Return) for node in branch.body))

    def test_wrong_scope_is_stopped_before_the_identity_write(self):
        authority = self.authority('FI', 'FI_COST_ONLY_BENCHMARK')
        authority['scientific_exclusion_key'] = 'DK2|wrong-intent'
        with self.assertRaisesRegex(ValueError, 'scope mismatch'):
            self.run_prefix('FI', authority, 'wrong-scope')
        self.assertNotIn('write-execution-identity', self.events)


if __name__ == '__main__':
    assert os.sched_getaffinity(0) == {31}
    resource.setrlimit(resource.RLIMIT_CPU, (5, 5))
    signal.alarm(30)
    began = time.monotonic()
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(RolePrefixTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    own = resource.getrusage(resource.RUSAGE_SELF)
    children = resource.getrusage(resource.RUSAGE_CHILDREN)
    print(json.dumps(dict(tests=result.testsRun, failures=len(result.failures), errors=len(result.errors),
        successful=result.wasSuccessful(), CPU_seconds=own.ru_utime + own.ru_stime + children.ru_utime + children.ru_stime,
        wall_seconds=time.monotonic() - began, numerical_modules=[name for name in ('numpy', 'pandas', 'scipy') if name in sys.modules],
        source_path=str(BENCHMARK_SOURCE), source_sha256=hashlib.sha256(BENCHMARK_SOURCE.read_bytes()).hexdigest(),
        SSH_calls=0, canonical_writes=0, array_reads=0), sort_keys=True))
    raise SystemExit(0 if result.wasSuccessful() else 1)
