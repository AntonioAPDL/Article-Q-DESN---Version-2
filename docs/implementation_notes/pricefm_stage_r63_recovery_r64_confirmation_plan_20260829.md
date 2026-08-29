# PriceFM Stage-R63 recovery and Stage-R64 confirmation plan

Date: 2026-08-29

Lane: PriceFM only

## Decision

Preserve every completed Stage-R63 fit. Recover the shared postfit contract in
place, rerun the validation-only closeout, and freeze its winners before any
further statistical computation. Do not rerun Stage-R63, open test data, mutate
the PriceFM registry, or update the article. A later Stage-R64 may confirm only
the frozen validation winners with the genuine joint seven-quantile MCMC kernel;
the historical Stage-R50 independent single-quantile runner is not an equivalent
confirmation engine.

## Audited state before recovery

- Task worktree: `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__pricefm_joint_quantile_20260824`.
- Branch and upstream: `work/pricefm-joint-quantile-20260824`.
- Frozen pre-recovery head: `b6434e797e0afac376e5891ffe3f635107e31b77`.
- Runtime tag: `pricefm_stage_r63_corrected_joint_campaign_20260827`.
- All 38 arms over 30 case-specific region/fold cells completed with zero fit
  failures and no active PriceFM process.
- All 38 checkpoints, prediction tables, contract metrics, and source manifests
  exist and independently verify. The fits consumed 298.383 core-hours.
- The run tree uses 13.43 GiB. Reconstructible adapter matrices account for
  10.95 GiB; 1.05 GiB of compact RDS checkpoints and initializers must remain.
- Test, registry, article, and MCMC launch authorization are false.

## Root cause and scope of repair

The R63 runtime schema replaced the legacy scalar `tau0` with
`rhs_control.anchor_tau0` and `rhs_control.innovation_tau0`. The shared postfit
repair generated contract predictions and validation metrics, then attempted to
serialize `cfg["tau0"]`. That late `KeyError` left all summaries marked as
postfit-pending and prevented the guarded adapter cleanup. The R61 mechanism
runner also hard-coded `stage = "R61"`, and both the repair and closeout commands
returned shell success for blocked scientific summaries.

The correction must:

1. accept legacy scalar and split joint-RHS schemas;
2. retain the scalar anchor alias for old readers while recording both scales;
3. honor the configured stage in future runner summaries;
4. return a nonzero process code for actual repair failures or blocked R63
   closeout;
5. preserve compact fit dimensions and elapsed time after adapter cleanup;
6. add an executable split-RHS repair fixture, rather than only a source-text
   schema assertion.

No likelihood, design matrix, prediction, checkpoint, or fitted parameter is
changed by this repair.

## Recovery transaction

Run focused tests before touching runtime artifacts. Then execute the idempotent
postfit repair against the existing 38-case manifest with eight workers,
original-scale metric replay enabled, and guarded heavy cleanup enabled. A case
may delete only the seven reconstructible adapter matrix/row files after its
completed summary and hashes have been written atomically. Checkpoints,
predictions, metrics, traces, diagnostics, logs, configs, and manifests remain.

The closeout may run only after all 38 cases report postfit completion, zero
repair failures, matching checkpoint and source-manifest hashes, train/validation
firewalls, and zero contract crossing pairs. It selects one arm independently
for each of the 30 cells using contract validation AQL and requires improvement
against both the exact R62 independent authority and the old joint result, plus
the preregistered stability gate. Test remains sealed.

## Provisional scientific diagnosis

Before durable closeout, reconstructed metrics show three provisional winners:
PT fold 2, HU fold 3, and SI fold 3. Their gains over the exact independent
authority are approximately 0.360%, 0.195%, and 0.036%. Their raw joint outputs
also beat the independent reference, so isotonic projection does not create the
direction of the gain. All gains remain too small for article promotion without
MCMC and frozen test confirmation.

The selected R63 arm improves the old joint result in 26 of 30 cells but beats
the independent authority in only three. None of the 38 VB fits reaches the
strict tolerance. The severe same-family arms do not repair IT_NORD fold 2,
IT_SARD fold 2, LT fold 1, or SE_2 fold 2. At the tested settings, initialization
and innovation-scale changes are therefore not a sufficient explanation of the
joint-versus-independent gap. Another broad R63-style VB campaign is not
scientifically justified.

