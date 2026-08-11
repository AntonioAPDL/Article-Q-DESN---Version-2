# PriceFM Stage-R51 to R54 exAL collapsed-M0 campaign

## Objective

Re-estimate every exAL model currently selected on the authoritative PriceFM
region/fold surface using the exact collapsed scale-shape M0 transition. The
campaign changes inference only. It retains the case-specific information set,
reservoir, lag window, depth, units, dynamics, RHS_NS prior, split, and seven
paper quantiles selected by the historical validation workflow.

## Frozen scope

| Item | Contract |
|---|---:|
| Authoritative region/fold rows | 114 |
| Eligible exAL rows | 87 |
| Excluded AL rows | 27 |
| Quantiles per case | 7 |
| Independent chains | 4 |
| Production chain jobs | 2,436 |
| Warmup per chain | 500 |
| Retained draws per chain | 500 |
| M0 method | `m0_v_collapsed_support_logit` |
| exdqlm commit | `10ca8e356ff445f600c4eee15f36db8a69330016` |

The 27 AL rows are not converted because the collapsed M0 transition is
exAL-only. Historical search candidates that are not selected in the current
registry are outside scope.

## Pipeline

1. `181_freeze_pricefm_stage_r51_exal_m0_authority.py` joins the current
   114-row authority with the historical specification atlas. It freezes the
   87 exact exAL designs, records the 27 AL exclusions, reconstructs selected
   seven-quantile child lineage, and hashes every source contract.
2. `182_prepare_pricefm_stage_r52_r53_exal_m0_launch.py` writes one adapter and
   replay contract per region/fold and four M0 chain contracts per paper
   quantile. It is the only stage that materializes the launch configuration.
3. `183_prepare_pricefm_stage_r52_exal_m0_case.R` rebuilds the adapter and
   requires exact X, y, row, and feature-map hashes. It then regenerates a
   normal-to-AL-to-exAL VB start for each quantile and records replay metrics.
4. `184_run_pricefm_stage_r53_exal_m0_chain.R` consumes the explicit VB state,
   verifies that the package records the M0 transition, and writes compact
   chain draws, scalar diagnostics, predictions, and an atomic success marker.
5. `185_launch_pricefm_stage_r53_exal_m0.py` runs one process per unused
   physical core, forces all numerical thread pools to one, and resumes only
   incomplete jobs. It can recognize one externally active replay without
   duplicating it. The adapter/replay phase must finish before chains start.
6. `186_closeout_pricefm_stage_r54_exal_m0.R` selects complete seven-quantile
   bundles using validation AQL only. It then audits the frozen test split
   against current authoritative Q-DESN and cached PriceFM.

## Promotion contract

An internal Q-DESN upgrade requires validation selection, replay parity,
four-chain diagnostics, chain-level prediction stability, validation harm
guards, and lower frozen-test AQL than the current authoritative Q-DESN row.
Article-level PriceFM promotion additionally requires lower frozen-test AQL
than cached PriceFM. The closeout writes review queues only. It never mutates
the registry, article, figures, tables, or prose.

## Runtime and storage

The launcher discovers busy physical cores immediately before execution and
does not share SMT siblings. Every worker sets BLAS, OpenMP, BLIS, NumExpr, and
vecLib thread counts to one. Case adapters and explicit VB states are shared by
all four chains. Latent draws are not stored; the small RHS `tau` and `c2`
scalar traces are retained for diagnostics. Heavy chain states remain
available through closeout and may be cleaned only after a reviewed promotion
and retention manifest identifies winners and reproducibility-critical files.
