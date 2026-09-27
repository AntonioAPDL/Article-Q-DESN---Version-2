# JOINT pure-recursive shared-capacity recovery

Date: 2026-09-27

## Decision

Resume the pending 136-component VB and 160-worker MCMC confirmation on a
formally partitioned Jerez allocation instead of waiting for the unrelated
PriceFM R120 controller to become globally idle.

This is a runtime amendment only. It does not change the eight case-specific
DESN/RHS selections, seven quantile levels, simulation fixtures, seeds,
posterior targets, structured-VB initialization, M0 MCMC kernel, iteration
budgets, forecast policies, or scoring contract.

## Evidence

- Ridge screening: 6,144/6,144 complete, zero failures.
- RHS screening: 6,000/6,000 complete, zero failures.
- Nested quantile VB: 408/408 complete, zero failures.
- Confirmation VB/MCMC: 0/136 and 0/160; no worker ever launched.
- Exclusive controller wait: more than 37 hours with zero clean polls.
- PriceFM R120: active and pinned to a declared 15-core list.
- Jerez topology: 32 physical cores represented by logical CPUs 0-31.
- Storage and memory: above the existing 100 GiB and one-thread gates.

## Frozen partition

| Owner | Logical CPUs | Physical cores |
|---|---|---:|
| JOINT confirmation | `1,8,9,12,13,15,19,20,24,25,27,28,29,30,31` | 15 |
| PriceFM R120 | `2,3,4,5,6,7,10,11,14,17,18,21,22,23,26` | 15 |
| Spare | `0,16` | 2 |

The topology preflight requires zero physical overlap and complete coverage of
all 32 physical cores. PriceFM processes are allowed by the confirmation host
gate only for the named R120 campaign. The waiting controller separately
checks that the live controller declares exactly the frozen PriceFM list, its
compute children remain inside that reservation, and no process above the
hot-process threshold occupies a JOINT target physical core for five
consecutive polls. Logical siblings are mapped to physical package/core IDs,
so activity on CPUs 32--63 cannot evade the gate.

Jerez also has exactly two long-running non-scientific
`python3 /tmp/finalize_stat7l_syllabus_docx.py` processes with unrestricted
kernel affinity. Their prelaunch logical CPU positions migrate, so treating
their instantaneous positions as fixed reservations makes a five-poll gate
impossible. The controller records both processes and permits at most two
exact command matches; every other hot process remains a blocker. Two physical
cores remain unassigned to JOINT and PriceFM so the Linux scheduler can place
these background processes without systematic scientific-worker
oversubscription. This lane does not alter their processes or affinity.

## Recovery sequence

1. Commit, push, and synchronize the source branch.
2. Archive the old waiting-controller evidence and terminate only its idle
   shell/controller processes; no scientific worker exists to stop.
3. Update the expanded-screen runtime allocation on its dedicated branch.
4. Repoint the expanded scheduler to the new source control root.
5. Start the shared-capacity source controller and require five clean polls.
6. Prepare the 32-cell confirmation packet under contract v2.
7. Run 136 VB components, then 160 MCMC workers.
8. Build and verify the path and mean-state posterior score packets.
9. Release expanded screening only after source exit 0 and the exact terminal
   source status.
10. Stop expanded screening after case-specific RHS selection for scientific
    review; do not auto-launch another quantile/MCMC campaign.

The pure-recursive preparer persists both `cpu_affinity_preflight.csv` and
`shared_capacity_preflight.csv` in its top-level artifact manifest. This keeps
the verified topology and complete JOINT/PriceFM/spare partition auditable
after the live process table changes.

## Failure policy

- Any topology overlap, malformed PriceFM affinity, source-manifest failure,
  nonzero worker failure, or contract mismatch fails closed.
- Partial confirmation artifacts are never used for article selection.
- No article, main, Overleaf, PriceFM, or unrelated runtime file is modified.
- The task remains `NOT_READY_FOR_INTEGRATION` until confirmation and expanded
  screening close independently with verified manifests.
