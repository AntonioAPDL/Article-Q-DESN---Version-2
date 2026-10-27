# Owned private stage guard

Preparation only. This module grants no authority, reads no target data, launches
no stage by itself, and changes no baseline process. Root must first approve the
exact source, runtime, target, funding, resource scope and new-stage clock. The
caller must hold the exact shared global exclusive flock before entering this
API, including all metadata reads which the resource scope covers.

```python
observation = lambda owned: guard.physical_peer_guard(census, audit_disk_path, owned)
receipt = guard.run_owned(
    command, env=env, stdout=stdout, stderr=stderr,
    preexec_fn=reviewed_R_limits, pass_fds=(lock_fd,), lock_fd=lock_fd,
    wall_seconds=grant['maximum_wall_seconds'],
    maximum_combined_CPU_seconds=fully_funded_controller_plus_child_cap,
    maximum_administrative_CPU_seconds=funded_parent_reserve_minus_tail,
    absolute_deadline_UTC=grant['expires_UTC'],
    peer_check_callback=observation, expected_child_affinity={30},
    interval_seconds=1, peer_interval_seconds=10)
```

The deadline must already be the minimum of all applicable root-stage and global
expiries. No new clock, automatic retry, replacement grant or resource policy is
created here. Combined CPU means the controller's **entire** SELF CPU since
startup, all its already reaped administrative children, plus the new child tree.
Its funding must carry those costs once; it is not merely the R child ceiling.
The caller must additionally charge its post-return finalization CPU. Configure
the R CPU/address-space/file limits in the reviewed preexec function.

`peer_check_callback(None)` runs before launch and after reaping; periodic calls
receive the exact held direct-child PID/start ticks/PPID/boot identity. The pure
CPU/lifetime/wall/thread-child checks run at most1s apart without a global
`/proc` scan. Full peer/resource observations run at a separately declared
maximum10s cadence; this production policy makes no1s peer-reclaim claim.
Each full observation's actual CPU/wall cost is retained for source-context
pricing. The administrative ceiling includes startup and reaped helpers, and
the controller reserves a separately funded finalization tail. Exhaustion stops
only the exact owned child and records the full measured debit; it grants no
replacement allowance.

The pure
stdlib peer checker validates actual physical siblings `{30,62}`. It inspects
all **same-UID** processes and their thread masks, matching the scope of the
root census. Only the observer's current PID and exact owned child lifetime are
excluded. Census entries bind boot, PID, start ticks, command hash and allowed
states; a reviewed stopped peer resuming rejects even outside the pair. Unknown
R/Python/script numerical peers and frozen numerical shell-pipeline markers on
either sibling reject. Same-UID permission
errors and failed observations of still-present processes reject; disappearance
requires a fresh absence proof. Floors remain MemAvailable192GiB and disk80GiB.
This is an observed same-UID resource contract, not CPU isolation against OS or
other-UID workloads. CPU62 receives no numerical authorization.

The caller must be single-threaded, keep default SIGCHLD and never install a
competing reaper. `Popen` creates one new disposable direct child. The supervisor
uses only `wait4`, never `poll`, `wait` or `communicate`, so the kernel retains
the child's PID until this supervisor reaps it. Each abort rechecks boot, exact
PID/start ticks and direct PPID before signalling **only that owned child**.
There is no generic stop-by-PID/process-group API and no baseline signal path.
An identity failure never signals. A child unreaped after SIGKILL remains held
in the module and retains the inherited shared lock; its receipt fails closed.
The caller must not replace the grant or let another borrower proceed.

Before caller preexec and exec, the new child sets PDEATHSIG=SIGKILL with parent
PID rechecks and a private wall timer. Its inherited global lock FD, exact initial
CPU mask and PDEATHSIG are rechecked. A mandatory irreversible Linux x86_64
seccomp filter rejects fork/vfork, rejects clone without CLONE_THREAD, rejects
x32 syscalls, and returns ENOSYS for clone3 so pthreads can use checked clone.
Ordinary same-thread-group threads are permitted and periodically checked for
the exact `{30}` mask. Unsupported architecture/kernel or failed filter setup
exits125 before the payload. A private preexec pipe, closed before target exec,
proves successful kernel-boundary setup; the target cannot forge that proof.
The filter is needed because sampling alone cannot prove that an unobserved
subprocess did not escape. It permits exact direct-thread-group CPU accounting
with `/proc` live CPU and final `wait4` rusage. Any observed subprocess descendant
still aborts and invalidates accounting completeness. No cgroups or pidfds are
required. Compatibility with the exact pinned private R runtime remains an
admission prerequisite; these metadata tests do not prove target-model success.

Only a receipt with `status == 'EXITED'`, `returncode == 0`, and all of
`reaped`, `drained`, `CPU_accounting_complete`, `preexec_kernel_boundary_proved`
and `subprocess_creation_kernel_denied` true permits later candidate sealing.
The receipt includes cumulative parent and reaped-child CPU, exact wait4 child
CPU/RSS, periodic and post-reap peer evidence, limit/deadline, abort details and
the inherited lock inode. An external fresh physical-drain/root decision remains
necessary before a different borrower; the module never unlocks/refills itself.

Validation uses only administrative CPU31 metadata/sleep processes and synthetic
`/proc` trees. It tests real wait4 ownership, shared-flock exclusion, PDEATHSIG
after a disposable supervisor exits, irreversible process-creation denial while
allowing an ordinary thread, deadline/CPU aborts, preexec boundary failure, unknown
SMT62 peers, changed census bindings, permission errors and identity-loss no-kill.
No R, optimizer, production arrays or target certificate calculation is used.
