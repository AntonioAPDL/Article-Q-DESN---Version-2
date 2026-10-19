# PriceFM R141 Recovery Rollout

## Purpose

R141 resumes the frozen R137 all-region PriceFM experiment after the R140
orchestration failure. It is a recovery release, not a new model search. The
scientific estimand, training-only selection rule, candidate geometry, priors,
quantiles, recursive forecast operator, path count, and comparison references
remain those of R137.

R140 stopped at the boundary between quantile-design generation and the frozen
R137 AL fitter. R140 wrote the terminal status
`completed_r140_quantile_design`, while the exact R137 fitter requires
`completed_r137_quantile_design`. The failure occurred before any independent
AL optimization began.

## Frozen scientific contract

R141 preserves the following R137 choices:

- selection uses three internal rolling-origin splits of fold-1 training data;
- the official forecast window is never used to select a specification;
- the readout is intercept plus every reservoir layer, with no direct input or
  calendar bypass;
- seven quantiles are fitted at 0.10, 0.25, 0.45, 0.50, 0.55, 0.75, and 0.90;
- the median AL fit is initialized from the selected Normal RHS fit and the
  remaining AL fits are initialized outward from the median;
- initializers do not define prior centers or otherwise change the posterior;
- AL uses the public CRAN `exdqlm` 1.1.1 API for exactly 300 iterations;
- forecasts use 500 paths and the frozen CDF-pool quantile operator;
- MCMC, exAL, joint fitting, registry mutation, article mutation, and promotion
  are not authorized by this campaign.

## Recovery boundary

The only admissible R140 imports are immutable, sealed tasks for these stages:

1. Ridge candidate scoring;
2. train-only sufficient-statistic construction;
3. Normal RHS fitting and internal scoring.

The imported task JSON, source HEAD, task hash, and completed-evidence hash are
verified before hard-link materialization in the R141 campaign. Hard links
avoid duplicating large payloads while retaining byte-identical evidence.

The four partial R140 regions are:

| Host | Region | Ridge | Statistics | RHS |
| --- | --- | ---: | ---: | ---: |
| muscat | AT | 645 | 93 | 294 |
| muscat | BG | 645 | 96 | 303 |
| jerez | BE | 645 | 99 | 312 |
| jerez | CZ | 645 | 96 | 303 |

All quantile designs and every downstream AL, scoring, final-design, full-fit,
and forecast artifact are regenerated under R141. In particular, R140
quantile-design artifacts are never imported, even when sealed, because their
terminal certificate is incompatible with the frozen fitter.

## Host execution

Each server owns two failure-isolated queues. Each queue receives 15 distinct
physical cores, for 30 physical cores per host and 60 across both hosts. Every
R, Python, BLAS, and data-table worker is constrained to one thread. A failed
regional controller blocks only its queue; the other queue continues until it
is complete or reaches a separately detected failure.

The scheduler refuses to launch when:

- source or dependency worktrees are dirty or at unexpected revisions;
- the source-matched release receipt is absent;
- the raw data hash differs;
- CPU sets overlap or do not identify 30 physical cores;
- available memory falls below 180 GiB;
- available disk falls below 80 GiB on muscat or 50 GiB on jerez.

## Verification gates

Before launch, both hosts must pass the same committed-source release suite:

- R137 parity tests;
- R140 orchestration regression tests;
- R141 recovery tests;
- immutable import and exclusion tests;
- scheduler failure-isolation tests;
- a real R141-design to R137-AL fit using CRAN `exdqlm` 1.1.1.

The initial launch is healthy only after each host has two live controllers,
the four partial regions have provenance receipts with the expected import
counts, regenerated designs carry `completed_r137_quantile_design`, and AL work
continues beyond the previously failing assertion.

## Completion and authority

The four exact R137 pilot regions (EE, HU, IT_NORD, and SK) remain frozen and
are incorporated only by the final all-region closeout. The other 34 regions
must each produce `R141_REGION_COMPLETE_NOT_PROMOTED` and sealed closeout
evidence. The combined closeout is descriptive and comparison-only. It cannot
mutate the registry, manuscript, or current authority.

No integration decision is made until all 38 regions and all 114 region-fold
cells are complete and the matched aggregate comparison has been audited.
