"""One-shot blind SHA256 of the exact separately authorized15 existing inputs.

No deserialization, copies, numerical values, network, Slurm, R or numpy.
"""
import argparse,hashlib,importlib.util,json,os,resource,signal,stat,time
from pathlib import Path
BLOCK=1024**2
def require(ok,message):
    if not ok:raise ValueError(message)
def fingerprint(s):return (s.st_dev,s.st_ino,s.st_size,s.st_mtime_ns,s.st_ctime_ns,s.st_uid,s.st_nlink,s.st_mode)
def blind_member(path,size,sha,maximum):
    p=Path(path).absolute();require(not any(x.is_symlink() for x in (p,*p.parents)),'physical opaque member')
    with os.fdopen(os.open(p,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK),'rb') as f:
        before=os.fstat(f.fileno());require(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_uid in (0,os.getuid()) and before.st_size==size<=maximum,'exact regular opaque size/owner/link')
        digest=hashlib.sha256();count=0
        while True:
            block=f.read(min(BLOCK,size-count+1))
            if not block:break
            count+=len(block);require(count<=size,'bounded opaque byte count');digest.update(block)
        after=os.fstat(f.fileno());require(fingerprint(before)==fingerprint(after)==fingerprint(p.stat()) and count==size and digest.hexdigest()==sha,'stable exact blind opaque hash')
    return dict(path=str(p),sha256=sha,bytes=size,device=before.st_dev,inode=before.st_ino,opaque_only=True)
def execute(issuer,request_pin,actual_issue_guard):
    c=issuer.live(request_pin,'cache',{'issue':actual_issue_guard});r=c['request'];root=c['root'];receipt=c['receipt'];auth=issuer.linked(receipt['cache_authority']);delivery=issuer.linked(receipt['delivery']);scope=c['scope'];now=time.time()
    require(r['cache_helper_source']==issuer.pin(__file__),'actual reviewed blind helper source')
    c['batch'].contract.validate_opaque_delivery_authority(delivery,c['scope_pin'],c['rows'],c['context']['config']['original_manifest'])
    require(auth.get('status')=='ROOT_AUTHORIZED_EXACT_NO3_OPAQUE_HOME_CACHE' and auth.get('scope')==c['scope_pin'] and auth.get('funding_ledger')==receipt['funding_ledger']
        and auth.get('source_request')==r['original_delivery_request'] and auth.get('files')==c['rows'] and auth.get('allow_opaque_transport') is True
        and auth.get('no_deserialization_R_numpy_scores_models_losses_or_jobs') is True and auth.get('maximum_files')==15 and type(auth.get('maximum_files')) is int
        and auth.get('maximum_file_bytes')==c['batch'].contract.MAX_TARGET_FILE and auth.get('maximum_total_bytes')==c['batch'].contract.MAX_TARGET_TOTAL
        and auth.get('expected_total_bytes')==163921491 and auth.get('maximum_calls')==1 and type(auth.get('maximum_calls')) is int
        and auth.get('blind_hash_existing_only') is True and auth.get('no_copy') is True and auth.get('cache_helper_source')==r['cache_helper_source']
        and scope['issued_epoch']<=auth['issued_epoch']<=now<auth['expires_epoch']<=scope['expires_epoch'],'exact complete fresh funded byte authority BEFORE first member open')
    issuer.intent(c,'cache');rows=[];total=0
    for row in auth['files']:
        result=blind_member(row['source']['path'],row['bytes'],row['source']['sha256'],auth['maximum_file_bytes']);total+=result['bytes'];require(total<=auth['maximum_total_bytes'],'aggregate opaque bound');rows.append(result)
    require(len(rows)==15 and total==163921491,'complete closed exact15 blind hash')
    value=dict(status='PASS_EXACT_FRESH_AUTHORIZED_OPAQUE_BLIND_HASH_NO_COPY',request=request_pin,scope=c['scope_pin'],funding_ledger=receipt['funding_ledger'],authority=receipt['cache_authority'],source_request=r['original_delivery_request'],
        cache_helper_source=r['cache_helper_source'],files=rows,bytes=total,semantic_array_reads=0,R_executions=0,optimizer_invocations=0,copies=0,issued_epoch=time.time())
    issuer.put(root/'cache.RECEIPT.json',value);return value
def main():
    require(os.sched_getaffinity(0)=={31},'administrative CPU31 only');os.umask(0o077);resource.setrlimit(resource.RLIMIT_CORE,(0,0));resource.setrlimit(resource.RLIMIT_CPU,(8,8));signal.alarm(300)
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--request',required=True);p.add_argument('--request-sha256',required=True);p.add_argument('--issuer-sha256',required=True);p.add_argument('--issue-guard',required=True);p.add_argument('--issue-guard-sha256',required=True);a=p.parse_args()
    source=Path(__file__).absolute().parent/'legacy_issue.py';require(not source.is_symlink() and hashlib.sha256(source.read_bytes()).hexdigest()==a.issuer_sha256,'reviewed issuer before import')
    spec=importlib.util.spec_from_file_location('reviewed_legacy_issuer',source);issuer=importlib.util.module_from_spec(spec);spec.loader.exec_module(issuer)
    value=execute(issuer,dict(path=a.request,sha256=a.request_sha256),dict(path=a.issue_guard,sha256=a.issue_guard_sha256));u=resource.getrusage(resource.RUSAGE_SELF);print(json.dumps(dict(result=value,SELF_CPU_seconds=u.ru_utime+u.ru_stime),sort_keys=True))
if __name__=='__main__':main()
