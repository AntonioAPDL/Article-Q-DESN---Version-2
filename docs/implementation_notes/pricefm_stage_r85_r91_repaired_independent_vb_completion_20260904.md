# PriceFM R85-R91 Repaired Independent-VB Completion Contract

## Scientific objective

Complete the PriceFM independent seven-quantile VB comparison without mixing
estimators produced by incompatible exAL initializers. Selection remains
region/fold-specific: each of the 56 cases chooses one complete AL or exAL
seven-quantile surface using validation AQL only. Test data are opened once,
after selection is frozen, and only as an audit against the authoritative
Q-DESN and cached fold-aligned PriceFM references.

This chain does not fit a joint model, run MCMC, mutate the decision registry,
or edit the article. Those actions require a later scientific decision and an
integration handoff.

## Audited starting state

| Evidence | Result | Consequence |
|---|---:|---|
| R73 AL atoms | 392/392 | Reuse; no AL refit |
| R76 exAL terminal completions | 280/294 | Old initializer is invalid |
| R76 exAL terminal failures | 14/294 | Replaced by R83 |
| R82 diagnostic controls | 3/3 passed | Structured plug-in initialization accepted |
| R83 replacements | 14/14 completed | Retain; apply final atom and case gates |
| R76 visible R82-bound failures | 169/280 | R84 cannot be authoritative |
| ExAL cases containing R76 atoms | 42/42 | All 280 R76 atoms require homogeneous refit |
| R84 provisional selection | 56 cases | Quarantined; test remains sealed |

The old initialization used a second-order Gaussian delta approximation at
`gamma = 0`, where the exAL representation contains `abs(gamma)` and is not
smooth. In the diagnostic failure, this produced negative initial xi moments;
the positivity floor then removed effective likelihood precision from the
first coefficient update. This is an estimator-provenance problem, not merely
a terminal-failure problem. Therefore even bounded-looking R76 atoms cannot be
mixed into the final surface.

## Efficiency decision

Refit exactly 280 exAL atoms. Do not refit the 392 AL atoms or the 14 R83 exAL
atoms. This is the smallest homogeneous correction:

- refitting only the 169 visibly unstable atoms would retain 111 atoms from the
  invalid initializer;
- refitting all 294 exAL atoms would duplicate the 14 R83 repairs;
- refitting AL would add no information because AL is unaffected by the exAL
  initialization defect.

Historical runtime totals imply approximately 466 core-hours for the 280-atom
campaign. At 32 one-thread workers the ideal lower bound is about 14.6 hours;
wall time may be longer because task runtimes vary.

## Frozen numerical contract

The repaired runtime is a local, versioned derivative of exact CRAN exdqlm
1.1.1:

- runtime version: `1.1.1.9004`;
- base tarball SHA-256:
  `3f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e`;
- repair label:
  `scale-aware-SPD-plus-large-n-GIG-plus-failure-diagnostics-plus-structured-plugin-init`;
- initialization: plug-in exAL moments at the AL beta/sigma warm start for the
  first CAVI coefficient update, followed by the existing structured
  gamma-grid and conditional-GIG updates.

Every atom is checked against the pre-existing R82 gates:

1. required traces are finite;
2. at least 35 structured updates are present;
3. maximum sigma is below 100;
4. final beta L2 norm is below 10 times the AL initialization norm;
5. maximum absolute gamma is below 4;
6. first state delta is below 100;
7. last-ten state and sigma deltas are below 2;
8. package, task, runner, source config, warm start, and output hashes match.

Thresholds cannot be changed after observing R87.

## Stage contract

### R85: surface-wide numerical audit

R85 reads R76, R83, and R84 without fitting or opening test. It writes a
294-row atom ledger, a case ledger, the exact 280-row R86 refit manifest, the
14-row retained-R83 ledger, gates, hashes, JSON, and a report. Its result
quarantines R84 and authorizes launch preparation only.

### R86: homogeneous launch preparation

