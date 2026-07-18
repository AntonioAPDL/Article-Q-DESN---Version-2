# Joint exQDESN Phase138 selected long-chain launch

Date: 2026-07-16

## Purpose

Phase138 is the selected long-chain confirmation that follows the Phase137 readiness audit. It is
designed to answer one narrow question:

> If the Phase136 winning gamma-kernel choice is held fixed within each high-priority case, does a
> longer selected MCMC run materially improve the exAL posterior quantile-grid evidence?

This is still not an article-promotion step. It is the confirmation layer needed before deciding
whether the exAL rows should enter the final article-facing validation table.

## Why this is the optimal next run

Phase136 completed cleanly enough to continue:

- 5 high-priority cases;
- 10 case-kernel variants;
- 80 MCMC chain jobs;
- 0 worker failures;
- 0 raw forecast crossings;
- 0 contract forecast crossings.

However, all Phase136 case-variants remained review-level because gamma lag-1 autocorrelation was
high and several rows had Rhat review flags. Phase136 also showed that selected exAL MCMC improves
matched exAL VB in most high-priority cases, but still does not match the corresponding AL rows.

Therefore, launching a broad 16-row exAL MCMC campaign would spend too much compute before knowing
whether the selected gamma kernels stabilize under longer chains. The efficient next move is to
focus the same order of chain-iteration budget on the five selected case-kernel winners.

## Selected groups

Phase137 selected:

| Group | Cases | Kernel | Chain jobs |
|---|---:|---|---:|
| `selected_bounded_w4` | 3 | bounded gamma slice, width multiplier 4 | 24 |
| `selected_logit_w4` | 2 | logit-scale gamma slice, eta width 4 | 16 |

Each chain uses:

```text
mcmc_n_iter = 16000
mcmc_burn = 4000
mcmc_thin = 1
n_chains = 8
mcmc_seed_offset = 8600
save_rdata = false
```

This preserves the Phase136 total iteration order:

```text
Phase136: 10 variants x 8 chains x 8000 = 640000 chain-iterations
Phase138:  5 variants x 8 chains x 16000 = 640000 chain-iterations
```

## Resource policy

At launch time the machine had 64 cores and a load average near 36, with unrelated GloFAS,
PriceFM, and TT500 jobs active. Running both Phase138 groups simultaneously would request 40
additional workers and could overcommit the machine.

The Phase138 launcher therefore runs the groups sequentially in one scheduler tmux session:

1. `selected_bounded_w4` at 24 cores;
2. `selected_logit_w4` at 16 cores.

This is slower than full concurrency but much safer for a shared, long-running validation machine.

## Launcher

New launcher:

```bash
bash application/scripts/147_launch_joint_exqdesn_phase138_selected_long_chain_confirmation.sh
```

The launcher reads:

```text
application/cache/joint_qdesn_phase137_exal_gamma_kernel_readiness_20260716/phase137_next_launch_plan.csv
```

It writes orchestration artifacts to:

```text
application/cache/joint_qdesn_phase138_selected_long_chain_confirmation_20260716_orchestration
```

The scheduler tmux session is:

```text
joint_qdesn_phase138_selected_long_chain_20260716
```

The launcher does not modify article assets.

## Expected outputs

Phase138 group outputs:

```text
application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_bounded_w4
application/cache/joint_qdesn_phase138_exal_selected_long_chain_confirmation_20260716_logit_w4
```

Orchestration outputs:

- `phase138_orchestration_plan.csv`;
- per-group job scripts;
- per-group stdout logs;
- per-group time logs;
- per-group exit files;
- `phase138_scheduler.log`;
- `phase138_scheduler.exit`;
- `artifact_manifest.csv`;
- `README.md`.

## Gates after completion

Hard fail:

- nonzero scheduler or group exit;
- worker failures in any group;
- missing or failed artifact manifests, except the already documented Phase136 historical figure-path
  repair;
- nonfinite scores;
- nonzero contract crossings.

Review:

- gamma autocorrelation remains high;
- Rhat remains above review threshold;
- ESS remains low;
- exAL improves over Phase136 but remains materially worse than matched AL.

Potential article-promotion condition:

- implementation gates pass;
- contract crossings are zero;
- performance improves materially relative to Phase136;
- selected exAL rows become competitive enough with matched AL to justify article-facing inclusion,
  or else the manuscript clearly presents exAL as a diagnostic extension rather than the main
  validated winner.

## Next audit

After the scheduler finishes, run a Phase138 health/deep-audit stage before touching the article.
That audit should compare:

- Phase138 vs Phase136 selected rows;
- Phase138 vs Phase135 matched exAL VB;
- Phase138 vs matched AL rows;
- gamma/sigma trace behavior;
- Rhat/ESS/autocorrelation;
- raw and contract crossings;
- runtime and failure modes.
