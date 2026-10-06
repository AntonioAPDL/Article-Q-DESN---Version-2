# PriceFM Stage-R99/R100 targeted recovery

Date: 2026-09-13

Lane: PriceFM only

## Purpose

Stage R99 freezes the evidence used to design a bounded recovery screen for
the 17 Central/East and Nordic regions that remain weakest under the valid R98
authority. Stage R100 implements the resulting train/validation-only normal
Ridge-to-RHS screen. It does not score the outer test period, fit quantile or
joint models, mutate the registry, or modify the article.

The full operational plan is intentionally local and ignored:

```text
local_trackers/pricefm_stage_r99_r100_targeted_recovery_execution_plan_20260913.md
```

## Evidence and decision

The immutable input authority is:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/
authoritative/pricefm_stage_r98_validity_first_authority_closeout_20260913/
pricefm_stage_r98_authoritative_registry.csv
```

Its SHA-256 is
`4cf8ff653c6bd7fc64a2992fbfb6e1df48867d1b7d840cd8544fb30a5c538cb6`.
It contains 114 complete region/fold rows across 38 regions and three folds.

R97 already evaluated the generic 240-candidate geometry bank. R100 therefore
does not repeat that search. It retains each region's exact R98 specification
as a control and shifts the bounded candidate budget toward spatial summaries,
training-derived degree-one neighbor subsets, reservoir-seed robustness, and
design-size-adjusted RHS scales.

The fixed recovery targets are:

```text
AT, BG, CZ, DE_LU, HR, HU, PL, RO, SK,
FI, NO_1, NO_2, NO_3, NO_4, NO_5, SE_2, SE_4
```

## R99 outputs

R99 writes reproducible CSV, JSON, and Markdown evidence beneath:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/
audits/pricefm_stage_r99_targeted_recovery_20260913
```

The completed R99 source-manifest hash is
`53a78c088bbe39e56a6216a30a3dea22bd5183a1bd59e0f63c114231522a5d64`.
The audit validates R98 completeness, raw training-period regime shifts,
training-only neighbor rankings, retained R97 ranking coverage, comparator
provenance, the target queue, and mechanism gates.

The PriceFM comparator is labelled precisely as the cached PriceFM Phase-I
checkpoint replay. It is not represented as a complete full-shot reproduction.

## R100 search contract

Each target receives exactly 240 deterministic normal Ridge candidates:

| Feature policy | Candidates |
|---|---:|
| target only | 12 |
| graph summary mean | 48 |
| graph summary mean and standard deviation | 72 |
| selected-neighbor spread summary | 84 |
| direct graph k-hop | 24 |

The bounded structural support is:

```text
lag_window: 96, 168, 240
depth: 1, 2, 3
units: [48], [64], [96], [128], [48,48], [64,64], [80,80],
       [96,48], [120,64], [40,40,40], [48,48,48], [64,64,64],
       [96,64,48]
alpha: 0.25, 0.35, 0.45, 0.55
rho: 0.82, 0.90, 0.95
input_scale: 0.15, 0.20, 0.35, 0.50
state_output: final_layer
```

Candidate selection uses only inner folds 101, 102, and 103. Their validation
windows all end before 2024-09-01. The outer test period and outer-fold scores
are excluded from configuration, ranking, and winner freezing.

After Ridge ranking, only the top 30 candidates per region advance. Each is
fitted with normal RHS_NS at three scales:

```text
tau_ref = tau_R98 * sqrt(p_R98 / p_candidate)
tau0 = {0.25, 1, 4} * tau_ref
```

This gives 4,080 Ridge experiments and at most 1,530 RHS experiments, each
evaluated on three inner validation cells. R100 freezes one provisional normal
winner per region and then stops.

## Compute and storage controls

The production controller requires the exact logical CPU set
`0-24,32-56`. On Muscat these are both hardware threads of 25 physical cores.
Every model is pinned to one logical CPU and all supported numerical thread
variables are set to one. Seven physical cores remain outside the campaign.

Launch admission requires two idle-CPU measurements, at least 250 GiB of free
disk, at least 64 GiB of available memory, unchanged source hashes, and a clean
pushed `work/pricefm-*` task branch. Disk and memory floors are also checked
before every model. Completed model binaries and adapter matrices are removed
only after their train/validation metrics and method summaries are validated
and hashed.

## Reproducibility entry points

```bash
python application/scripts/pricefm/331_audit_pricefm_stage_r99_targeted_recovery.py
python application/scripts/pricefm/332_prepare_pricefm_stage_r100_targeted_normal_screen.py
python application/scripts/pricefm/333_orchestrate_pricefm_stage_r100_targeted_normal_screen.py \
  --code-root "$PWD" \
  --workers 50 \
  --cpu-list 0-24,32-56 \
  --approval-token RUN_PRICEFM_R100_TARGETED_NORMAL_RECOVERY
```

The launch-prep source manifest has SHA-256
`6f1d6cf52204fae9ad370d47eeede7994b061a16ce30f33b074472e2cacfc857`.

## Downstream boundary

R101 may be designed only after R100 freezes complete normal winners. It will
need a separate gate for independent seven-quantile AL and repaired structured
exAL VB fits using one region-level DESN/tau specification across folds and
quantiles. Test scoring, registry replacement, article assets, joint fitting,
and MCMC remain blocked.
