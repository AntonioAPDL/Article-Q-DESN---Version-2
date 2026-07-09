# PriceFM Stage-Q near-miss refinement, 2026-06-26

Stage Q follows the completed Stage-P seven-quantile confirmation over the
Stage-O conservative median promotion queue.  Stage P showed one clear local
Q-DESN win over cached fold-aligned PriceFM (`SE_4`, fold 1), two close losses
(`NL`, fold 3 and `RO`, fold 1), and four rows that still lag PriceFM.

The objective of Stage Q is to refine only the close rows before any article
surface promotion.  The run is deliberately median-only and validation-selected:
test metrics remain audit-only, and any Stage-Q winner must pass a later
seven-paper-quantile confirmation before it can replace an article-facing
decision.

## Inputs

- Stage-P comparison flags:
  `application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_p_promotions_20260626/selected_competitiveness_flags.csv`
- Stage-P median registry:
  `application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_p_quantile_confirmation_registry.csv`
- Current Stage-M decision surface:
  `application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv`

## Decision rules

- `promote_article_candidate`: Stage-P local Q-DESN beats cached PriceFM on
  the seven paper quantiles.  This row is frozen as evidence and is not refit in
  Stage Q.
- `near_miss_refine`: Stage-P is close to PriceFM, using the generated
  comparison label or default gates `delta_abs <= 0.35` or `delta_rel <= 0.05`.
  These rows are priority 0.
- `optional_modest_gap_refine`: modest gaps that may be useful after priority 0,
  using default gates `delta_abs <= 0.55` or `delta_rel <= 0.08`.  These rows
  are priority 1 and are not launched until priority 0 is inspected.
- `do_not_promote_yet`: all other Stage-P rows.

## Stage-Q grid

Tracked preparer:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/76_prepare_pricefm_stage_q_nearmiss_refinement.py
```

Ignored generated grid:

```text
application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_q_nearmiss_refinement_20260626.yaml
```

Ignored authoritative plan root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_q_nearmiss_refinement_plan_20260626/
```

Ignored run root:

```text
application/data_local/pricefm/runs/pricefm_stage_q_nearmiss_refinement_20260626/
```

## Search scope

Priority 0 targets:

- `NL`, fold 3
- `RO`, fold 1

The search perturbs the Stage-P graph Q-DESN geometry around:

- graph degree 1 versus 2;
- lag windows `72`, `96`, `128`, `144`, and `192`;
- `alpha`, `rho`, and input scale;
- D1, D2, and D3 reservoir capacities;
- a small number of targeted interaction checks.

Priority 1 currently contains only optional modest-gap rows and should wait
until priority 0 is summarized.

## Guardrails

- Selection remains validation AQL only.
- Test metrics are audit-only.
- Current Stage-M article decision surface is not mutated.
- No Stage-Q candidate is promoted without later seven-quantile confirmation.
- Artifact hygiene removes `.rds`, `.rda`, `.RData`, and `.rdata` model objects
  after successful cells.
- Generated configs, metrics, figures, logs, and launch files remain under
  ignored `application/data_local/pricefm/` paths.

## Validation

Focused test:

```sh
application/data_local/pricefm/venv/bin/python \
  -m pytest application/tests/test_pricefm_stage_q_nearmiss_refinement.py -q
```

The test verifies Stage-P decision classification, priority assignment, median
grid generation, nonmutation of Stage-M, and artifact-hygiene wiring.

## Launch sequence

Dry-run gate:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_q_nearmiss_refinement_20260626.yaml \
  --priorities 0 \
  --experiment-jobs 1 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run true \
  --resume true \
  --force false
```

Real priority-0 launch:

```sh
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/13_run_desn_experiment_grid.py \
  --grid-config application/data_local/pricefm/configs/pricefm_desn_experiment_grid_stage_q_nearmiss_refinement_20260626.yaml \
  --priorities 0 \
  --experiment-jobs 12 \
  --cell-jobs 1 \
  --build-windows true \
  --dry-run false \
  --resume true \
  --force false
```

## Closeout criteria

After priority 0 completes:

1. Confirm all cells completed and no binary fit artifacts remain.
2. Summarize median validation winners for `NL` fold 3 and `RO` fold 1.
3. Compare audit test AQL against Stage-P and cached PriceFM.
4. Queue Stage-R seven-quantile confirmation only for validation-selected rows
   that plausibly improve the Stage-P near misses.
5. Leave priority 1 unlaunched unless priority 0 suggests the modest-gap path is
   worth the additional compute.

## Completed closeout

Priority 0 completed cleanly, but did not rescue either near miss.  The
tracked closeout is:

```text
docs/implementation_notes/pricefm_stage_q_nearmiss_refinement_closeout_20260626.md
```

Decision:

- no Stage-Q candidate is promoted;
- Stage-M remains unchanged;
- Stage-Q priority 1 remains unlaunched;
- the next step is a validation/test transfer and horizon-block diagnostic
  stage before any new broad rescue grid.
