#!/usr/bin/python3.11
"""Retained three-library build, not numerical/model execution or ABI approval."""
import argparse
import datetime as dt
import hashlib
import json
import os
import pathlib
import re
import resource
import shlex
import shutil
import subprocess
import sys
import time

RHOME = pathlib.Path('/data/jaguir26/local/opt/R/4.6.0/lib64/R')
RSCRIPT = pathlib.Path('/data/jaguir26/local/opt/R/4.6.0/bin/Rscript')
STEMS = {'key': 'mq_key_hash', 'isotonic': 'mq_isoreg_batch', 'inverse': 'mq_event_inverse'}
SOURCE_PATHS = ['scripts/build_mq_native_replay.py',
                'application/tests/test_build_mq_native_replay.py',
                'docs/implementation_notes/mq_native_retained_build_20261102.md'] + [
                    'scripts/native/' + stem + '.c' for stem in STEMS.values()]

def need(condition, message):
    if not condition:
        raise ValueError('MQ_NATIVE_BUILD: ' + message)

def digest(path):
    h = hashlib.sha256()
    with open(path, 'rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()

def canonical(path):
    p = pathlib.Path(path)
    need(p.is_absolute() and str(p.resolve(strict=True)) == str(p) and not p.is_symlink(),
         'canonical nonsymlink existing path required')
    return p

def file_pin(path):
    p = canonical(path)
    need(p.is_file(), 'regular file required')
    return {'path': str(p), 'size_bytes': p.stat().st_size, 'sha256': digest(p)}

def verify_pin(pin, maximum=256 * 1024**2):
    need(isinstance(pin, dict) and set(pin) == {'path', 'size_bytes', 'sha256'}, 'exact file pin required')
    need(type(pin['size_bytes']) is int and 0 < pin['size_bytes'] <= maximum and
         re.fullmatch('[0-9a-f]{64}', pin['sha256']) is not None, 'bounded size/SHA required')
    need(file_pin(pin['path']) == pin, 'pinned bytes changed: ' + pin['path'])
    return pathlib.Path(pin['path'])

def unique_object(pairs):
    out = {}
    for key, value in pairs:
        need(key not in out, 'duplicate JSON object key')
        out[key] = value
    return out

def read_json(path, maximum=2 * 1024**2):
    p = canonical(path)
    need(p.is_file() and p.stat().st_size <= maximum, 'bounded JSON file required')
    return json.loads(p.read_text(), object_pairs_hook=unique_object)

def clean_environment(makevars=None):
    # Preserve only ordinary identity/authentication/session metadata. Make,
    # compiler, loader, shell and Git injection settings are not inherited.
    env = {key: os.environ[key] for key in ('HOME', 'USER', 'LOGNAME', 'SSH_AUTH_SOCK',
           'XDG_RUNTIME_DIR', 'DBUS_SESSION_BUS_ADDRESS') if key in os.environ}
    # Injection variables stay ABSENT, not empty: GCC_EXEC_PREFIX='' and
    # empty include-path components have meaningful compiler search semantics.
    env.update(PATH='/usr/bin:/bin', LC_ALL='C', TZ='UTC', MAKEFLAGS='-j1',
               OMP_NUM_THREADS='1', OPENBLAS_NUM_THREADS='1', MKL_NUM_THREADS='1',
               R_MAKEVARS_SITE='/dev/null', R_MAKEVARS_USER=str(makevars) if makevars else '/dev/null',
               R_PROFILE='/dev/null', R_PROFILE_USER='/dev/null', R_ENVIRON='/dev/null', R_ENVIRON_USER='/dev/null')
    return env

def command(argv, cwd=None, env=None, timeout=25):
    result = subprocess.run(list(map(str, argv)), cwd=cwd, env=env or clean_environment(),
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=timeout, check=False)
    need(result.returncode == 0, 'command failed: ' + str(argv[0]) + '\n' + result.stdout)
    return result.stdout

def git(root, *args):
    return command(['/usr/bin/git', '--no-replace-objects', '-c', 'core.fsmonitor=false', '-C', root, *args]).strip()

def dependency_elf_type(path):
    with open(path, 'rb') as stream:
        header = stream.read(20)
    if header[:4] != b'\x7fELF':
        return None
    need(len(header) == 20 and header[5] in (1, 2), 'invalid ELF dependency header')
    kind = int.from_bytes(header[16:18], 'little' if header[5] == 1 else 'big')
    need(kind in (1, 2, 3), 'unsupported ELF toolchain type')
    return kind  # ET_REL is hash-pinned, never handed to the dynamic loader.

def dependency_paths(text):
    need('not found' not in text, 'unresolved dynamic toolchain dependency')
    return re.findall(r'(?:=>\s+)?(/[^\s()]+)', text)

def validate_scope(spec, now=None):
    fields = {'schema_version', 'purpose', 'nonce', 'expires_utc', 'source_root', 'source_commit',
              'source_tree', 'published_ref', 'origin_remote_url', 'output_root', 'source_files',
              'toolchain_files', 'header_files', 'limits', 'allow_retained_build',
              'allow_numeric_replay', 'allow_refit', 'allow_scoring', 'allow_future_truth',
              'allow_production', 'allow_article'}
    need(isinstance(spec, dict) and set(spec) == fields, 'exact retained-build contract fields required')
    need(spec['schema_version'] == 'mq_native_retained_build_contract_v1' and
         spec['purpose'] == 'CONTROLLED_RETAINED_THREE_DLL_BUILD_ONLY', 'wrong build purpose')
    need(spec['allow_retained_build'] is True and all(spec[k] is False for k in
         ('allow_numeric_replay', 'allow_refit', 'allow_scoring', 'allow_future_truth', 'allow_production', 'allow_article')),
         'build-only permissions required')
    need(re.fullmatch('[a-f0-9]{32,64}', spec['nonce']) is not None, 'fresh nonce required')
    for key in ('source_commit', 'source_tree'):
        need(re.fullmatch('[a-f0-9]{40}', spec[key]) is not None, 'full source identities required')
    need(spec['origin_remote_url'] == 'git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git' and
         re.fullmatch('refs/heads/work/[A-Za-z0-9_./-]+', spec['published_ref']) is not None and
         '..' not in spec['published_ref'] and '//' not in spec['published_ref'], 'dedicated published source ref required')
    expiry = dt.datetime.fromisoformat(spec['expires_utc'].replace('Z', '+00:00'))
    current = now or dt.datetime.now(dt.timezone.utc)
    need(expiry.tzinfo is not None and expiry > current + dt.timedelta(seconds=120), 'purpose must cover complete bounded build')
    need(isinstance(spec['limits'], dict) and all(type(v) is int for v in spec['limits'].values()) and
         spec['limits'] == {'cpu_seconds': 120, 'wall_term_seconds': 119,
         'wall_kill_after_seconds': 1, 'address_space_bytes': 2 * 1024**3,
         'output_bytes': 64 * 1024**2, 'logical_cpu': 26}, 'fixed finite build limits required')
    for key in ('source_files', 'toolchain_files', 'header_files'):
        values = spec[key]
        need(isinstance(values, list) and values and all(isinstance(v, dict) for v in values) and
             len({v.get('path') for v in values}) == len(values), 'unique complete input inventories required')
    return expiry

def source_guard(spec):
    root = canonical(spec['source_root'])
    need(git(root, 'rev-parse', 'HEAD') == spec['source_commit'] and
         git(root, 'rev-parse', 'HEAD^{tree}') == spec['source_tree'] and
         git(root, 'rev-parse', '--show-toplevel') == str(root) and
         not git(root, 'status', '--porcelain=v1', '--untracked-files=all'), 'clean exact committed source required')
    need({p['path'] for p in spec['source_files']} == {str(root / p) for p in SOURCE_PATHS}, 'exact build source closure required')
    for pin in spec['source_files']:
        path = verify_pin(pin, 4 * 1024**2)
        relative = path.relative_to(root).as_posix()
        raw = subprocess.check_output(['/usr/bin/git', '--no-replace-objects', '-C', str(root),
                                       'cat-file', 'blob', spec['source_commit'] + ':' + relative])
        need(hashlib.sha256(raw).hexdigest() == pin['sha256'], 'source differs from committed blob')
    need(git(root, 'remote', 'get-url', 'origin') == spec['origin_remote_url'], 'origin differs')
    env = clean_environment()
    env.update(GIT_TERMINAL_PROMPT='0', GIT_SSH_COMMAND='/usr/bin/ssh -F /dev/null -oBatchMode=yes '
               '-oControlMaster=no -oControlPath=none -oControlPersist=no -oProxyCommand=none -oProxyJump=none -oRequestTTY=no')
    remote = command(['/usr/bin/git', '-C', root, 'ls-remote', '--exit-code', 'origin', spec['published_ref']], env=env).split()
    need(remote == [spec['source_commit'], spec['published_ref']], 'fresh published source readback differs')
    return root

def discover_inputs(root):
    """SDK/header preprocessing only; caller separately bounds this enrollment."""
    root = canonical(root)
    need(command(['/usr/bin/gcc', '-dumpfullversion']).strip() == '8.5.0', 'GCC8.5 required')
    need(command([RSCRIPT, '--vanilla', '-e', 'cat(as.character(getRversion()))']).strip() == '4.6.0', 'native R4.6 required')
    headers = set()
    for stem in STEMS.values():
        deps = command(['/usr/bin/gcc', '-M', '-I' + str(RHOME / 'include'), '-I/usr/local/include',
                        '-DNDEBUG', root / 'scripts/native' / (stem + '.c')])
        paths = shlex.split(deps.split(':', 1)[1].replace('\\\n', ' '))
        headers.update(str(pathlib.Path(p).resolve(strict=True)) for p in paths if p.endswith('.h'))
    tools = {'/usr/bin/gcc', '/usr/bin/make', '/usr/bin/git', '/usr/bin/ssh', '/usr/bin/timeout',
             '/usr/bin/python3.11', '/usr/bin/sh', '/usr/bin/sed', '/usr/bin/grep', '/usr/bin/expr',
             '/usr/bin/uname', '/usr/bin/rm', '/usr/bin/ldd', str(RSCRIPT), str(RHOME / 'bin/R'),
             str(RHOME / 'bin/Rscript'), str(RHOME / 'bin/exec/R'), str(RHOME / 'etc/Makeconf')}
    for folder in ('bin', 'etc', 'share/make', 'share/R'):
        tools.update(str(p.resolve(strict=True)) for p in (RHOME / folder).rglob('*') if p.is_file())
    package_code = command([RSCRIPT, '--vanilla', '-e',
        'loadNamespace("tools"); loadNamespace("compiler"); for(p in loadedNamespaces()) {'
        'b<-find.package(p); f<-c(file.path(b,c("DESCRIPTION","NAMESPACE")),'
        'unlist(lapply(c("R","libs","Meta"),function(d)list.files(file.path(b,d),'
        'full.names=TRUE,recursive=TRUE,all.files=TRUE,no..=TRUE))));'
        'f<-f[file.exists(f)&!dir.exists(f)];cat(paste(f,collapse="\\n"),"\\n",sep="")}'])
    tools.update(str(pathlib.Path(p).resolve(strict=True)) for p in package_code.splitlines() if p.startswith('/'))
    for name in ('cc1', 'collect2', 'as', 'ld'):
        value = command(['/usr/bin/gcc', '-print-prog-name=' + name]).strip()
        tools.add(str(pathlib.Path(value if '/' in value else shutil.which(value, path='/usr/bin:/bin')).resolve(strict=True)))
    for name in ('libgcc_s.so.1', 'crtbeginS.o', 'crtendS.o', 'crti.o', 'crtn.o'):
        value = command(['/usr/bin/gcc', '-print-file-name=' + name]).strip()
        need(value != name, 'missing compiler link input ' + name)
        tools.add(str(pathlib.Path(value).resolve(strict=True)))
    crypto = command(['/usr/bin/gcc', '-print-file-name=libcrypto.so']).strip()
    need(crypto != 'libcrypto.so', 'explicit system libcrypto link input missing')
    tools.add(str(pathlib.Path(crypto).resolve(strict=True)))
    tools.update(str(p.resolve(strict=True)) for p in (RHOME / 'lib').iterdir() if p.is_file())
    initial = sorted({str(pathlib.Path(p).resolve(strict=True)) for p in tools})
    for path in initial:
        if dependency_elf_type(path) in (2, 3):
            loader_env = clean_environment()
            loader_env['LD_LIBRARY_PATH'] = str(RHOME / 'lib')
            lines = command(['/usr/bin/ldd', path], env=loader_env)
            for value in dependency_paths(lines):
                tools.add(str(pathlib.Path(value).resolve(strict=True)))
    return {'toolchain_files': [file_pin(p) for p in sorted({str(pathlib.Path(x).resolve(strict=True)) for x in tools})],
            'header_files': [file_pin(p) for p in sorted(headers)]}

def native_limits(spec):
    need(sys.version_info[:2] == (3, 11) and sys.flags.isolated and sys.flags.no_site and
         sys.dont_write_bytecode, 'isolated no-site/no-bytecode Python3.11 required')
    need(not os.getenv('LD_PRELOAD') and not os.getenv('LD_AUDIT') and not os.getenv('LD_LIBRARY_PATH'),
         'no initial loader injection permitted')
    need(os.sched_getaffinity(0) == {26}, 'build core26 required')
    for key, value in ((resource.RLIMIT_CPU, 120), (resource.RLIMIT_AS, 2 * 1024**3),
                       (resource.RLIMIT_FSIZE, 64 * 1024**2)):
        need(resource.getrlimit(key) == (value, value), 'native hard/soft build rlimit differs')
    pid = os.getpid()
    for _ in range(12):
        stat = pathlib.Path('/proc/' + str(pid) + '/stat').read_text()
        tail = stat.rsplit(') ', 1)[1].split()
        parent = int(tail[1])
        if parent <= 1:
            break
        argv = pathlib.Path('/proc/' + str(parent) + '/cmdline').read_bytes().rstrip(b'\0').split(b'\0')
        if argv and pathlib.Path(os.fsdecode(argv[0])).name == 'timeout':
            need(argv[1:4] == [b'--signal=TERM', b'--kill-after=1s', b'119s'] and
                 os.getpgid(0) == parent and os.getpgid(parent) == parent, 'whole-group native timeout differs')
            return
        pid = parent
    need(False, 'exact whole-group timeout ancestor absent')

def build(spec, purpose_sha):
    expiry = validate_scope(spec)
    native_limits(spec)
    root = source_guard(spec)
    inventory = discover_inputs(root)
    need(inventory == {k: spec[k] for k in inventory}, 'complete toolchain/header inventory differs')
    for group in ('toolchain_files', 'header_files'):
        for pin in spec[group]:
            verify_pin(pin)
    output = pathlib.Path(spec['output_root'])
    parent = canonical(str(output.parent))
    need(not output.exists() and not output.is_symlink() and parent.stat().st_uid == os.getuid() and
         not output.is_relative_to(root), 'fresh externally owned build directory required')
    output.mkdir(mode=0o700)
    started = time.monotonic()
    makevars = output / 'controlled.Makevars'
    crypto = pathlib.Path(command(['/usr/bin/gcc', '-print-file-name=libcrypto.so']).strip()).resolve(strict=True)
    need(str(crypto) in {pin['path'] for pin in spec['toolchain_files']}, 'unbound crypto link input')
    makevars.write_text('CC = /usr/bin/gcc\nCFLAGS = -O2 -fno-fast-math -ffp-contract=off\n'
                        'PKG_CFLAGS = -fno-fast-math -ffp-contract=off\nPKG_LIBS = -Wl,-rpath,' + str(RHOME / 'lib') + ' ' + str(crypto) + '\n')
    result = {'schema_version': 'mq_native_retained_build_receipt_v1',
              'status': 'BUILD_IN_PROGRESS', 'source_commit': spec['source_commit'], 'source_tree': spec['source_tree'],
              'purpose_sha256': purpose_sha, 'source_files': spec['source_files'], 'dlls': {},
              'R_home': str(RHOME), 'R_libdir': str(RHOME / 'lib'),
              'controlled_Makevars': makevars.read_text(), 'compile_logs': [],
              'toolchain_files': spec['toolchain_files'], 'header_files': spec['header_files'],
              'numeric_replay_executed': False, 'source_runtime_authenticated': False, 'C_ABI_qualified': False,
              'production_authorized': False, 'allow_refit': False, 'allow_scoring': False, 'allow_article': False}
    try:
        for role, stem in STEMS.items():
            source = root / 'scripts/native' / (stem + '.c')
            copied = output / (stem + '.c')
            shutil.copyfile(source, copied)
            text = command([RHOME / 'bin/R', 'CMD', 'SHLIB', '--preclean', copied.name],
                           cwd=output, env=clean_environment(makevars), timeout=30)
            need(all(flag in text for flag in ('-fno-fast-math', '-ffp-contract=off', '-Wl,-rpath,' + str(RHOME / 'lib'))),
                 'actual compiler flags/rpath absent')
            log = output / (stem + '.build.log')
            log.write_text(text)
            result['compile_logs'].append(file_pin(str(log)))
            result['dlls'][role] = dict(file_pin(str(output / (stem + '.so'))),
                                       source_path=source.relative_to(root).as_posix(), source_sha256=digest(source))
            need(sum(p.stat().st_size for p in output.rglob('*') if p.is_file()) < spec['limits']['output_bytes'], 'build output cap exceeded')
        need(discover_inputs(root) == inventory, 'toolchain/SDK changed after compilation')
        source_guard(spec)
        need(dt.datetime.now(dt.timezone.utc) < expiry, 'build purpose expired')
        usage = [resource.getrusage(k) for k in (resource.RUSAGE_SELF, resource.RUSAGE_CHILDREN)]
        cpu = sum(x.ru_utime + x.ru_stime for x in usage)
        need(cpu < 120 and time.monotonic() - started < 120, 'whole-build budget exceeded')
        result.update(status='RETAINED_NATIVE_BUILD_COMPLETE_NOT_NUMERICAL_QUALIFICATION',
                      inputs_reverified=True, CPU_seconds=cpu, wall_seconds_after_admission=time.monotonic() - started)
    except BaseException as error:
        result.update(status='FAILED_RETAINED_BUILD', error=str(error))
        (output / 'BUILD_FAILURE.json').write_text(json.dumps(result, indent=2) + '\n')
        raise
    (output / 'BUILD_RECEIPT.json').write_text(json.dumps(result, indent=2) + '\n')
    need(sum(p.stat().st_size for p in output.rglob('*') if p.is_file()) < spec['limits']['output_bytes'], 'final build output cap exceeded')
    print('MQ_RETAINED_NATIVE_BUILD_COMPLETE_NOT_NUMERICAL_QUALIFICATION')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract', required=True)
    parser.add_argument('--sha256', required=True)
    parser.add_argument('--execute', action='store_true', required=True)
    args = parser.parse_args()
    need(re.fullmatch('[0-9a-f]{64}', args.sha256) is not None, 'purpose SHA required')
    contract = canonical(args.contract)
    need(contract.stat().st_size <= 2 * 1024**2 and digest(contract) == args.sha256, 'external purpose bytes differ')
    spec = read_json(str(contract))
    need(not contract.is_relative_to(canonical(spec['source_root'])), 'purpose must be external to source')
    build(spec, args.sha256)

if __name__ == '__main__':
    main()
