"""Private process-limit regressions; no scheduler or numerical package calls."""
import json
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import unittest
from unittest import mock

from . import activation as a, lifecycle as l

PY = '/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python'
MiB = 1024 ** 2


class ComputeAttestationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.resources = dict(cpus=1, memory_MiB=4096, cpu_seconds=120, wall_seconds=120)
        self.authority = dict(purpose='CONTROL_TEST', resources=self.resources)

    def fake_limits(self, cpu=(120, resource.RLIM_INFINITY), memory=(512 * MiB, resource.RLIM_INFINITY)):
        actual = {resource.RLIMIT_CPU: cpu, resource.RLIMIT_AS: memory}
        setter = mock.Mock(side_effect=lambda kind, value: actual.__setitem__(kind, value))
        return actual, setter

    def test_infinite_hard_limits_are_clamped_to_authoritative_declared_allocation(self):
        actual, setter = self.fake_limits()
        evidence = self.root / 'limits.json'
        def apply_after_raw(kind, value):
            raw = json.loads((self.root / 'limits-before.json').read_text())
            self.assertEqual(raw['before'], dict(CPU=[120, resource.RLIM_INFINITY], AS=[512 * MiB, resource.RLIM_INFINITY]))
            actual[kind] = value
        setter.side_effect = apply_after_raw
        l.establish_compute_limits(self.resources, self.authority, evidence_path=evidence,
            getter=actual.__getitem__, setter=setter)
        observed = json.loads(evidence.read_text())
        self.assertEqual(observed['before'], dict(CPU=[120, resource.RLIM_INFINITY], AS=[512 * MiB, resource.RLIM_INFINITY]))
        self.assertEqual(observed['after'], dict(CPU=[120, 120], AS=[4096 * MiB, 4096 * MiB]))
        self.assertEqual(actual[resource.RLIMIT_CPU], (120, 120))
        self.assertEqual(actual[resource.RLIMIT_AS], (4096 * MiB, 4096 * MiB))
        setter.assert_has_calls([mock.call(resource.RLIMIT_CPU, (120, 120)),
            mock.call(resource.RLIMIT_AS, (4096 * MiB, 4096 * MiB))], any_order=True)

    def child(self, mode):
        evidence = self.root / (mode + '.json')
        script = '''import json,resource,sys
from pathlib import Path
from pricefm_hb import activation as a,lifecycle as l
resources=dict(cpus=1,memory_MiB=4096,cpu_seconds=120,wall_seconds=120)
cpu_hard=resource.getrlimit(resource.RLIMIT_CPU)[1]
as_hard=resource.getrlimit(resource.RLIMIT_AS)[1]
resource.setrlimit(resource.RLIMIT_CPU,(120,cpu_hard))
resource.setrlimit(resource.RLIMIT_AS,(512*1024**2,512*1024**2 if sys.argv[2]=='low-hard' else as_hard))
try:
 l.establish_compute_limits(resources,dict(purpose='CONTROL_TEST',resources=resources),evidence_path=Path(sys.argv[1]))
except a.ActivationError as exc:
 print(json.dumps(dict(outcome='REJECTED',error=str(exc),numerical=[x for x in ('numpy','scipy','pandas') if x in sys.modules])))
else:
 print(json.dumps(dict(outcome='ESTABLISHED',CPU=resource.getrlimit(resource.RLIMIT_CPU),AS=resource.getrlimit(resource.RLIMIT_AS),numerical=[x for x in ('numpy','scipy','pandas') if x in sys.modules])))
'''
        result = subprocess.run([PY, '-B', '-c', script, str(evidence), mode], text=True,
            capture_output=True, timeout=10,
            env=dict(os.environ, PYTHONPATH=str(Path(__file__).resolve().parents[1])))
        self.assertEqual(result.returncode, 0, result.stderr)
        observed = json.loads(evidence.read_text())
        raw = json.loads(evidence.with_name(evidence.stem + '-before.json').read_text())
        self.assertEqual(raw['before'], observed['before'])
        return json.loads(result.stdout), observed

    def test_private_child_normalizes_inherited_soft_limits_before_numerical_imports(self):
        result, evidence = self.child('soft-only')
        self.assertEqual(result['outcome'], 'ESTABLISHED')
        self.assertEqual(result['CPU'], [120, 120])
        self.assertEqual(result['AS'], [4096 * MiB, 4096 * MiB])
        self.assertEqual(evidence['before']['CPU'][0], 120)
        self.assertEqual(evidence['before']['AS'][0], 512 * MiB)
        self.assertEqual(evidence['after'], dict(CPU=[120, 120], AS=[4096 * MiB, 4096 * MiB]))
        self.assertEqual(result['numerical'], [])

    def test_private_child_low_hard_limit_rejects_and_retains_actual_before_after(self):
        result, evidence = self.child('low-hard')
        self.assertEqual(result['outcome'], 'REJECTED')
        self.assertEqual(evidence['before']['AS'], [512 * MiB, 512 * MiB])
        self.assertEqual(evidence['after']['AS'], [512 * MiB, 512 * MiB])
        self.assertIn(str(512 * MiB), result['error'])
        self.assertEqual(result['numerical'], [])

    def test_authority_resource_mismatch_and_purpose_cap_reject_before_changing_limits(self):
        for resources, authority in (
            (self.resources, dict(self.authority, resources=dict(self.resources, cpu_seconds=121))),
            (dict(self.resources, cpu_seconds=121, wall_seconds=121),
                dict(self.authority, resources=dict(self.resources, cpu_seconds=121, wall_seconds=121))),
        ):
            with self.subTest(resources=resources, authority=authority):
                actual, setter = self.fake_limits()
                evidence = self.root / ('authority-' + str(resources['cpu_seconds']) + '.json')
                with self.assertRaises(a.ActivationError):
                    l.establish_compute_limits(resources, authority, evidence_path=evidence,
                        getter=actual.__getitem__, setter=setter)
                setter.assert_not_called()
                observed = json.loads(evidence.read_text())
                self.assertEqual(observed['before']['AS'], [512 * MiB, resource.RLIM_INFINITY])
                self.assertEqual(observed['after'], observed['before'])

    def test_kernel_limit_disagreement_rejects_with_actual_tuples_retained(self):
        actual, _ = self.fake_limits()
        setter = mock.Mock()
        evidence = self.root / 'kernel-disagrees.json'
        with self.assertRaises(a.ActivationError):
            l.establish_compute_limits(self.resources, self.authority, evidence_path=evidence,
                getter=actual.__getitem__, setter=setter)
        observed = json.loads(evidence.read_text())
        self.assertEqual(observed['after'], observed['before'])
        self.assertEqual(observed['after']['AS'], [512 * MiB, resource.RLIM_INFINITY])


if __name__ == '__main__':
    unittest.main()
