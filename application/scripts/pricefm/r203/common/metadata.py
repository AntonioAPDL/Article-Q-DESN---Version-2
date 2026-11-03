"""Strict source/metadata utilities. This module never grants execution."""
from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import stat


def require(condition, message):
    if not condition:
        raise ValueError(message)


def closed(value, keys, label):
    require(type(value) is dict and set(value) == set(keys), label + ': exact keys')
    return value


def integer(value, label, minimum=0, maximum=2**63 - 1):
    require(type(value) is int and minimum <= value <= maximum, label + ': integer range')
    return value


def finite(value, label):
    require(type(value) in (int, float) and math.isfinite(value), label + ': finite number')
    return value


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()


def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()


def strict_json(raw):
    require(type(raw) in (bytes, str), 'JSON bytes or text')
    def pairs(rows):
        result = {}
        for key, value in rows:
            require(key not in result, 'duplicate JSON key')
            result[key] = value
        return result
    def number(text):
        return finite(float(text), 'JSON number')
    def invalid(text):
        raise ValueError('nonfinite JSON constant: ' + text)
    return json.loads(raw, object_pairs_hook=pairs, parse_float=number, parse_constant=invalid)


def absolute(value):
    require(type(value) is str and '\x00' not in value, 'path string')
    path = Path(value)
    require(path.is_absolute() and value == str(path) and '..' not in path.parts
            and str(path) != '/', 'canonical absolute path')
    return path


def physical(value):
    path = absolute(value)
    require(not any(p.is_symlink() for p in (path, *path.parents)), 'physical path required')
    return path


def descriptor(value):
    closed(value, {'path', 'sha256'}, 'pin')
    absolute(value['path'])
    require(type(value['sha256']) is str and re.fullmatch('[0-9a-f]{64}', value['sha256']), 'SHA256')
    return value


def read_regular(path, *, limit, expected_sha=None, expected_uid=None, expected_bytes=None):
    path = physical(str(path))
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW)
    with os.fdopen(fd, 'rb') as stream:
        before = os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_nlink == 1
                and 0 <= before.st_size <= limit, 'bounded regular single-link file')
        if expected_uid is not None:
            require(before.st_uid == expected_uid, 'exact file UID')
        if expected_bytes is not None:
            require(before.st_size == expected_bytes, 'exact file size')
        raw = stream.read(limit + 1)
        after = os.fstat(stream.fileno())
    identity = lambda x: (x.st_dev, x.st_ino, x.st_size, x.st_mtime_ns, x.st_ctime_ns,
                          x.st_mode, x.st_uid, x.st_nlink)
    require(identity(before) == identity(after) == identity(path.stat())
            and len(raw) == before.st_size, 'stable complete file read')
    if expected_sha is not None:
        require(hashlib.sha256(raw).hexdigest() == expected_sha, 'actual file SHA256')
    return raw


def linked(pin):
    descriptor(pin)
    require(Path(pin['path']).suffix == '.json', 'metadata JSON only')
    return strict_json(read_regular(pin['path'], limit=4 * 1024**2,
                                   expected_sha=pin['sha256'], expected_uid=os.getuid()))


def source_bytes(pin):
    descriptor(pin)
    require(Path(pin['path']).suffix in {'.py', '.R', '.c', '.h', '.md', '.json'}, 'source only')
    return read_regular(pin['path'], limit=4 * 1024**2,
                        expected_sha=pin['sha256'], expected_uid=os.getuid())


def pin_file(path):
    path = physical(str(path))
    require(path.suffix in {'.json', '.py', '.R', '.c', '.h', '.md'}, 'source or metadata pin')
    return {'path': str(path), 'sha256': hashlib.sha256(read_regular(
        path, limit=4 * 1024**2, expected_uid=os.getuid())).hexdigest()}


def write_new(path, value):
    path = physical(str(path))
    raw = json.dumps(value, indent=2, sort_keys=True, allow_nan=False).encode() + b'\n'
    require(len(raw) <= 4 * 1024**2, 'bounded new metadata')
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(raw)
        stream.flush()
        os.fsync(stream.fileno())
    parent = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(parent)
    finally:
        os.close(parent)
    return pin_file(path)
