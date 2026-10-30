"""Temporary stdlib fixtures only: no canonical registry, SSH, arrays or jobs."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('artifact_recovery', Path(__file__).with_name('artifact_recovery.py'))
r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)

    def test_pin_changed_rejected(self):
        path = self.base / 'x.json'; r.write_new(path, {'a': 1}); pin = r.pin(path)
        path.write_text('{}')
        with self.assertRaisesRegex(ValueError, 'changed'):
            r.read(pin)

    def test_duplicate_json_keys_rejected(self):
        path = self.base / 'x.json'; path.write_text('{"a":1,"a":2}')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            r.read(r.pin(path))

    def test_write_new_never_overwrites(self):
        path = self.base / 'x.json'; r.write_new(path, {'old': True}); before = path.read_bytes()
        with self.assertRaises(FileExistsError):
            r.write_new(path, {})
        self.assertEqual(before, path.read_bytes())

    def test_symlinks_and_hardlinks_rejected(self):
        path = self.base / 'x'; path.write_bytes(b'x')
        link = self.base / 'link'; link.symlink_to(path)
        with self.assertRaisesRegex(ValueError, 'symlink'):
            r.digest(link)
        link.unlink(); os.link(path, link)
        with self.assertRaisesRegex(ValueError, 'single-link'):
            r.digest(path)

    def test_noreplace_even_empty_directory(self):
        source = self.base / 'source'; target = self.base / 'target'
        source.mkdir(); target.mkdir()
        inode = source.stat().st_ino
        with self.assertRaises(OSError):
            r.no_replace_rename(source, target)
        self.assertEqual(inode, source.stat().st_ino)

    def test_tree_rename_preserves_raw_and_inodes(self):
        source = self.base / 'source'; source.mkdir(); (source / 'x.bin').write_bytes(b'opaque raw bytes')
        before = r.tree_manifest(source); target = self.base / 'target'
        r.no_replace_rename(source, target); r.same_tree(before, r.tree_manifest(target))

    def test_journal_chain_detects_mutation(self):
        r.event(self.base, 'A'); r.event(self.base, 'B')
        (self.base / 'event_0000.json').write_text('{}')
        with self.assertRaises((ValueError, KeyError)):
            r.event(self.base, 'C')

    def test_only_exact_eligible_ids_before_any_controller_call(self):
        path = self.base / 'cfg.json'
        r.write_new(path, dict(schema='r170_completed_artifact_recovery_config_v1', scope_id='old-failed-D4'))
        with self.assertRaisesRegex(ValueError, 'only H D5/S5'):
            r.load_context(path, None)

    def test_original_publication_remote_alias_exact_hash_and_content(self):
        publication = r.write_new(self.base / 'publication.json', {'source_files': {'e.py': 'exact'}})
        grant = dict(source_publication=publication)
        profile = dict(remote_root='/owned/remote', feature_publication=dict(
            path='/owned/remote/metadata/feature_publication.json', sha256=publication['sha256']))
        controller = SimpleNamespace(spec_read=lambda spec, value: r.read(publication))
        r.original_publication(profile, grant, controller)
        profile['feature_publication']['sha256'] = '0'*64
        with self.assertRaisesRegex(ValueError, 'publication'):
            r.original_publication(profile, grant, controller)
        profile['feature_publication']['sha256'] = publication['sha256']
        controller.spec_read = lambda spec, value: {'source_files': {'e.py':'changed'}}
        with self.assertRaisesRegex(ValueError, 'publication'):
            r.original_publication(profile, grant, controller)

    def fixture(self, phase):
        canonical = self.base / 'canonical'; canonical.mkdir()
        (canonical / 'release').mkdir(); r.write_new(canonical / 'release/release_manifest.json', {})
        recovery = self.base / 'recovery'; recovery.mkdir()
        staging = recovery / 'decoded_raw'; staging.mkdir(); (staging / 'new.bin').write_bytes(b'new raw')
        (staging / 'new.bin').chmod(0o600)
        original_spec = r.write_new(self.base / 'spec.json', {})
        request = r.write_new(self.base / 'request.json', {})
        scope = r.D5 if phase == 'D' else r.S5
        ctx = dict(root=recovery, canonical=canonical, claim=dict(job_id='123'),
            spec=dict(request=request), cfg=dict(scope_id=scope, original_spec=original_spec))
        bindings = dict(spec=original_spec, request=request,
            source_manifest=r.pin(canonical / 'release/release_manifest.json'))
        wire = dict(path=str(self.base / 'unused.spool'), sha256='0'*64, bytes=100)
        spool = r.write_new(self.base / 'spool.json', dict(status='WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM',
            scope_id=scope, job_id='123', bindings=bindings, wire=wire))
        s = staging.stat()
        decoded = dict(status='PASS_OFFLINE_DECODE', schema='r165_artifact_spool_decode_receipt_v1',
            scope_id=scope, job_id='123', all_frames_verified=True, canonical_install_performed=False,
            bindings=bindings, spool_receipt=spool, wire=wire, target_root=str(staging),
            target_identity=dict(device=s.st_dev, inode=s.st_ino, uid=s.st_uid, mode=0o700),
            original_receive_receipt=dict(files=1, bytes=7), payload_bytes=7)
        manifest = dict(schema='r164_exact_file_stream_v1', kind='directory', total_bytes=7,
            files=[dict(name='new.bin', bytes=7, sha256=r.digest(staging / 'new.bin'), mode=0o600)])
        manifest_sha = hashlib.sha256(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
        decoded.update(wire_manifest=manifest, wire_manifest_sha256=manifest_sha)
        decoded['original_receive_receipt']['manifest_sha256'] = manifest_sha
        def guard(value, cpu):
            return dict(returncode=0, command_returncode=0, all_owned_descendants_reaped=True,
                kernel_escape_filter=True, independent_guardian=True, CPU_limit=cpu,
                aggregate_CPU_seconds=0.1, complete_lifecycle_wall_seconds=1, stdout=json.dumps(value))
        ctx['operational_guards'] = dict(spool=r.write_new(self.base / 'spool_guard.json', guard(r.read(spool), 40)),
            decode=r.write_new(self.base / 'decode_guard.json', guard(decoded, 20)))
        return ctx, decoded

    def old_partial(self, canonical):
        old = canonical / 'returned_raw'; old.mkdir()
        for index in range(194):
            (old / ('old_%03d' % index)).write_bytes(str(index).encode())
        (old / 'file.profile-part').write_bytes(b'partial frame')
        return r.tree_manifest(old)

    def test_D_two_renames_preserve_all195_partial_inodes(self):
        ctx, decoded = self.fixture('D'); before = self.old_partial(ctx['canonical'])
        r.install_tree(ctx, decoded)
        r.same_tree(before, r.tree_manifest(ctx['canonical'] / 'returned_raw_recovery06_preserved'))
        self.assertEqual((ctx['canonical'] / 'returned_raw/new.bin').read_bytes(), b'new raw')
        self.assertTrue((ctx['root'] / 'OLD_PARTIAL_MANIFEST.json').is_file())

    def test_interruption_between_renames_fails_closed_preserves_both(self):
        ctx, decoded = self.fixture('D'); before = self.old_partial(ctx['canonical'])
        rename = r.no_replace_rename
        count = [0]
        def fail_second(source, target):
            count[0] += 1
            if count[0] == 2:
                raise OSError('simulated interruption')
            return rename(source, target)
        with patch.object(r, 'no_replace_rename', fail_second):
            with self.assertRaises(OSError):
                r.install_tree(ctx, decoded)
        self.assertFalse((ctx['canonical'] / 'returned_raw').exists())
        self.assertTrue(Path(decoded['target_root']).is_dir())
        r.same_tree(before, r.tree_manifest(ctx['canonical'] / 'returned_raw_recovery06_preserved'))
        with self.assertRaises(FileExistsError):
            r.install_tree(ctx, decoded)

    def test_S_one_install_no_fake_failed_transfer(self):
        ctx, decoded = self.fixture('S'); r.install_tree(ctx, decoded)
        self.assertFalse((ctx['root'] / 'OLD_PARTIAL_MANIFEST.json').exists())
        self.assertTrue((ctx['canonical'] / 'returned_raw/new.bin').is_file())

    def test_S_preexisting_return_fails(self):
        ctx, decoded = self.fixture('S'); (ctx['canonical'] / 'returned_raw').mkdir()
        with self.assertRaisesRegex(ValueError, 'absent'):
            r.install_tree(ctx, decoded)

    def test_changed_decode_count_fails_before_archive(self):
        ctx, decoded = self.fixture('D'); before = self.old_partial(ctx['canonical'])
        decoded['original_receive_receipt']['files'] = 2
        with self.assertRaises(ValueError):
            r.install_tree(ctx, decoded)
        r.same_tree(before, r.tree_manifest(ctx['canonical'] / 'returned_raw'))

    def test_changed_job_or_spool_binding_fails(self):
        ctx, decoded = self.fixture('S'); decoded['job_id'] = 'foreign'
        with self.assertRaisesRegex(ValueError, 'receiver'):
            r.install_tree(ctx, decoded)

    def test_equal_size_staging_mutation_rejected_before_archive(self):
        ctx, decoded = self.fixture('D'); before = self.old_partial(ctx['canonical'])
        (Path(decoded['target_root']) / 'new.bin').write_bytes(b'bad raw')
        with self.assertRaisesRegex(ValueError, 'original hash'):
            r.install_tree(ctx, decoded)
        r.same_tree(before, r.tree_manifest(ctx['canonical'] / 'returned_raw'))

    def test_validation_never_launches_a_subprocess(self):
        source = Path(r.__file__).read_text()
        self.assertNotIn('subprocess.', source)
        self.assertNotIn('collect_run(', source)
        self.assertNotIn('c.operation(', source)

    def test_failed_external_decode_guard_blocks_all_renames(self):
        ctx, decoded = self.fixture('D'); before = self.old_partial(ctx['canonical'])
        value = r.read(ctx['operational_guards']['decode']); value['returncode'] = 124
        ctx['operational_guards']['decode'] = r.write_new(self.base / 'failed_guard.json', value)
        with self.assertRaisesRegex(ValueError, 'outer guardian'):
            r.install_tree(ctx, decoded)
        r.same_tree(before, r.tree_manifest(ctx['canonical'] / 'returned_raw'))

    def test_validator_rejects_wrong_budget_before_result_access(self):
        ctx, _ = self.fixture('S'); ctx['cfg']['authority'] = {'path':'x','sha256':'y'}
        execution = r.write_new(self.base / 'execution.json', dict(status='EXECUTED_ORIGINAL_FULL_RAW_VALIDATOR',
            recovery_authority=ctx['cfg']['authority'], validation_plan={}, CPU=4, wall=180,
            new_recovery_fees_only=True))
        r.write_new(ctx['root'] / 'VALIDATION_PLAN.json', {})
        with self.assertRaisesRegex(ValueError, 'execution receipt'):
            r.validator(ctx, execution)


if __name__ == '__main__':
    unittest.main()
