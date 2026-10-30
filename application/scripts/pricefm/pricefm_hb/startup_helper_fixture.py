"""Private synthetic helper lifecycle; never a model or R startup proof."""
import argparse
import errno
import json
import os
from pathlib import Path
import resource
import sys
import time


def main():
    p = argparse.ArgumentParser(); p.add_argument("--case", required=True); p.add_argument("--nonce", required=True)
    a = p.parse_args()
    status = dict(line.split(":", 1) for line in Path("/proc/self/status").read_text().splitlines() if ":" in line)
    assert status["NoNewPrivs"].strip() == "1" and status["Seccomp"].strip() == "2"
    assert os.getpid() == os.getsid(0) == os.getpgrp()
    value = dict(status="PASS_SYNTHETIC_OWNED_HELPER_FIXTURE", role="SYNTHETIC_OWNED_HELPER",
        case=a.case, nonce=a.nonce, models=0, optimizer_invocations=0, scientific_data_read=False)
    if a.case == "wait_and_escape":
        readfd, writefd = os.pipe()
        pid = os.fork()
        if pid == 0:
            os.close(readfd); denied = 0
            try:
                for operation in (os.setsid, lambda: os.sched_setaffinity(0, os.sched_getaffinity(0)),
                                  lambda: os.kill(os.getpid(), 0)):
                    try:
                        operation()
                    except PermissionError as error:
                        assert error.errno == errno.EPERM; denied += 1
                os.write(writefd, str(denied).encode()); os.close(writefd)
                os._exit(0 if denied == 3 else 97)
            except BaseException:
                os._exit(98)
        os.close(writefd); raw = os.read(readfd, 100); os.close(readfd)
        got, code = os.waitpid(pid, 0); result = os.waitstatus_to_exitcode(code)
        assert got == pid and result == 0 and raw == b"3"
        value.update(helper_wait_status=result, escape_operations_denied=3)
        failed = os.fork()
        if failed == 0:
            os._exit(7)
        got, code = os.waitpid(failed, 0)
        assert got == failed and os.waitstatus_to_exitcode(code) == 7
        value["deliberate_nonzero_helper_status_observed"] = 7
    elif a.case == "orphan":
        pid = os.fork()
        if pid == 0:
            time.sleep(.15); os._exit(0)
        value["intentionally_unwaited_private_helper"] = True
        print(json.dumps(value, sort_keys=True), flush=True); os._exit(0)
    elif a.case == "nonzero_helper":
        pid = os.fork()
        if pid == 0:
            os._exit(7)
        _, code = os.waitpid(pid, 0)
        # A parent returning0 despite a failed helper is specifically forbidden.
        raise SystemExit(os.waitstatus_to_exitcode(code))
    elif a.case == "cpu_boundary":
        pid = os.fork()
        if pid == 0:
            while True:
                pass
        startup = dict(case=a.case, helper_pid=pid,
                       inherited_CPU_limits=list(resource.getrlimit(resource.RLIMIT_CPU)))
        print(json.dumps(startup), flush=True)
        os.waitpid(pid, 0)
    elif a.case == "wall_boundary":
        pid = os.fork()
        if pid == 0:
            time.sleep(120); os._exit(0)
        time.sleep(120)
    else:
        raise ValueError("unsupported owned synthetic case")
    print(json.dumps(value, sort_keys=True), flush=True)


if __name__ == "__main__":
    main()
