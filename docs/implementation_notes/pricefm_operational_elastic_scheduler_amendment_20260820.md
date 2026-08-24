# PriceFM operational elastic scheduler amendment

## Decision

The scientific PriceFM operational campaign remains unchanged, but its fixed
20-core scheduler is replaced by an elastic 1-20 physical-core scheduler. The
amendment is operational only: it does not alter data, windows, architecture,
seeds, epochs, graph masks, validation selection, test isolation, promotion
gates, registry state, or article state.

## Evidence for the amendment

The repaired fixed scheduler remained healthy for more than 16 hours and made
468 resource observations without starting preparation or a model. During that
period:

- 20 idle physical cores occurred in 0 percent of polls;
- 16 idle physical cores occurred in 0 percent of polls;
- at least four idle physical cores occurred in 1.71 percent of polls;
- at least two idle physical cores occurred in 61.54 percent of polls;
- at least one idle physical core occurred in 74.57 percent of polls;
- the maximum observed idle capacity was five physical cores;
- the minimum observed one-minute load was 44.51, above the old limit of 36;
- no operational artifact or child model process was created.

The host has 32 physical cores and 64 logical CPUs. Concurrent protected work
continuously replenished the machine, so an all-or-nothing 20-core gate had no
credible path to execution. Merely relaunching or lowering the fixed threshold
to 16 would reproduce the same starvation.

## Elastic resource contract

`198_launch_pricefm_operational_elastic_campaign.py` keeps the original stage
order and invokes the unchanged scientific scripts `190` through `196`.

The replacement scheduler:

- dispatches from one to twenty model processes;
- samples both logical siblings of every physical core;
- requires a core to be idle in two consecutive samples;
- never dispatches more than one PriceFM model on one physical core;
- limits every process to one numerical thread;
- excludes physical cores already leased to active PriceFM jobs;
- preserves four logical CPUs of projected load headroom with a ceiling of 60;
- applies niceness 10 to PriceFM workers;
- retains 128 GiB available-memory and 150 GiB free-disk gates;
- stops dispatching when capacity disappears but never kills an active fit;
- rechecks capacity before dispatching replacement work;
- resumes only from hash-verified completed artifacts;
- retains deterministic seeds, retry bounds, exact-vendor Python preflight,
  source hashes, and the exclusive PriceFM campaign lock.

Preparation and lightweight control stages use one stable idle physical core.
Model pools automatically scale to a reserved 20-core window if one appears.

## Scientific invariance

Concurrency and process scheduling can change wall-clock time but not the
campaign estimand or selection protocol. The amendment continues to run:

- nine Phase-I fits using three seeds per fold;
- 1,047 deduplicated Phase-II graph-mask fits;
- at most 456 validation-triggered stability fits;
- validation-only winner freezing for 114 region/fold cells;
- 114 unique test-scoring tasks after the winner hashes are frozen;
- a read-only closeout against authoritative Q-DESN and cached PriceFM.

R56 remains deferred until the operational closeout determines whether EE fold
1 still passes the dual-reference gate. Registry and article mutation remain
blocked.

## Transition protocol

The fixed waiter must remain alive while the replacement is implemented and
tested. Once the replacement branch is committed and pushed, the transition is:

1. verify that the fixed scheduler has no child process or partial artifact;
2. archive its health, events, preflight, and launch contract;
3. terminate only the fixed PriceFM scheduler and confirm lock release;
4. launch the elastic scheduler with a separate log root and the same artifact
   root;
5. verify the new preflight, source manifest, lock ownership, and first health
   record;
6. confirm that preparation or fitting starts only on stable idle physical
   cores.
