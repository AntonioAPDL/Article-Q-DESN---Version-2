# JOINT expanded-screen scheduler recovery

Date: 2026-09-30

The expanded case-specific DESN/RHS screen remains scientifically unchanged.
This note repairs only its deferred release condition.

## Defect

The original scheduler required both the final source pipeline status and a
zero exit receipt from `joint_qdesn_pure_recursive_shared_capacity_v7_20260927`.
That historical controller terminated during an execution-control recovery and
its nonzero receipt is permanent. A later compatible controller resumed the
same verified runtime, so the old receipt can never describe final completion.

## Corrected release gate

The scheduler now waits for all of the following:

1. the source campaign records
   `COMPLETE_WITH_PATH_AND_MEAN_STATE_SCORE_PACKETS`;
2. the confirmation MCMC final-manifest verification exists and every row is
   verified;
3. the recursive score packet has `final_packet/DONE`, and every final-packet
   manifest row is verified;
4. no source confirmation or score worker remains active.

The scheduler then launches the existing expanded-screen entry point with its
frozen target and source roots. It does not use partial confirmation results,
does not change the expanded candidate space, and does not relaunch completed
current-screen work.

## Runtime arguments

The corrected positional interface is:

```text
schedule_joint_qdesn_pure_recursive_expanded_screen_after_current.sh \
  SOURCE_ROOT CONFIRMATION_ROOT SCORE_ROOT TARGET_ROOT
```

The prior `SOURCE_CONTROLLER` argument is intentionally removed because a
historical orchestration process is not an authoritative scientific completion
artifact.
