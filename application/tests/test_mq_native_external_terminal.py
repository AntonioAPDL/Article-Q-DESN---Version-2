#!/usr/bin/python3.11
"""Generated metadata only: no systemd queries, builds, inputs or actors."""
import copy
import csv
import hashlib
import importlib.util
import pathlib
import tempfile
import types
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[2]
LOADER = importlib.util.spec_from_file_location(
    'mqterminal_generated_test', ROOT / 'scripts/mq_native_external_terminal.py')
terminal = importlib.util.module_from_spec(LOADER)
LOADER.loader.exec_module(terminal)


def time_text(exit_code=0, user='1.20', system='0.30', elapsed='1:02.25', rss=1024):
    return ('\tUser time (seconds): ' + str(user) + '\n'
            '\tSystem time (seconds): ' + str(system) + '\n'
            '\tElapsed (wall clock) time (h:mm:ss or m:ss): ' + str(elapsed) + '\n'
            '\tMaximum resident set size (kbytes): ' + str(rss) + '\n'
            '\tExit status: ' + str(exit_code) + '\n')


def state(final=False):
    return dict(Id='qdesn-generated.service', LoadState='loaded',
                FragmentPath='/generated/qdesn-generated.service',
                ActiveState='inactive' if final else 'deactivating',
                SubState='dead' if final else 'stop-post', Result='success',
                ExecMainCode='1', ExecMainStatus='0', MainPID='0',
                ControlGroup='/user.slice/generated/qdesn-generated.service')


def generated_pin(path):
    return dict(path=str(path), size_bytes=path.stat().st_size,
                sha256=hashlib.sha256(path.read_bytes()).hexdigest())


def replay_packet():
    return dict(source_commit='a' * 40, source_tree='b' * 40,
                purpose_contract_sha256='c' * 64,
                production_authorized=False, C_ABI_qualified=False,
                training_paths=65536, parameter_refits=0, score_evaluations=0,
                observational_future_truth_used=False,
                article_promotion_authorized=False,
                production_consumer_qualified=False, numerical_status='REVIEW')


def service_fixture(actor='mq-native-build'):
    suffix = 'build' if actor == 'mq-native-build' else 'replay'
    unit = 'qdesn-native-' + suffix + '-20261103-aaaaaaaa.service'
    spec = dict(source_root='/generated/source',
                administrative_unit_name=unit,
                external_execution_gate={'sha256': 'd' * 64},
                limits=dict(logical_cpu=26 if suffix == 'build' else 27,
                            cpu_seconds=120 if suffix == 'build' else 1800,
                            wall_term_seconds=119 if suffix == 'build' else 1799,
                            address_space_bytes=2 * 1024**3,
                            output_bytes=64 * 1024**2))
    grant = dict(actor=actor, unit=unit, source_root='/generated/source',
                 purpose_sha256='c' * 64,
                 helper={'path': '/generated/source/scripts/mq_native_external_terminal.py'})
    private = '/generated/private'
    fields, environment = terminal.service_definition(spec, grant, private)
    text = '[Unit]\nDescription=Generated test only\n[Service]\n'
    text += ''.join(key + '=' + value + '\n' for key, value in fields.items())
    text += 'Environment=' + ' '.join('"' + key + '=' + value + '"'
                                        for key, value in environment.items()) + '\n'
    return spec, grant, private, text


def effective_fixture(actor='mq-native-build'):
    spec, grant, private, _ = service_fixture(actor)
    fields, environment = terminal.service_definition(spec, grant, private)
    value = state()
    value.update(Id=grant['unit'], FragmentPath='/generated/' + grant['unit'],
                 ControlGroup='/user.slice/generated/' + grant['unit'],
                 DropInPaths='', NeedDaemonReload='no')
    for key in ('WorkingDirectory', 'CPUAffinity', 'LimitCPU', 'LimitAS',
                'LimitFSIZE', 'KillMode', 'Restart'):
        value[key] = fields[key]
    for key in ('ExecStart', 'ExecStopPost'):
        value[key] = ('{ path=/usr/bin/taskset ; argv[]=' + fields[key] +
                      ' ; ignore_errors=no ; start_time=[generated] ;'
                      ' stop_time=[generated] ; pid=123 ; code=exited ; status=0 }')
    value['Environment'] = ' '.join('"' + key + '=' + item + '"'
                                     for key, item in environment.items())
    return spec, grant, private, value