R86 transforms the 280 hash-pinned R76 task configurations. It changes only
stage identity, output location, runtime identity, method label, and numerical
initialization. Region, fold, quantile, DESN structure, feature policy, lag
window, alpha, rho, input scale, tau0, prior, data, seed, and AL warm start are
preserved. The adapters contain only train and validation files. R86 writes no
YAML and cannot launch itself.

### R87: background refit

R87 runs one model per explicitly selected logical CPU with all numerical
thread pools fixed to one. It writes each atom atomically to a new run root,
skips only hash-valid completed atoms, and maintains atomic launch status. A
resume may rerun interrupted tasks but may not change scientific settings or
retry a numerical failure under a new rule.

### R88: numerical and provenance closeout

R88 combines the 280 R87 outputs and 14 R83 outputs into the corrected 294-atom
surface. It applies the frozen numerical contract to every atom. A case is exAL
eligible only when all seven quantiles pass. A failed case falls back to its
frozen R73 AL surface. There is no further rescue loop.

### R89: validation-only family selection

R89 computes raw original-scale seven-quantile validation AQL for each eligible
exAL case and compares it with the corresponding R73 AL AQL. One family is
selected per region/fold. The 14 AL-only cases remain AL. Monotone
rearrangement is a sensitivity analysis and cannot select a family. The final
392-atom manifest freezes coefficient, prediction, scaler, feature, row,
configuration, environment, and source hashes before test access.

### R90: sealed scoring-only test audit

R90 must not refit. It materializes the exact test design from the frozen case
configuration, scores stored beta means, and first reproduces the frozen
validation predictions. Test metrics are admissible only after coefficient
dimensions, feature order, validation rows, scalers, and validation predictions
replay within a pre-registered numerical tolerance. It compares test AQL with
both the authoritative Q-DESN and cached fold-aligned PriceFM references.
The historical authority is universally available only as case-level
seven-quantile AQL for Q-DESN and PriceFM. Some generations retain subgroup
metrics, but others point to aggregate registries or median-run geometry.
Accordingly, dual superiority is tested at case level. Candidate quantile and
horizon metrics are complete-surface diagnostics, not comparisons against
invented historical subgroup values.
The scoring worker removes regenerated `X_val`, `y_val`, `X_test`, and `y_test`
matrices after scoring, but retains their pre-cleanup hashes, the test row
ledger, predictions, validation replay, adapter manifests, and terminal hash
ledger. This bounds persistent storage while preserving deterministic replay.

### R91: promotion and integration handoff

A region/fold may enter the promotion queue only when its frozen candidate:

- has a complete finite seven-quantile test surface;
- beats both authoritative Q-DESN and cached PriceFM on test AQL;
- has complete finite metrics for all seven quantiles and all four horizon blocks;
- passes all replay, provenance, and hash gates.

R91 writes read-only decision tables, figure data, prose recommendations, and a
frozen integration handoff. It does not edit the registry or article and does
not push `main`; the integration coordinator owns those actions. If no case
passes, the valid outcome is a documented negative result with no article
mutation.

### Gated finalizer

The R87-to-R91 finalizer polls for the immutable R87 launch summary and stops
on any R87 task failure. After a clean 280/280 closeout it executes R88, R89,
and R90 preparation in order. It waits until 20 independently sampled idle
logical CPUs pass resource gates, launches one scoring-only case per CPU, and
then runs R91. Test access requires its explicit command-line authorization;
all fitting and mutation flags remain false. The finalizer cannot publish or
modify an article, registry, joint model, or MCMC result.

## Operational stops

- No test file may be present in R85-R89 adapters or manifests.
- No R76 exAL output may enter R88 or R89 as a scientific fit.
- No per-quantile or test-oracle AL/exAL mixing is allowed.
- No automatic numerical rescue follows R88.
- No joint model or MCMC is fitted in this chain.
- No registry or manuscript file is modified.
- Other lanes' CPUs, worktrees, jobs, and artifacts remain untouched.
- Generated runtime outputs remain in the ignored artifact repository.

## Completion definition

The scientific lane is complete when R91 has either produced a valid dual-
reference promotion queue or documented that the queue is empty, all scripts
and tests are committed on the dedicated branch, generated evidence is
hash-manifested, and the branch is clean and synchronized with its upstream.
