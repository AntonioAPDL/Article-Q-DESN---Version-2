"""Owned /dev/shm binary-stream adversarial tests; no SSH or science."""
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from . import profile_stream as s
from unittest.mock import patch


class StreamTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='pricefm_stream_test_',dir='/dev/shm')
        self.root=Path(self.tmp.name);self.source=self.root/'source';self.target=self.root/'target'
        self.source.mkdir();self.target.mkdir();self.binary=bytes(range(256))*513
        (self.source/'binary.bin').write_bytes(self.binary)
        (self.source/'nested').mkdir();(self.source/'nested/job.sh').write_bytes(b'#!/bin/sh\nexit 0\n')
        os.chmod(self.source/'nested/job.sh',0o700)
    def tearDown(self):self.tmp.cleanup()
    def stream(self):
        out=io.BytesIO();receipt=s.send(self.source,out.write,1024**2);return out.getvalue(),receipt
    def test_binary_nested_roundtrip_hashes_and_owner_execute_mode(self):
        raw,sent=self.stream();got=s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertEqual(got,sent);self.assertEqual((self.target/'binary.bin').read_bytes(),self.binary)
        self.assertEqual(stat.S_IMODE((self.target/'nested/job.sh').stat().st_mode),0o700)
        self.assertFalse(list(self.target.rglob('*.profile-part-*')))
    def test_file_can_be_renamed_to_exact_authority_marker(self):
        out=io.BytesIO();sent=s.send(self.source/'binary.bin',out.write,1024**2)
        target=self.target/'worker_authority.json';got=s.receive(target,io.BytesIO(out.getvalue()).read,1024**2)
        self.assertEqual(got,sent);self.assertEqual(target.read_bytes(),self.binary)
        self.assertEqual(target.stat().st_nlink,1)

    def test_atomic_publication_never_overwrites_a_racing_destination(self):
        part=self.target/'pending';final=self.target/'authority.json';part.write_bytes(b'new');final.write_bytes(b'keep')
        fd=s.directory_fd(self.target)
        try:
            with self.assertRaisesRegex(ValueError,'create-only'):s.publish_noreplace(fd,part.name,final.name)
        finally:os.close(fd)
        self.assertEqual(final.read_bytes(),b'keep');self.assertEqual(part.read_bytes(),b'new')

    def test_replaced_pending_inode_cannot_be_published(self):
        raw,_=self.stream();original=s.os.stat;changed=False
        def inspect(path,*args,**kwargs):
            nonlocal changed
            if isinstance(path,str) and '.profile-part-' in path and not changed:
                changed=True;fd=kwargs['dir_fd'];s.os.unlink(path,dir_fd=fd)
                other=s.os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600,dir_fd=fd);s.os.write(other,b'changed');s.os.close(other)
            return original(path,*args,**kwargs)
        with patch.object(s.os,'stat',side_effect=inspect),self.assertRaisesRegex(ValueError,'identity changed'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertFalse((self.target/'binary.bin').exists())

    def test_opened_destination_root_must_match_initial_inode(self):
        raw,_=self.stream();other=self.root/'other';other.mkdir();original=s.directory_fd
        def replaced(path):return original(other if Path(path)==self.target else path)
        with patch.object(s,'directory_fd',side_effect=replaced),self.assertRaisesRegex(ValueError,'root identity changed'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertFalse(list(other.iterdir()));self.assertFalse(list(self.target.iterdir()))
    def test_truncated_or_trailing_stream_never_publishes_marker(self):
        out=io.BytesIO();s.send(self.source/'binary.bin',out.write,1024**2);raw=out.getvalue()
        for variant in (raw[:5],raw[:-1],raw+b'UNEXPECTED'):
            target=self.target/('marker_'+str(len(variant))+'.json')
            with self.subTest(length=len(variant)),self.assertRaises(ValueError):s.receive(target,io.BytesIO(variant).read,1024**2)
            self.assertFalse(target.exists())
    def test_payload_or_manifest_hash_corruption_rejected(self):
        raw,_=self.stream();header_size=struct.unpack('!Q',raw[len(s.MAGIC):len(s.MAGIC)+8])[0]
        offset=len(s.MAGIC)+8+header_size;bad=bytearray(raw);bad[offset]^=1
        with self.assertRaisesRegex(ValueError,'SHA mismatch'):s.receive(self.target,io.BytesIO(bad).read,1024**2,True)
        self.assertFalse((self.target/'binary.bin').exists())
        bad=bytearray(raw);bad[-1]^=1
        with self.assertRaisesRegex(ValueError,'trailer/manifest'):s.receive(self.target,io.BytesIO(bad).read,1024**2,True)
    def forged(self,name,size=0,sha=None):
        value=dict(schema='r164_exact_file_stream_v1',kind='directory',total_bytes=size,
            files=[dict(name=name,bytes=size,sha256=sha or hashlib.sha256(b'').hexdigest(),mode=0o600)])
        h=json.dumps(value,sort_keys=True,separators=(',',':')).encode()
        return s.MAGIC+struct.pack('!Q',len(h))+h+s.END+hashlib.sha256(h).digest()
    def test_path_traversal_absolute_credentials_and_noncanonical_paths_rejected(self):
        for name in ('../escape','/absolute','a/../../escape','.ssh/key','a//b','a/./b'):
            with self.subTest(name=name),self.assertRaisesRegex(ValueError,'unsafe'):s.receive(self.target,io.BytesIO(self.forged(name)).read,1024**2,True)
    def test_symlink_source_and_destination_parent_rejected(self):
        (self.source/'link').symlink_to(self.source/'binary.bin')
        with self.assertRaisesRegex(ValueError,'symlink'):self.stream()
        (self.target/'escape').symlink_to(self.source,target_is_directory=True)
        with self.assertRaises((ValueError,OSError)):s.receive(self.target,io.BytesIO(self.forged('escape/new')).read,1024**2,True)
        self.assertFalse((self.source/'new').exists())
    def test_overwrite_and_hardlinked_source_rejected(self):
        raw,_=self.stream();(self.target/'binary.bin').write_bytes(b'keep')
        with self.assertRaisesRegex(ValueError,'create-only'):s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertEqual((self.target/'binary.bin').read_bytes(),b'keep')
        os.link(self.source/'binary.bin',self.source/'hardlink')
        with self.assertRaisesRegex(ValueError,'single-link'):self.stream()
    def test_byte_cap_and_header_cap_checked_before_payload(self):
        with self.assertRaisesRegex(ValueError,'byte cap'):s.manifest(self.source,1)
        raw,_=self.stream()
        with self.assertRaisesRegex(ValueError,'byte cap'):s.receive(self.target,io.BytesIO(raw).read,1,True)
        raw=s.MAGIC+struct.pack('!Q',s.HEADER_MAX+1)
        with self.assertRaisesRegex(ValueError,'header length'):s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
    def test_duplicate_member_or_json_key_rejected(self):
        value=dict(schema='r164_exact_file_stream_v1',kind='directory',total_bytes=0,
            files=[dict(name='a',bytes=0,sha256=hashlib.sha256(b'').hexdigest(),mode=0o600)]*2)
        with self.assertRaisesRegex(ValueError,'duplicate'):s.validate_manifest(value,1024)
        with self.assertRaisesRegex(ValueError,'duplicate'):s.decode(b'{"x":1,"x":2}')
    def test_member_depth_and_source_change_after_manifest_are_rejected(self):
        with self.assertRaisesRegex(ValueError,'unsafe'):s.safe_name('/'.join(['deep']*65+['file']))
        output=io.BytesIO();changed=False
        def write(block):
            nonlocal changed
            output.write(block)
            if not changed:
                changed=True
                with (self.source/'binary.bin').open('ab') as f:f.write(b'changed')
        with self.assertRaisesRegex(ValueError,'source changed'):s.send(self.source,write,1024**2)
    def test_live_upload_pipe_and_ack_are_binary_exact(self):
        args=[sys.executable,'-I','-B',s.__file__,'--receive','--path',str(self.target),'--directory','--max-bytes',str(1024**2)]
        p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        pipe=s.Pipes(p,5);sent=s.send(self.source,pipe.write,1024**2);p.stdin.close();ack=s.decode(pipe.finish())
        self.assertEqual(ack,sent);self.assertEqual((self.target/'binary.bin').read_bytes(),self.binary)
        p.stdout.close();p.stderr.close()
    def test_live_download_pipe_streams_without_full_payload_buffer(self):
        args=[sys.executable,'-I','-B',s.__file__,'--send','--path',str(self.source),'--max-bytes',str(1024**2)]
        p=subprocess.Popen(args,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        pipe=s.Pipes(p,5);p.stdin.close();got=s.receive(self.target,pipe.read,1024**2,True);pipe.finish()
        self.assertEqual(got['files'],2);self.assertEqual((self.target/'binary.bin').read_bytes(),self.binary)
        p.stdout.close();p.stderr.close()
    def test_no_scientific_module_imported(self):self.assertFalse({'numpy','scipy','pandas'}&set(sys.modules))


if __name__=='__main__':unittest.main()