class NativeTerminalGeneratedTests(unittest.TestCase):
    def test_native_time_exact_and_hour_clock(self):
        value = terminal.native_time(time_text())
        self.assertEqual(value, dict(exit_code=0, user_cpu_seconds=1.2,
                                    system_cpu_seconds=.3, wall_seconds=62.25,
                                    peak_rss_kib=1024))
        self.assertEqual(terminal.native_time(time_text(elapsed='2:03:04.50'))[
            'wall_seconds'], 7384.5)

    def test_native_time_missing_duplicate_noninteger_and_invalid_clock(self):
        valid = time_text()
        for bad in (valid.replace('User time (seconds)', 'User time'),
                    valid + '\tExit status: 0\n',
                    time_text(exit_code='0.5'), time_text(rss='1.5'),
                    time_text(user='nan'), time_text(user='-1'),
                    time_text(elapsed='0:60'), time_text(elapsed='1:60:00'),
                    time_text(elapsed='1:2:3:4'), time_text(elapsed='12'),
                    time_text(elapsed='0:nan')):
            with self.subTest(value=bad):
                with self.assertRaises(ValueError):
                    terminal.native_time(bad)

    def test_actual_stop_post_state_required(self):
        terminal.check_unit(state(), 'qdesn-generated.service',
                            '/generated/qdesn-generated.service')
        for key, value in (('Id', 'qdesn-other.service'), ('LoadState', 'not-found'),
                           ('FragmentPath', '/generated/other.service'),
                           ('MainPID', '77'), ('Result', 'timeout'),
                           ('ExecMainStatus', '124'), ('ExecMainCode', '0'),
                           ('ActiveState', 'inactive'), ('SubState', 'running'),
                           ('ControlGroup', '/generated/qdesn-generated.service')):
            bad = state(); bad[key] = value
            with self.subTest(field=key):
                with self.assertRaises(ValueError):
                    terminal.check_unit(bad, 'qdesn-generated.service',
                                        '/generated/qdesn-generated.service')

    def test_final_requires_linked_successful_actual_hook(self):
        hook = dict(successful_actual_stop_post_proof=True, unit_state=state())
        terminal.check_unit(state(True), 'qdesn-generated.service',
                            '/generated/qdesn-generated.service', True, hook)
        collected = state(True); collected.update(ExecMainCode='0', ControlGroup='')
        terminal.check_unit(collected, 'qdesn-generated.service',
                            '/generated/qdesn-generated.service', True, hook)
        for bad_hook in (None, {}, dict(hook, successful_actual_stop_post_proof=False)):
            with self.subTest(hook=bad_hook):
                with self.assertRaises(ValueError):
                    terminal.check_unit(state(True), 'qdesn-generated.service',
                                        '/generated/qdesn-generated.service', True, bad_hook)
        for key, value in (('ActiveState', 'deactivating'), ('SubState', 'stop-post'),
                           ('ControlGroup', '/user.slice/other.service'),
                           ('ExecMainCode', '2')):
            bad = state(True); bad[key] = value
            with self.subTest(field=key):
                with self.assertRaises(ValueError):
                    terminal.check_unit(bad, 'qdesn-generated.service',
                                        '/generated/qdesn-generated.service', True, hook)

    def test_generated_output_inventory_and_file_pins(self):
        with tempfile.TemporaryDirectory(prefix='mq_terminal_generated_') as directory:
            root = pathlib.Path(directory).resolve()
            a = root / 'a.txt'; a.write_text('generated only\n')
            pin = generated_pin(a)
            self.assertEqual(terminal.pin_check(pin), a)
            rows = terminal.output_inventory(root)
            self.assertEqual(rows, [dict(relative_path='a.txt', size_bytes=pin['size_bytes'],
                                         sha256=pin['sha256'])])
            for key, value in (('size_bytes', 999), ('sha256', 'f' * 64)):
                bad = dict(pin); bad[key] = value
                with self.assertRaises(ValueError): terminal.pin_check(bad)
            link = root / 'alias'; link.symlink_to(a)
            with self.assertRaises(ValueError): terminal.output_inventory(root)
            bad = dict(pin, path=str(link))
            with self.assertRaises(ValueError): terminal.pin_check(bad)
            link.unlink()
            (root / 'subdir').mkdir()
            with self.assertRaises(ValueError): terminal.output_inventory(root)

    def test_replay_manifest_membership_and_hashes(self):
        with tempfile.TemporaryDirectory(prefix='mq_terminal_generated_') as directory:
            root = pathlib.Path(directory).resolve()
            (root / 'qualification.json').write_text('{"generated": true}\n')
            generated = terminal.output_inventory(root)
            manifest = root / 'artifact_manifest.csv'
            def write(rows):
                with manifest.open('w', newline='') as stream:
                    writer = csv.DictWriter(stream, fieldnames=['relative_path', 'size_bytes', 'sha256'])
                    writer.writeheader(); writer.writerows(rows)
            write(generated)
            terminal.check_manifest(root, terminal.output_inventory(root), 'mq-native-replay')
            for changed in ([], generated * 2,
                            [dict(generated[0], relative_path='other')],
                            [dict(generated[0], size_bytes=999)],
                            [dict(generated[0], sha256='f' * 64)]):
                write(changed)
                with self.assertRaises(ValueError):
                    terminal.check_manifest(root, terminal.output_inventory(root), 'mq-native-replay')

    def test_replay_review_is_not_an_execution_failure(self):
        receipt = replay_packet()
        spec = dict(source_commit='a' * 40, source_tree='b' * 40)
        terminal.check_packet(receipt, spec, 'c' * 64, 'mq-native-replay')
        self.assertEqual(receipt['numerical_status'], 'REVIEW')
        for key, value in (('source_commit', 'd' * 40), ('source_tree', 'd' * 40),
                           ('purpose_contract_sha256', 'd' * 64),
                           ('production_authorized', True), ('C_ABI_qualified', True),
                           ('training_paths', 128), ('parameter_refits', 1),
                           ('score_evaluations', 1), ('observational_future_truth_used', True),
                           ('article_promotion_authorized', True),
                           ('production_consumer_qualified', True)):
            bad = copy.deepcopy(receipt); bad[key] = value
            with self.subTest(field=key):
                with self.assertRaises(ValueError):
                    terminal.check_packet(bad, spec, 'c' * 64, 'mq-native-replay')

    def test_retained_build_packet_pins_and_false_admission(self):
        with tempfile.TemporaryDirectory(prefix='mq_terminal_generated_') as directory:
            root = pathlib.Path(directory).resolve()
            pins = {}
            for role in ('key', 'isotonic', 'inverse'):
                path = root / (role + '.generated'); path.write_text(role)
                pins[role] = generated_pin(path)
            log = root / 'generated.log'; log.write_text('not a compiler invocation\n')
            receipt = dict(source_commit='a' * 40, source_tree='b' * 40,
                           purpose_sha256='c' * 64, production_authorized=False,
                           C_ABI_qualified=False,
                           status='RETAINED_NATIVE_BUILD_COMPLETE_NOT_NUMERICAL_QUALIFICATION',
                           numeric_replay_executed=False, dlls=pins,
                           compile_logs=[generated_pin(log)])
            spec = dict(source_commit='a' * 40, source_tree='b' * 40)
            terminal.check_packet(receipt, spec, 'c' * 64, 'mq-native-build')
            for key, value in (('status', 'BUILD_IN_PROGRESS'),
                               ('numeric_replay_executed', True),
                               ('production_authorized', True), ('dlls', {'key': pins['key']})):
                bad = copy.deepcopy(receipt); bad[key] = value
                with self.subTest(field=key):
                    with self.assertRaises(ValueError):
                        terminal.check_packet(bad, spec, 'c' * 64, 'mq-native-build')
            log.write_text('changed generated log\n')
            with self.assertRaises(ValueError):
                terminal.check_packet(receipt, spec, 'c' * 64, 'mq-native-build')

    def test_exact_prospective_build_and_replay_unit(self):
        for actor in ('mq-native-build', 'mq-native-replay'):
            spec, grant, private, text = service_fixture(actor)
            terminal.validate_unit_text(text, spec, grant, private)
            fields, environment = terminal.service_definition(spec, grant, private)
            self.assertEqual(fields['KillMode'], 'control-group')
            self.assertEqual(fields['Restart'], 'no')
            self.assertIn('/usr/bin/timeout --signal=TERM --kill-after=1s', fields['ExecStart'])
            self.assertIn('/usr/bin/python3.11 -I -S -B', fields['ExecStopPost'])
            self.assertIn('--phase stop-post --private /generated/private', fields['ExecStopPost'])
            self.assertEqual(environment['LD_PRELOAD'], '')
            if actor == 'mq-native-build':
                self.assertIn('/usr/bin/python3.11 -I -S -B scripts/build_mq_native_replay.py', fields['ExecStart'])
            else:
                self.assertIn('Rscript --vanilla scripts/qualify_mq_native_composed.R', fields['ExecStart'])
                self.assertEqual(environment['QDESN_MQ_NATIVE_PURPOSE_SHA256'], 'c' * 64)

    def test_unit_command_environment_cap_and_directive_mutations(self):
        spec, grant, private, text = service_fixture()
        edits = [('scripts/build_mq_native_replay.py', 'scripts/other.py'),
                 ('--sha256 ' + 'c' * 64, '--sha256 ' + 'd' * 64),
                 ('--phase stop-post', '--phase final'),
                 ('--cpu=120:120', '--cpu=121:121'),
                 ('--signal=TERM', '--signal=KILL'),
                 ('--kill-after=1s', '--kill-after=3s'),
                 ('CPUAffinity=26', 'CPUAffinity=27'),
                 ('LimitAS=2147483648', 'LimitAS=4294967296'),
                 ('KillMode=control-group', 'KillMode=process'),
                 ('Restart=no', 'Restart=always'),
                 ('"OMP_NUM_THREADS=1"', '"OMP_NUM_THREADS=2"'),
                 ('"LD_PRELOAD="', '"LD_PRELOAD=/generated/other.so"')]
        for old, new in edits:
            self.assertIn(old, text)
            with self.subTest(change=new):
                with self.assertRaises(ValueError):
                    terminal.validate_unit_text(text.replace(old, new), spec, grant, private)
        for extra in ('ExecStartPre=/bin/true\n', 'EnvironmentFile=/generated/env\n',
                      'Restart=no\n', 'Environment="OMP_NUM_THREADS=1"\n',
                      'Environment="UNAPPROVED=1"\n', '[Install]\nWantedBy=default.target\n'):
            with self.subTest(extra=extra):
                with self.assertRaises(ValueError):
                    terminal.validate_unit_text(text + extra, spec, grant, private)

    def test_unit_issuance_identity_rejects_unknown_actor_or_unsafe_paths(self):
        spec, grant, private, _ = service_fixture()
        for key, value in (('actor', 'mq-production'), ('unit', 'other.service'),
                           ('source_root', '/generated/source with space'),
                           ('source_root', '/generated/../other')):
            changed = copy.deepcopy(grant); changed[key] = value
            with self.subTest(field=key):
                with self.assertRaises(ValueError):
                    terminal.service_definition(spec, changed, private)
        with self.assertRaises(ValueError):
            terminal.service_definition(spec, grant, '/generated/private;other')

    def test_effective_loaded_unit_matches_both_prospective_actors(self):
        for actor in ('mq-native-build', 'mq-native-replay'):
            spec, grant, private, value = effective_fixture(actor)
            terminal.validate_effective_unit(value, spec, grant, private)
            self.assertEqual(set(value), set(terminal.FIELDS))

    def test_effective_unit_rejects_override_stale_command_environment_and_limits(self):
        spec, grant, private, value = effective_fixture()
        mutations = [('DropInPaths', '/generated/override.conf'),
                     ('NeedDaemonReload', 'yes'),
                     ('WorkingDirectory', '/generated/other'),
                     ('CPUAffinity', '27'), ('LimitCPU', '121'),
                     ('LimitAS', '4294967296'), ('LimitFSIZE', '134217728'),
                     ('KillMode', 'process'), ('Restart', 'always'),
                     ('ExecStart', value['ExecStart'].replace('scripts/build_mq_native_replay.py', 'other.py')),
                     ('ExecStopPost', value['ExecStopPost'].replace('--phase stop-post', '--phase final')),
                     ('ExecStart', value['ExecStart'] + ' ; ' + value['ExecStart']),
                     ('ExecStart', value['ExecStart'].replace('ignore_errors=no', 'ignore_errors=yes')),
                     ('ExecStart', '/usr/bin/taskset'),
                     ('Environment', value['Environment'].replace('OMP_NUM_THREADS=1', 'OMP_NUM_THREADS=2')),
                     ('Environment', value['Environment'] + ' "UNAPPROVED=1"'),
                     ('Environment', value['Environment'] + ' "OMP_NUM_THREADS=1"')]
        for key, item in mutations:
            changed = copy.deepcopy(value); changed[key] = item
            with self.subTest(field=key, value=item):
                with self.assertRaises(ValueError):
                    terminal.validate_effective_unit(changed, spec, grant, private)

    def test_systemd_property_parser_is_exact_and_fully_mocked(self):
        _, grant, _, value = effective_fixture()
        text = ''.join(key + '=' + value[key] + '\n' for key in terminal.FIELDS)
        fake = types.SimpleNamespace(returncode=0, stdout=text)
        with mock.patch.object(terminal.subprocess, 'run', return_value=fake) as call:
            self.assertEqual(terminal.unit_state(grant['unit']), value)
            argv = call.call_args.args[0]
            self.assertEqual(argv[:4], ['/usr/bin/systemctl', '--user', 'show', grant['unit']])
            self.assertEqual(argv[4:], [item for key in terminal.FIELDS for item in ('-p', key)])
        for bad in (text + 'Id=duplicate\n', text.replace('NeedDaemonReload=no\n', ''),
                    text + 'Unknown=other\n', 'malformed\n'):
            with mock.patch.object(terminal.subprocess, 'run',
                                   return_value=types.SimpleNamespace(returncode=0, stdout=bad)):
                with self.assertRaises(ValueError): terminal.unit_state(grant['unit'])
        with mock.patch.object(terminal.subprocess, 'run',
                               return_value=types.SimpleNamespace(returncode=1, stdout='')):
            with self.assertRaises(ValueError): terminal.unit_state(grant['unit'])


if __name__ == '__main__':
    unittest.main()