## Stage-R64 joint-MCMC boundary

Stage-R64 must be generated only from the frozen R63 confirmation queue. It must
fit a single joint ordered seven-quantile model per selected region/fold, retain
the exact case-specific DESN and information-set contract, preserve AL versus
exAL family and split RHS scales, and initialize from the corresponding R63
checkpoint. It must not combine seven independently fitted quantiles or perform
post-hoc synthesis.

The repository contains genuine joint AL and exAL MCMC kernels and chain-pooling
diagnostics. The old PriceFM Stage-R50 runner is not suitable because it fits
separate tau/component jobs. Before launch, a no-launch prep must verify:

- checkpoint dimensions and parameter mapping into the joint kernel;
- exact train/validation adapter reconstruction after cleanup;
- distinct chain seeds and one numerical thread per chain;
- fixed MCMC controls, scalar and block diagnostics, Rhat/ESS thresholds, and
  prediction agreement across chains;
- raw and monotone-contract validation scoring with zero contract crossings;
- exAL use of the current collapsed-scale/M0 gamma strategy when an exAL case is
  ever eligible;
- immutable source/config/checkpoint hashes and continued test isolation.

The current provisional queue contains only AL cases, so exAL gamma machinery is
not part of the immediate compute surface. MCMC remains confirmatory rather than
a new model-selection grid. This document authorizes preparation and validation
of that contract, not MCMC launch.

## Implemented recovery outcome

The no-refit recovery completed all 38 cases with zero failures. Every repaired
summary now records the R63 stage, scalar compatibility alias, split anchor and
innovation scales, compact fit dimensions, elapsed time, test firewall, and
durable provenance hashes. All 38 checkpoint and source-manifest hashes verify,
and every monotone contract has zero crossings. Guarded cleanup removed all 266
reconstructible adapter matrix/row files, reducing the R63 run tree from 13.43
GiB to approximately 2.5 GiB and increasing free space from 417 GiB to 428 GiB.
No checkpoint or model evidence was removed.

The final R63 closeout selected three validation-confirmation candidates and
retained the exact R62 independent authority in the other 27 cells:

| Region/fold | R63 contract AQL | R62 independent AQL | Old joint AQL |
| --- | ---: | ---: | ---: |
| HU fold 3 | 6.148623 | 6.160662 | 6.185963 |
| PT fold 2 | 6.214642 | 6.237120 | 6.244149 |
| SI fold 3 | 7.294092 | 7.296728 | 7.331182 |

Stage-R64 then probed all three RDS checkpoints directly. Their formats,
case identifiers, finite beta/alpha/sigma states, dimensions, seven-quantile
grids, split RHS controls, and hashes match the frozen contract. It generated a
12-chain seed plan and no launch YAML. The three candidates are AL, so the
collapsed exAL gamma kernel is implemented but inactive for this queue.

The production launch remains blocked for three evidence-backed reasons:

1. the cleaned train/validation adapters have not yet been deterministically
   rebuilt and replayed against their retained X/y/row hashes;
2. no dedicated PriceFM runner maps these checkpoints into the genuine joint
   kernel while preserving split RHS controls and resumable chain artifacts;
3. the current prototype rebuilds a large sparse stacked design inside each
   MCMC iteration and has no production-scale timing evidence.

For 2,000 iterations and four chains per candidate, linear scaling from the VB
runtime alone suggests approximately 63.8 hours per PT chain, 109.0 hours per SI
chain, and 139.9 hours per HU chain. These are planning heuristics, not MCMC
benchmarks. The frozen campaign must not launch until the exact production runner
is implemented and benchmarked without changing the statistical target.

## Final evidence gate

After successful joint-MCMC diagnostics, freeze posterior prediction artifacts
and open test once for audit. A candidate may enter a registry/article review
only if it beats both the authoritative independent QDESN result and cached
PriceFM on the same test contract, passes the full seven-quantile and harm guards,
and has a complete reproducibility manifest. Otherwise retain the independent
authority. Article, registry, main, and Overleaf changes remain outside this
task branch and require an integration handoff.
