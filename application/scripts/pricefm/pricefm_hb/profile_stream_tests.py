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
import time
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
            with self.assertRaisesRegex(ValueError,'create-only'):
                s.publish_noreplace(fd,part.name,final.name,s.fingerprint(part.stat()))
        finally:os.close(fd)
        self.assertEqual(final.read_bytes(),b'keep');self.assertEqual(part.read_bytes(),b'new')

    def test_hardlink_commit_exposes_two_links_until_cleanup_then_single_link_ack(self):
        out=io.BytesIO();sent=s.send(self.source/'binary.bin',out.write,1024**2)
        final=self.target/'worker_authority.json';original=s.os.unlink;observed=[]
        def unlink(path,*args,**kwargs):
            if isinstance(path,str) and '.profile-part-' in path:
                part=os.stat(path,dir_fd=kwargs['dir_fd'],follow_symlinks=False)
                current=final.lstat();observed.append((part.st_ino,current.st_ino,current.st_nlink))
                self.assertEqual(part.st_ino,current.st_ino);self.assertEqual(current.st_nlink,2)
            return original(path,*args,**kwargs)
        with patch.object(s.os,'unlink',side_effect=unlink):
            got=s.receive(final,io.BytesIO(out.getvalue()).read,1024**2)
        self.assertEqual(got,sent);self.assertEqual(len(observed),1)
        self.assertEqual(final.stat().st_nlink,1)

    def test_crash_before_unlink_retains_two_links_and_no_ack(self):
        out=io.BytesIO();s.send(self.source/'binary.bin',out.write,1024**2)
        final=self.target/'worker_authority.json';original=s.os.unlink
        def fail(path,*args,**kwargs):
            if isinstance(path,str) and '.profile-part-' in path:raise OSError('fixture interrupted before cleanup')
            return original(path,*args,**kwargs)
        with patch.object(s.os,'unlink',side_effect=fail),self.assertRaisesRegex(OSError,'interrupted'):
            s.receive(final,io.BytesIO(out.getvalue()).read,1024**2)
        self.assertEqual(final.stat().st_nlink,2);self.assertEqual(final.read_bytes(),self.binary)
        self.assertEqual(len(list(self.target.glob('*.profile-part-*'))),1)

    def test_replaced_part_after_open_is_detected_before_unlink(self):
        raw,_=self.stream();original=s.os.link;changed=False
        def link(part,final,*args,**kwargs):
            nonlocal changed
            if not changed:
                changed=True;fd=kwargs['src_dir_fd'];os.unlink(part,dir_fd=fd)
                other=os.open(part,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600,dir_fd=fd)
                os.write(other,b'wrong inode');os.close(other)
            return original(part,final,*args,**kwargs)
        with patch.object(s.os,'link',side_effect=link),self.assertRaisesRegex(ValueError,'linked publication identity'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertEqual((self.target/'binary.bin').stat().st_nlink,2)

    def test_unexpected_third_link_is_not_cleaned_or_acknowledged(self):
        raw,_=self.stream();original=s.os.link;extra=self.target/'unexpected_alias'
        def link(part,final,*args,**kwargs):
            result=original(part,final,*args,**kwargs)
            original(part,extra,src_dir_fd=kwargs['src_dir_fd'],follow_symlinks=False)
            return result
        with patch.object(s.os,'link',side_effect=link),self.assertRaisesRegex(ValueError,'link count changed'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertEqual(extra.stat().st_nlink,3)

    def test_changed_mode_during_link_fails_before_cleanup(self):
        raw,_=self.stream();original=s.os.link
        def link(part,final,*args,**kwargs):
            result=original(part,final,*args,**kwargs)
            os.chmod(final,0o400,dir_fd=kwargs['dst_dir_fd']);return result
        with patch.object(s.os,'link',side_effect=link),self.assertRaisesRegex(ValueError,'linked publication identity'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)
        self.assertEqual((self.target/'binary.bin').stat().st_nlink,2)

    def test_destination_symlink_never_overwritten(self):
        part=self.target/'pending';part.write_bytes(b'new')
        untouched=self.target/'untouched';untouched.write_bytes(b'keep')
        final=self.target/'authority.json';final.symlink_to(untouched)
        fd=s.directory_fd(self.target)
        try:
            with self.assertRaisesRegex(ValueError,'create-only'):
                s.publish_noreplace(fd,part.name,final.name,s.fingerprint(part.stat()))
        finally:os.close(fd)
        self.assertTrue(final.is_symlink());self.assertEqual(untouched.read_bytes(),b'keep')

    def test_directory_fsync_failure_never_returns_ack(self):
        raw,_=self.stream();original=s.os.fsync
        def sync(fd):
            if stat.S_ISDIR(os.fstat(fd).st_mode):raise OSError('fixture directory fsync failure')
            return original(fd)
        with patch.object(s.os,'fsync',side_effect=sync),self.assertRaisesRegex(OSError,'directory fsync'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)

    def test_replaced_final_after_unlink_cannot_be_acknowledged(self):
        raw,_=self.stream();original=s.os.unlink;changed=False
        def unlink(part,*args,**kwargs):
            nonlocal changed
            result=original(part,*args,**kwargs)
            if isinstance(part,str) and '.profile-part-' in part and not changed:
                changed=True;final=self.target/'binary.bin';original(final);final.write_bytes(b'substituted')
            return result
        with patch.object(s.os,'unlink',side_effect=unlink),self.assertRaisesRegex(ValueError,'linked publication identity'):
            s.receive(self.target,io.BytesIO(raw).read,1024**2,True)

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


class ForkSafeLaunchTests(unittest.TestCase):
    def test_public_preexec_callback_and_pipes_are_used(self):
        with patch.object(s.os,'listdir',return_value=[str(os.getpid())]), patch.object(s.subprocess,'Popen') as launch:
            self.assertIs(s.fork_safe_popen(['owned-command']),launch.return_value)
        launch.assert_called_once_with(['owned-command'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                       stderr=subprocess.PIPE,preexec_fn=s._fork_only_child)

    def test_extra_or_nonmain_kernel_threads_fail_before_fork(self):
        for tasks in ([],[str(os.getpid()),'12345'],['12345']):
            with patch.object(s.os,'listdir',return_value=tasks), patch.object(s.subprocess,'Popen') as launch:
                with self.assertRaisesRegex(ValueError,'exactly the main kernel thread'):s.fork_safe_popen(['owned-command'])
                launch.assert_not_called()

    def test_delayed_preexec_parent_is_interruptible_and_strict_group_stops(self):
        """An observation wrapper records only successful original stop proofs."""
        from . import profile_supervisor as guard
        with tempfile.TemporaryDirectory(prefix='pricefm_fork_preexec_',dir='/dev/shm') as tmp:
            root=Path(tmp);marker=root/'callback.json';trace=root/'actual_stopped.json'
            package=str(Path(s.__file__).resolve().parent.parent)
            payload=("import sys,os,time,json;from pathlib import Path\n"
                f"sys.path.insert(0,{package!r})\nfrom pricefm_hb import profile_stream as s\n"
                "def record(pid):\n"
                "    f=(Path('/proc')/str(pid)/'stat').read_text().rsplit(')',1)[1].split()\n"
                "    return dict(pid=pid,state=f[0],birth=int(f[19]),uid=(Path('/proc')/str(pid)).stat().st_uid)\n"
                "def delayed():\n"
                "    time.sleep(.03)\n"
                f"    Path({str(marker)!r}).write_text(json.dumps(dict(parent=record(os.getppid()),child=record(os.getpid()))))\n"
                "    time.sleep(.45)\n"
                "s._fork_only_child=delayed\n"
                "p=s.fork_safe_popen([sys.executable,'-I','-B','-c',\"print('owned fork-only exec')\"])\n"
                "out,err=p.communicate(timeout=2);assert p.returncode==0 and out==b'owned fork-only exec\\n' and not err\n"
                "print('owned delayed preexec complete')\n")
            launcher=("import sys,json;from pathlib import Path;from types import SimpleNamespace\n"
                f"sys.path.insert(0,{package!r})\nfrom pricefm_hb import profile_supervisor as g\n"
                "original=g.await_owned_stop\n"
                "def observed(records,**kw):\n"
                "    items,waited=original(records,**kw)\n"
                f"    marker=Path({str(marker)!r});trace=Path({str(trace)!r})\n"
                "    if marker.exists() and not trace.exists():\n"
                "        try:info=json.loads(marker.read_text())\n"
                "        except (OSError,ValueError):info=None\n"
                "        if info is not None:\n"
                "            found={x['pid']:x for x in items}\n"
                "            pair=[info['parent'],info['child']]\n"
                "            if all(x['pid'] in found and found[x['pid']]['start_ticks']==x['birth'] and found[x['pid']]['uid']==x['uid'] for x in pair):\n"
                "                trace.write_text(json.dumps(dict(callback=info,actual_original_stop_items=items,observability_only=True)))\n"
                "    return items,waited\n"
                "g.await_owned_stop=observed\n"
                f"code=g.guarded_run([sys.executable,'-I','-B','-c',{payload!r}],SimpleNamespace(cpu=5,wall=8,output_cap=65536,passthrough=False))\n"
                "sys.exit(code)\n")
            started=time.monotonic()
            result=subprocess.run([sys.executable,'-I','-B','-c',launcher],capture_output=True,timeout=12,
                                  preexec_fn=s._fork_only_child)
            destination=os.environ.get('PRICEFM_FORK_TEST_ARTIFACTS')
            if destination:
                path=Path(destination);path.mkdir(parents=True,exist_ok=True)
                (path/(self._testMethodName+'.stdout')).write_bytes(result.stdout)
                (path/(self._testMethodName+'.stderr')).write_bytes(result.stderr)
                if trace.exists():(path/(self._testMethodName+'.trace.json')).write_bytes(trace.read_bytes())
            receipt=json.loads(result.stdout) if result.stdout else None
            actual=json.loads(trace.read_text()) if trace.exists() else None
            proof=dict(returncode=result.returncode,stdout=result.stdout.decode(errors='replace'),
                       stderr=result.stderr.decode(errors='replace'),guardian_receipt=receipt,
                       actual_stopped_observation=actual,wall_seconds=time.monotonic()-started,
                       instrumented_observation_only_not_original_incident_causal_proof=True)
            if destination:
                (path/(self._testMethodName+'.json')).write_text(json.dumps(proof,indent=2,sort_keys=True)+'\n')
            self.assertEqual(result.returncode,0,proof);self.assertIsNotNone(actual,proof)
            self.assertEqual(actual['callback']['parent']['state'],'S',proof)
            pair={actual['callback'][key]['pid'] for key in ('parent','child')}
            stopped=[x for x in actual['actual_original_stop_items'] if x['pid'] in pair]
            self.assertEqual(len(stopped),2,proof);self.assertTrue(all(x['state']=='T' for x in stopped),proof)
            self.assertTrue(receipt['all_owned_descendants_reaped'],proof)
            self.assertGreater(receipt['proved_stopped_snapshots'],1,proof)
            self.assertLess(receipt['aggregate_CPU_seconds'],5,proof)


if __name__=='__main__':unittest.main()
