"""Finite owned-byte fixtures only; no SSH or scientific payloads."""
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from pricefm_hb import profile_stream as s

_spec=importlib.util.spec_from_file_location('tested_artifact_spool',Path(__file__).with_name('artifact_spool.py'))
m=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(m)


class SpoolTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='r170-spool-owned-',dir='/dev/shm');self.root=Path(self.tmp.name)
    def tearDown(self):self.tmp.cleanup()

    def capture(self,body,limit=m.WIRE_MAX):
        # Each of the three synthetic children has a separate predeclared2CPU cap.
        code='import resource; resource.setrlimit(resource.RLIMIT_CPU,(2,2)); '+body
        p=s.fork_safe_popen([sys.executable,'-I','-B','-c',code])
        try:
            with m.create(self.root/'wire') as wire,m.create(self.root/'stderr') as err:
                result=m.capture_process(p,wire,err,time.monotonic()+5,limit)
            self.assertIsNotNone(p.poll())
            return result,(self.root/'wire').read_bytes(),(self.root/'stderr').read_bytes()
        finally:
            for f in (p.stdin,p.stdout,p.stderr):
                if not f.closed:f.close()

    def test_complete_capture_stderr_bounded(self):
        result,wire,err=self.capture("import os; os.write(1,b'wire-bytes'); os.write(2,b'e'*70000)")
        self.assertTrue(result['capture_complete']);self.assertEqual(wire,b'wire-bytes')
        self.assertEqual(result['ssh_returncode'],0);self.assertEqual(len(err),65536)
        self.assertTrue(result['stderr_truncated']);self.assertEqual(result['stderr_bytes_seen'],70000)
        self.assertEqual(result['stderr_sha256'],hashlib.sha256(err).hexdigest())

    def test_nonzero_retains_diagnostics(self):
        result,wire,err=self.capture("import os; os.write(1,b'partial'); os.write(2,b'owned failure'); raise SystemExit(7)")
        self.assertFalse(result['capture_complete']);self.assertEqual(result['ssh_returncode'],7)
        self.assertEqual(err,b'owned failure');self.assertEqual(wire,b'partial');self.assertIsNone(result['sender_returncode'])

    def test_wire_cap_failure(self):
        result,wire,err=self.capture("import os; os.write(1,b'x'*200); os.write(2,b'cap diagnostic')",limit=20)
        self.assertFalse(result['capture_complete']);self.assertLessEqual(len(wire),20)
        self.assertEqual(result['error']['message'],'wire byte cap exceeded');self.assertEqual(err,b'cap diagnostic')

    def fixture(self,mutate=None):
        source=self.root/'source';source.mkdir();(source/'tiny.bin').write_bytes(b'owned\x00fixture\xff')
        (source/'job.sh').write_bytes(b'#!/bin/sh\nexit 0\n');(source/'job.sh').chmod(0o700)
        wire=io.BytesIO();original=s.send(source,wire.write);raw=wire.getvalue()
        if mutate:raw=mutate(raw)
        directory=self.root/'capture';directory.mkdir();path=directory/'wire.spool';path.write_bytes(raw)
        before=s.regular(path)
        receipt=dict(schema='r165_artifact_spool_receipt_v1',status='WIRE_SPOOL_COMPLETE_UNVERIFIED_STREAM',
            capture_complete=True,ssh_returncode=0,scope_id='r164-profile-'+'a'*32,job_id='873499',bindings={},
            max_bytes=s.BYTE_MAX,max_stream_bytes=m.WIRE_MAX,original_stream_source_sha256=m.STREAM_SHA,
            original_supervisor_source_sha256=m.SUPERVISOR_SHA,
            wire=dict(path=str(path),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),identity=m.identity(before),fingerprint=list(s.fingerprint(before))))
        m.save(directory/'spool_receipt.json',receipt)
        return directory/'spool_receipt.json',receipt,original

    def test_offline_exact_roundtrip_manifest(self):
        path,receipt,original=self.fixture();result=m.decode(path,self.root/'decoded',self.root/'decode_receipts')
        self.assertEqual(result['status'],'PASS_OFFLINE_DECODE');self.assertTrue(result['all_frames_verified'])
        self.assertEqual(result['original_receive_receipt'],original);self.assertEqual((self.root/'decoded/tiny.bin').read_bytes(),b'owned\x00fixture\xff')
        header=json.dumps(result['wire_manifest'],sort_keys=True,separators=(',',':')).encode()
        self.assertEqual(hashlib.sha256(header).hexdigest(),result['wire_manifest_sha256'])
        self.assertGreater(result['wire_bytes'],result['payload_bytes']);self.assertFalse(result['canonical_install_performed'])

    def test_truncated_wire_zero_exit_is_not_success(self):
        path,_,_=self.fixture(lambda raw:raw[:-10]);result=m.decode(path,self.root/'decoded',self.root/'decode_receipts')
        self.assertEqual(result['status'],'FAILED_OFFLINE_DECODE');self.assertFalse(result['all_frames_verified'])
        self.assertTrue(list((self.root/'decoded').glob('.*profile-part-*')))

    def malformed(self,kind):
        def change(raw):
            length=struct.unpack('!Q',raw[8:16])[0];header=s.decode(raw[16:16+length])
            if kind=='duplicate':header['files'].append(dict(header['files'][0]))
            else:header['files'][0]['name']='../escape'
            out=json.dumps(header,sort_keys=True,separators=(',',':')).encode()
            return s.MAGIC+struct.pack('!Q',len(out))+out+raw[16+length:]
        path,_,_=self.fixture(change);result=m.decode(path,self.root/'decoded',self.root/'decode_receipts')
        self.assertEqual(result['status'],'FAILED_OFFLINE_DECODE');self.assertFalse((self.root/'escape').exists())
    def test_duplicate_manifest_rejects(self):self.malformed('duplicate')
    def test_traversal_manifest_rejects(self):self.malformed('traversal')

    def test_stale_same_size_spool_rejects(self):
        path,receipt,_=self.fixture();wire=Path(receipt['wire']['path']);raw=wire.read_bytes();wire.write_bytes(b'x'+raw[1:])
        with self.assertRaises(ValueError):m.decode(path,self.root/'decoded',self.root/'decode_receipts')

    def test_symlink_spool_rejects(self):
        path,receipt,_=self.fixture();wire=Path(receipt['wire']['path']);wire.rename(wire.with_name('moved'));wire.symlink_to('moved')
        with self.assertRaises(ValueError):m.decode(path,self.root/'decoded',self.root/'decode_receipts')

    def test_hardlink_spool_rejects(self):
        path,receipt,_=self.fixture();os.link(receipt['wire']['path'],self.root/'extra_link')
        with self.assertRaises(ValueError):m.decode(path,self.root/'decoded',self.root/'decode_receipts')

    def test_duplicate_target_preserved(self):
        path,_,_=self.fixture();target=self.root/'decoded';target.mkdir();(target/'keep').write_bytes(b'keep')
        result=m.decode(path,target,self.root/'decode_receipts');self.assertEqual(result['status'],'FAILED_OFFLINE_DECODE')
        self.assertEqual((target/'keep').read_bytes(),b'keep')

    def test_duplicate_receipt_directory_rejects(self):
        path,_,_=self.fixture();target=self.root/'receipts';target.mkdir()
        with self.assertRaises(FileExistsError):m.decode(path,self.root/'decoded',target)

    def test_exact_frozen_sender_command(self):
        supervisor=Path(s.__file__).with_name('profile_supervisor.py').read_text()
        config=dict(schema='r165_artifact_spool_task_v1',scope_id='r164-profile-'+'a'*32,job_id='873499',
            source='owned-alias:/mnt/beegfs/home/jaguir26/owned_return/',ssh_argv=['ssh','owned-alias'],
            remote_helper_source=supervisor,cpu=40,wall=120,max_bytes=s.BYTE_MAX,
            bindings={role:dict(path='/tmp/'+role+'.json',sha256='a'*64) for role in ('spec','request','source_manifest')})
        import shlex
        argv=m.sender_argv(config);remote=shlex.split(argv[-1])
        self.assertEqual(remote[:4],['/usr/bin/python3','-I','-B','-c'])
        self.assertIn('--passthrough',remote);self.assertEqual(remote[remote.index('--cpu')+1],'40')
        self.assertEqual(remote[remote.index('--wall')+1],'120');self.assertEqual(remote[-1],str(s.BYTE_MAX))
        for field,value in [('cpu',41),('wall',121),('max_bytes',10),('remote_helper_source','wrong')]:
            bad=dict(config);bad[field]=value
            with self.assertRaises(ValueError):m.sender_argv(bad)

    def test_original_singlethread_gate_unchanged(self):
        with patch.object(s.os,'listdir',return_value=[str(os.getpid()),'999']),patch.object(s.subprocess,'Popen') as launch:
            with self.assertRaises(ValueError):s.fork_safe_popen(['never-executed'])
            launch.assert_not_called()

    def test_canonical_registry_target_prohibited(self):
        with self.assertRaises(ValueError):m.new_directory('/tmp/hb_control_registry/never')


if __name__=='__main__':unittest.main()
