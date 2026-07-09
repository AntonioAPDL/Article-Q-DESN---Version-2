# PriceFM Stage-R Selection Diagnostics Plan

Date: 2026-06-27

## Purpose

Stage Q is complete and clean, but it is negative evidence.  The priority-0
near-miss refinement did not rescue `NL` fold 3 or `RO` fold 1, and the
validation-selected candidates transferred poorly to the test window.  The next
stage should therefore diagnose why validation selection is unreliable before
spending compute on another broad Q-DESN search.

Stage R is a diagnostic and planning stage.  It should not fit DESN/Q-DESN
models, mutate the Stage-M article decision surface, or launch Stage-Q
priority-1 rows.  Its job is to convert the existing run history into a
reproducible failure-mode map and a smaller, justified next launch manifest.

## Current Evidence

Authoritative Stage-Q closeout:

```text
application/data_local/pricefm/authoritative/pricefm_stage_q_nearmiss_refinement_closeout_20260626/
docs/implementation_notes/pricefm_stage_q_nearmiss_refinement_closeout_20260626.md
```

Stage-Q health:

| Quantity | Value |
|---|---:|
| Priority-0 experiments | 84 |
| Launch rows | 96 / 96 |
| Nonzero return codes | 0 |
| Metric files | 84 |
| Binary fit artifacts | 0 |
| Stage-M surface changed | FALSE |
| Promotion recommended | FALSE |
| Priority-1 launch recommended | FALSE |

Stage-Q target decisions:

| Region | Fold | PriceFM AQL | Stage-P AQL | Stage-Q validation-selected test AQL | Stage-Q test-oracle AQL | Decision |
|---|---:|---:|---:|---:|---:|---|
| NL | 3 | 6.4117 | 6.5443 | 8.1305 | 7.8058 | do not promote |
| RO | 1 | 7.5680 | 7.8900 | 10.0195 | 9.5057 | do not promote |

Selection transfer:

| Region | Fold | Candidates | Spearman validation/test rank | Validation-selected regret | Selected vs Stage-P | Selected vs PriceFM |
|---|---:|---:|---:|---:|---:|---:|
| NL | 3 | 84 | -0.0163 | 0.3247 | +1.5862 | +1.7188 |
| RO | 1 | 84 | 0.0938 | 0.5138 | +2.1295 | +2.4516 |

This is not an operational failure.  The run completed, cleaned artifacts, and
produced finite metrics.  It is a scientific selection failure: median
validation AQL did not identify test-strong rows, and even the test-oracle
Stage-Q rows were worse than Stage P and PriceFM.

## Existing Inputs To Reuse

Stage R should consume these existing artifacts rather than regenerate fits.

| Source | Role |
|---|---|
| `application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv` | Current 42-row article decision surface |
| `application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/diagnostic_source_summary.csv` | Validation/test transfer summaries for Stage J/K/L |
| `application/data_local/pricefm/authoritative/pricefm_stage_m_validation_test_alignment_20260624/diagnostic_validation_test_rows.csv` | Candidate-level validation/test transfer rows |
| `application/data_local/pricefm/authoritative/pricefm_stage_m_split_diagnostics_20260624/split_response_contrasts.csv` | Train/validation/test response-shift diagnostics |
| `application/data_local/pricefm/authoritative/pricefm_stage_n_underperformance_closeout_20260625/validation_selected_closeout.csv` | Stage-N validation-selected rows |
| `application/data_local/pricefm/authoritative/pricefm_stage_n_underperformance_closeout_20260625/selection_instability_audit.csv` | Stage-N validation-selected versus test-oracle differences |
| `application/data_local/pricefm/authoritative/pricefm_stage_n_underperformance_closeout_20260625/horizon_gap_summary.csv` | Stage-N horizon-block test-oracle gaps |
| `application/data_local/pricefm/authoritative/pricefm_stage_o_selection_promotion_hardening_20260626/stage_o_selection_rule_audit.csv` | Selection-rule sensitivity audit |
| `application/data_local/pricefm/authoritative/pricefm_phase1_vs_stage_p_promotions_20260626/selected_competitiveness_flags.csv` | Seven-paper-quantile confirmation outcomes |
| `application/data_local/pricefm/authoritative/pricefm_stage_q_nearmiss_refinement_closeout_20260626/*.csv` | Stage-Q closeout, family, horizon, and transfer diagnostics |

Important existing scripts:

| Script | Reuse |
|---|---|
| `application/scripts/pricefm/68_summarize_pricefm_current_decision_surface.py` | Decision-surface summary conventions |
| `application/scripts/pricefm/69_audit_pricefm_validation_test_alignment.py` | Validation/test alignment pattern |
| `application/scripts/pricefm/73_prepare_pricefm_stage_n_underperformance_broad_search.py` | Existing broad-search metadata conventions |
| `application/scripts/pricefm/74_closeout_pricefm_stage_n_underperformance.py` | Candidate/horizon closeout pattern |
| `application/scripts/pricefm/75_harden_pricefm_stage_o_selection_promotions.py` | Conservative promotion and paper-quantile queue logic |
| `application/scripts/pricefm/76_prepare_pricefm_stage_q_nearmiss_refinement.py` | Stage-Q near-miss grid construction |
| `application/scripts/pricefm/77_closeout_pricefm_stage_q_nearmiss_refinement.py` | Clean closeout and artifact-hygiene pattern |

## Diagnosis

## Comprehensive Audit, 2026-06-27

The plan above was re-audited against the current authoritative outputs before
implementation.  The audit confirms that Stage R is the right next step and
that another immediate grid launch is not justified.

### A. Current decision surface

Current Stage-M article surface:

```text
application/data_local/pricefm/authoritative/pricefm_stage_m_current_decision_surface_20260624/current_decision_surface_table.csv
```

The selected panel has 42 region/fold rows.  Q-DESN/DESN rows beat cached
fold-aligned PriceFM in 25 rows, with mean delta `-0.328` AQL.  The aggregate
surface is useful, but it hides a strong information-set split:

| Information set | Rows | Wins | Mean delta | Median delta |
|---|---:|---:|---:|---:|
| PriceFM graph inputs | 27 | 20 | -0.7191 | -0.6768 |
| Target-only | 15 | 5 | 0.3772 | 0.3146 |

The worst unresolved rows are not homogeneous:

| Region | Fold | Current label | Information set | Delta AQL | Relative delta |
|---|---:|---|---|---:|---:|
| LT | 1 | PriceFM better | target-only | 1.9907 | 0.1594 |
| HU | 2 | PriceFM better | graph inputs | 1.3619 | 0.1860 |
| SK | 3 | PriceFM better | graph inputs | 1.3029 | 0.1736 |
| FI | 1 | PriceFM better | target-only | 1.3014 | 0.1406 |
| AT | 3 | PriceFM better | target-only | 0.8915 | 0.1320 |
| SE_4 | 1 | PriceFM better | target-only | 0.7799 | 0.1013 |
| RO | 1 | PriceFM better | graph inputs | 0.7293 | 0.0964 |
| PL | 3 | PriceFM better | target-only | 0.7130 | 0.0927 |
| RO | 3 | PriceFM better | graph inputs | 0.4331 | 0.0507 |
| NL | 3 | PriceFM better | graph inputs | 0.3736 | 0.0583 |

Implication: a single "bigger reservoir" prescription cannot be optimal.  The
next action must distinguish target-only parity gaps from graph-input rows that
already have graph information but still lose.

### B. Validation/test transfer

Current Stage-M validation/test gaps remain large:

| Current label | Rows | Mean absolute validation/test gap | Median absolute gap | Mean signed gap |
|---|---:|---:|---:|---:|
| Local beats PriceFM | 25 | 1.8141 | 1.7222 | -0.1081 |
| Local close to PriceFM | 6 | 2.1344 | 2.6602 | -0.8258 |
| PriceFM better | 11 | 1.7032 | 1.0617 | 0.5665 |

Earlier diagnostic sources also show weak transfer:

| Source | Rows | Region/folds | Validation win rate | Test win rate | Disagree rate | Mean validation delta | Mean test delta |
|---|---:|---:|---:|---:|---:|---:|---:|
| Stage J priority-0 closeout | 9 | 9 | 0.8889 | 0.2222 | 0.6667 | -0.5010 | 0.5599 |
| Stage K regularized graph | 87 | 8 | 0.0345 | 0.3908 | 0.3563 | 1.3033 | 1.3599 |
| Stage L SI seed expansion | 8 | 1 | 0.5000 | 1.0000 | 0.5000 | -0.0540 | -1.7260 |

Stage N then showed that validation-selected rows were often not the test-best
rows.  Among 17 region/folds, the validation-selected and test-oracle
candidates were almost never the same.  Seven rows had validation-selected
test gains, but none beat PriceFM; nine rows were vetoed by the test guardrail.

Stage O tested alternative validation-only selection summaries.  Robust ranks
were marginally better than pure validation AQL but still did not beat PriceFM:

| Rule | Region/folds | Test improvements | Beat PriceFM | Strict promotions | Mean test delta vs current | Mean test delta vs PriceFM |
|---|---:|---:|---:|---:|---:|---:|
| validation AQL min | 17 | 7 | 0 | 7 | 0.0534 | 3.0083 |
| validation MAE min | 17 | 7 | 0 | 7 | 0.0534 | 3.0083 |
| validation RMSE min | 17 | 6 | 0 | 5 | 0.3481 | 3.3029 |
| robust rank | 17 | 8 | 0 | 8 | 0.0014 | 2.9563 |

Implication: Stage R should not merely re-run the old median validation AQL
rule.  It must evaluate whether any validation-only rule has credible transfer
before a new grid is planned.

### C. Stage-P and Stage-Q confirm the near-miss boundary

Stage P confirmed seven paper quantiles for seven Stage-N candidates:

| Label | Rows | Mean delta | Median delta |
|---|---:|---:|---:|
| Local beats PriceFM | 1 | -0.4529 | -0.4529 |
| Local close to PriceFM | 2 | 0.2273 | 0.2273 |
| Local lags PriceFM | 4 | 0.8036 | 0.6903 |

Stage Q then refined the two close losses.  It failed:

| Region | Fold | Candidates | Spearman validation/test | Selected regret | Selected vs Stage-P | Selected vs PriceFM | Oracle vs Stage-P | Oracle vs PriceFM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| NL | 3 | 84 | -0.0163 | 0.3247 | 1.5862 | 1.7188 | 1.2615 | 1.3941 |
| RO | 1 | 84 | 0.0938 | 0.5138 | 2.1295 | 2.4516 | 1.6157 | 1.9378 |

Implication: Stage-Q priority 1 is scientifically blocked.  Priority 0 tested
the most plausible near-miss rescue family and found that the whole local
search neighborhood was worse than Stage P and PriceFM.

### D. Split shift is relevant but not sufficient

The split diagnostics show validation/test distribution differences, but they
do not explain everything alone.  On average, PriceFM-better rows have a
positive test-minus-validation response mean shift and a lower validation/test
standard-deviation ratio than local-win rows.  Stage R should include these
fields as covariates in the scorecard, not as a standalone launch rule.

| Current label | Mean test-minus-validation mean shift | Mean test/validation SD ratio | Mean test-minus-validation median shift |
|---|---:|---:|---:|
| Local beats PriceFM | -0.0463 | 0.9548 | -0.0261 |
| Local close to PriceFM | 0.0311 | 0.9297 | 0.0347 |
| PriceFM better | 0.1317 | 0.8902 | 0.0735 |

Implication: a good Stage-S search, if any, should account for split shift
when choosing rows and when interpreting validation results.

## Critical Assessment Of Alternatives

| Option | Decision | Reason |
|---|---|---|
| Launch Stage-Q priority 1 | Reject | Priority 0 already falsified the same near-miss search family; priority 1 would spend more compute on weaker rows. |
| Run another broad capacity/alpha/rho sweep | Reject for now | Stage-Q and Stage-N show transfer instability, not a simple missing-capacity pattern. |
| Promote test-oracle candidates | Reject | Violates validation-only selection contract and Stage-Q test-oracle rows still failed against Stage P/PriceFM. |
| Patch Stage-M manually | Reject | Stage-M is the current article surface and must only change through audited selection and paper-quantile confirmation. |
| Move directly to seven quantiles for all unresolved rows | Reject for now | Seven-quantile confirmation is expensive and should only follow a credible median/selection signal. |
| Implement Stage R diagnostic pass | Accept | Reuses existing expensive outputs, quantifies failure modes, and creates a defensible compute gate for any Stage-S launch. |

## Improved Stage-R Implementation Strategy

Stage R should be built as a deterministic evidence compiler with no fitting
side effects.  The implementation should follow this pipeline:

1. **Input manifest.** Read all Stage-M/N/O/P/Q inputs, record path, SHA-256,
   row count, column count, required-column status, and role.
2. **Region/fold scorecard.** Start from the 42-row Stage-M surface and add
   validation/test gap, split-shift summaries, Stage-N/O/P/Q status, graph
   policy, paper-quantile confirmation status, and current unresolved tier.
3. **Candidate transfer normalization.** Harmonize candidate rows from Stage
   J/K/L/N/O/Q into one schema, with explicit `test_metrics_role = audit_only`
   where applicable.
4. **Transfer diagnostics.** Compute validation/test win rates, disagreement
   rates, Spearman rank correlations where candidate groups are large enough,
   and test regret for validation-selected rows.
5. **Horizon diagnostics.** Merge Stage-N and Stage-Q horizon-block evidence,
   label early/mid/late weakness, and identify whether candidate choice changes
   by horizon block.
6. **Information-set parity.** Distinguish target-only underperformers from
   graph-input underperformers.  Target-only rows can justify graph-parity
   exploration; graph-input rows require geometry/selection evidence instead.
7. **Failure-mode assignment.** Assign one primary label per region/fold and
   optional secondary labels.  Labels must be deterministic and test-covered.
8. **Compute gate.** Write a recommendation table that can say `no_launch`.
   Launch configs are not written in Stage R.

This is more efficient than another grid because the most expensive
information already exists.  Stage R turns that information into a smaller
decision problem before any new fits.

## Efficient Screening Policy For Stage-S

If Stage R recommends a Stage-S launch, it should use a narrow candidate pool
with explicit gates.

### Row eligibility

A row is eligible for Stage-S only if at least one of the following is true:

- it is target-only and has no comparable graph-neighbor parity attempt;
- it has aligned validation/test evidence from a prior source;
- it has a specific horizon-block weakness that a different selection rule can
  target;
- it is close enough to PriceFM that a small rescue is plausible.

A row is not eligible if:

- Stage-Q already tested the same near-miss family and both selected and
  oracle rows failed badly;
- PriceFM is far ahead and no historical Q-DESN family approached it;
- the only proposal is more capacity without a diagnosed failure mode;
- the proposed action would require using test metrics for selection.

### Candidate family design

Stage-S should use failure-mode-specific families:

| Failure mode | Candidate family |
|---|---|
| `graph_parity_gap` | degree-1 and degree-2 graph inputs, small seed check, no large depth sweep first |
| `graph_geometry_gap` | graph degree/input aggregation and modest input-scale variants |
| `late_horizon_gap` | horizon-block-aware selection audit first; only then horizon-weighted median grid |
| `selection_instability` | seed/stability screen or robust validation rank, not larger reservoirs |
| `pricefm_far_ahead` | no launch unless a new model class or information set is introduced |

### Priority and parallelism

| Priority | Launch condition | Size | Parallelism |
|---|---|---:|---|
| 0 | Strong Stage-R evidence and plausible PriceFM gap | Small, hand-audited | 8-20 experiment jobs, `cell_jobs = 1` |
| 1 | Only after priority 0 transfers | Moderate | Launch after closeout |
| 2 | Exploratory seeds/capacity | Tiny diagnostic sample | Never before priority 0 closeout |

Keep the existing artifact hygiene: delete `.rds`, `.rda`, `.RData`, and
`.rdata` after metrics and figures are written.  Commit no generated run
artifacts; keep outputs under ignored `application/data_local/pricefm/` roots
unless they are compact documentation summaries.

## Revised Implementation Checklist

### Planning and reproducibility

- [ ] Add the Stage-R diagnostic script with explicit default input paths.
- [ ] Record input hashes and source roles in `stage_r_input_manifest.csv`.
- [ ] Record repo branch, HEAD, dirty state, and command line in `summary.json`.
- [ ] Ensure output paths are deterministic and ignored by git.
- [ ] Ensure no launch YAML or model-fit command is produced by default.

### Data contract checks

- [ ] Validate required columns for each input.
- [ ] Validate finite metrics.
- [ ] Validate unique keys for one-row-per-region/fold tables.
- [ ] Validate Stage-Q `run_clean = true`.
- [ ] Validate Stage-Q `priority1_launch_recommended = false`.
- [ ] Validate Stage-M row count remains 42.

### Analysis outputs

- [ ] Produce `stage_r_region_fold_scorecard.csv`.
- [ ] Produce `stage_r_candidate_transfer_rows.csv`.
- [ ] Produce `stage_r_selection_transfer_by_source.csv`.
- [ ] Produce `stage_r_horizon_block_diagnostics.csv`.
- [ ] Produce `stage_r_information_set_parity.csv`.
- [ ] Produce `stage_r_failure_mode_assignments.csv`.
- [ ] Produce `stage_r_next_grid_recommendations.csv`.
- [ ] Produce `stage_r_summary.md`.

### Tests

- [ ] Missing input fails clearly.
- [ ] Duplicate key fixtures fail clearly.
- [ ] Non-finite metric fixtures fail clearly.
- [ ] Stage-Q false launch recommendation is enforced.
- [ ] Heterogeneous source rows normalize to the common transfer schema.
- [ ] Test-oracle rows are marked audit-only.
- [ ] Failure-mode assignment is deterministic.
- [ ] The script does not write launch YAML by default.

### Stop conditions

- [ ] Stop if any authoritative input is missing or inconsistent.
- [ ] Stop if Stage-Q health is not clean.
- [ ] Stop if Stage-M would be mutated.
- [ ] Stop if Stage-R cannot distinguish action classes better than another
  blind sweep.
- [ ] Stop if the only recommended next action depends on test metrics for
  selection.

## Optimality Decision

After the audit, the optimal next move remains Stage R, but with stricter
scope:

1. implement diagnostics only;
2. use no new fitting compute;
3. do not launch Stage-Q priority 1;
4. do not write Stage-S launch configs by default;
5. produce a row-level action table that can explicitly recommend no launch;
6. only design Stage S after Stage R identifies a failure mode and a
   validation-only screening rule with better support than the current median
   validation AQL rule.

This keeps the workflow scientifically conservative, computationally
efficient, reproducible, and aligned with the current PriceFM article evidence.

### 1. Do not launch Stage-Q priority 1

Stage-Q priority 0 was already the strongest near-miss test.  It explored
graph degree, lag window, depth, reservoir units, alpha, rho, input scale, and
targeted interactions around the two closest Stage-P losses.  The search did
not contain hidden promotable rows: even the test-oracle candidates were worse
than Stage P and PriceFM.  Launching the optional modest-gap priority-1 rows
would repeat the same search family on weaker targets.

Decision: freeze Stage-Q priority 1 as unlaunched unless a later diagnostic
stage identifies a specific, evidence-backed reason to revive a subset.

### 2. The failure mode is not simply capacity

Stage-Q best-family results show that local perturbations of capacity, depth,
alpha, rho, and input scale rarely improved test AQL enough, and D2/D3 variants
often worsened transfer.  The middle and late horizon blocks dominated the
losses:

- NL selected candidate: horizon-block AQL `5.2164`, `8.3928`, `9.6636`,
  `9.2492`.
- RO selected candidate: horizon-block AQL `6.0451`, `11.4281`, `12.5826`,
  `10.0222`.

Decision: do not design the next grid as another undifferentiated
capacity/alpha/rho sweep.

### 3. The selection rule is too fragile

The current selection rule is median validation AQL only.  Stage-Q rank
correlations between validation and test were nearly zero, while earlier
Stage-M diagnostics already showed substantial disagreement:

- Stage J: validation win rate `0.889`, test win rate `0.222`, disagreement
  `0.667`.
- Stage K: validation win rate `0.034`, test win rate `0.391`, disagreement
  `0.356`.
- Stage L: validation win rate `0.500`, test win rate `1.000`, disagreement
  `0.500`.

Decision: the next useful compute should be preceded by a selection rule audit
that compares validation AQL, validation horizon blocks, stability across
seeds, and split-shift indicators.

### 4. Input information-set parity matters

The current Stage-M surface is much stronger for rows using PriceFM graph
inputs than target-only rows.  Graph-neighbor rows win more often and have a
more favorable mean delta than target-only rows.  However, Stage-Q also shows
that merely adding or perturbing graph inputs is not enough: graph-degree and
input-scale variants still failed for NL fold 3 and RO fold 1.

Decision: Stage R should separate "no graph parity" failures from "graph
present but wrong selection/geometry" failures.

### 5. Paper-quantile confirmation remains mandatory

Median-only screens are useful for compute triage, but final article changes
must be confirmed on the seven PriceFM paper quantiles.  Stage P correctly
prevented median-only rows from directly mutating the article surface.

Decision: no Stage-R recommendation may promote anything directly.  It may only
propose a later median grid or a seven-quantile confirmation queue.

## Stage-R Deliverable

Implement a new diagnostic script, not a fit launcher:

```text
application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py
```

Default ignored output root:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r_selection_diagnostics_20260627/
```

Required outputs:

| Output | Purpose |
|---|---|
| `stage_r_input_manifest.csv` | Paths, hashes, row counts, and roles for every source CSV |
| `stage_r_region_fold_scorecard.csv` | One row per current region/fold with decision label, current delta, validation/test gap, split shift, graph policy, and priority |
| `stage_r_selection_transfer_by_source.csv` | Source-level validation/test transfer summary across Stage J/K/L/N/O/Q |
| `stage_r_candidate_transfer_rows.csv` | Harmonized candidate-level validation/test rows |
| `stage_r_horizon_block_diagnostics.csv` | Horizon-block attribution for Stage N/Q where available |
| `stage_r_information_set_parity.csv` | Target-only versus graph-neighbor status and performance gaps |
| `stage_r_failure_mode_assignments.csv` | Region/fold labels such as `selection_instability`, `late_horizon_gap`, `graph_parity_gap`, `pricefm_far_ahead`, `stable_promising` |
| `stage_r_next_grid_recommendations.csv` | Diagnostic-only proposed actions; no automatic launch |
| `stage_r_summary.md` | Compact human-readable diagnosis and next-stage recommendation |
| `summary.json` | Machine-readable status and guardrails |

## Stage-R Checklist

### A. Synchronize and protect state

- [ ] Verify branch, HEAD, upstream, and dirty state.
- [ ] Confirm Stage-Q closeout exists and `run_clean = true`.
- [ ] Confirm no PriceFM fit processes from this work are running.
- [ ] Confirm Stage-M surface is not modified by Stage-R.

### B. Input validation

- [ ] Check each input CSV exists, is non-empty, and has required columns.
- [ ] Record relative path, SHA-256, row count, and column count.
- [ ] Verify unique `(region, fold)` keys where required.
- [ ] Verify all AQL, MAE, RMSE, delta, and split-shift fields are finite.
- [ ] Verify Stage-Q `priority1_launch_recommended = false`.
- [ ] Verify Stage-Q promotions are all false.

### C. Harmonized candidate transfer table

- [ ] Normalize Stage J/K/L/N/O/Q candidate rows into a single schema:
  `source`, `region`, `fold`, `experiment_id`, `method_id`, `feature_policy`,
  `graph_degree`, `validation_AQL`, `test_AQL`, `current_test_AQL`,
  `pricefm_AQL`, `validation_delta`, `test_delta`, `test_delta_vs_pricefm`,
  `candidate_family`, `selection_rule`, and `test_metrics_role`.
- [ ] Mark whether the row was validation-selected, test-oracle audit, or
  source-level diagnostic.
- [ ] Mark whether test metrics were audit-only.
- [ ] Never use test metrics to select a promotable candidate.

### D. Selection-transfer diagnostics

- [ ] Compute source-level validation and test win rates.
- [ ] Compute disagreement rates.
- [ ] Compute validation/test Spearman rank correlation where enough rows
  exist per `(source, region, fold)`.
- [ ] Compute validation-selected test regret versus test-oracle audit where
  available.
- [ ] Flag sources/families where validation rank is uninformative or reversed.

### E. Horizon-block diagnostics

- [ ] Harmonize Stage-N and Stage-Q horizon-block rows.
- [ ] Identify whether losses are early (`1-24`), middle (`25-72`), late
  (`73-96`), or broad across all horizons.
- [ ] Compare validation-selected and test-oracle horizon-block profiles.
- [ ] Flag rows where a horizon-specific rule would select differently.

### F. Information-set parity diagnostics

- [ ] Classify rows as target-only, graph degree 1, graph degree 2, or other.
- [ ] Compare current Stage-M deltas by information set.
- [ ] For underperforming rows, distinguish missing graph inputs from graph
  geometry/selection failures.
- [ ] Record PriceFM graph hash when present.

### G. Failure-mode assignments

Assign exactly one primary failure mode and optional secondary labels:

| Label | Meaning |
|---|---|
| `selection_instability` | Validation/test transfer is weak or reversed |
| `late_horizon_gap` | Middle/late horizon blocks dominate losses |
| `graph_parity_gap` | Current row lacks graph-neighbor inputs and graph rows historically help |
| `graph_geometry_gap` | Graph inputs exist but graph degree/aggregation appears unstable |
| `pricefm_far_ahead` | PriceFM gap is too large for near-miss rescue |
| `stable_promising` | Validation and test evidence align enough to justify a small launch |
| `no_action` | Existing evidence does not justify additional compute |

### H. Next-grid recommendations

Stage R may recommend a next grid only if the recommendation is linked to a
failure mode and an existing evidence trail.

Recommended actions may include:

- `no_launch`: keep row unchanged.
- `seven_quantile_confirmation`: only for a validation-selected median row that
  has already passed strict test guardrails in an earlier stage.
- `horizon_block_selection_pilot`: use existing candidates to test a validation
  rule that includes horizon-block stability before launching new fits.
- `graph_parity_targeted_grid`: for target-only underperformers with no graph
  parity yet.
- `stable_seed_recheck`: for rows with aligned validation/test but possible
  seed fragility.
- `defer_as_pricefm_far_ahead`: for rows where PriceFM is too far ahead and no
  past Q-DESN family approached it.

The script must not write launch configs automatically unless a later command
explicitly requests a grid preparer.  The first Stage-R output should be a
diagnostic recommendation table.

## Criteria For A Future Search

A future Stage-S grid is justified only if Stage R identifies at least one row
or family satisfying all of:

1. A clear failure mode is assigned.
2. The proposed search changes the failure mode, not merely more random
   capacity.
3. Historical diagnostics show either positive validation/test transfer or a
   reason to replace the selection rule.
4. The run can remain median-only until a later paper-quantile confirmation.
5. Artifact hygiene can delete `.rds`, `.rda`, `.RData`, and `.rdata` products
   after metrics and figures are produced.
6. The output is under ignored `application/data_local/pricefm/` roots.

If these gates are not met, the optimal action is no new search.

## Efficient Exploration Strategy After Stage R

If Stage R recommends a new launch, use a priority-tiered plan:

| Priority | Purpose | Size | Parallelism |
|---|---|---:|---|
| 0 | Strong diagnostic-backed rows only | Small, explicit | 8-20 experiment jobs, `cell_jobs = 1` |
| 1 | Secondary rows only if priority 0 transfers | Moderate | Launch after closeout only |
| 2 | Exploratory seeds/capacity | Small diagnostic sample | Never before priority 0 is closed |

Do not keep binary fit artifacts.  Metrics, diagnostics, figures, manifests,
logs, and checksums are sufficient for this PriceFM screening workflow.

## Required Tests For Stage-R Tooling

Suggested new test:

```text
application/tests/test_pricefm_stage_r_selection_diagnostics.py
```

Test coverage:

- [ ] Missing input CSV fails clearly.
- [ ] Duplicate region/fold keys fail where uniqueness is required.
- [ ] Non-finite metrics fail clearly.
- [ ] Stage-Q priority-1 recommendation is respected as false.
- [ ] Candidate rows from heterogeneous sources normalize to one schema.
- [ ] Test-oracle rows are marked audit-only.
- [ ] Failure-mode assignment is deterministic on a synthetic fixture.
- [ ] No launch YAML is written by the diagnostic script.
- [ ] Summary JSON records `diagnostic_only = true`.

Validation commands:

```sh
application/data_local/pricefm/venv/bin/python \
  -m pytest application/tests/test_pricefm_stage_r_selection_diagnostics.py -q

application/data_local/pricefm/venv/bin/python \
  -m py_compile application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py

application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/78_diagnose_pricefm_selection_transfer.py

git diff --check
```

## Documentation Criteria

The Stage-R implementation note should report:

- repo state and commit;
- all input paths and hashes;
- summary of Stage-M, Stage-N, Stage-O, Stage-P, and Stage-Q evidence;
- validation/test transfer table;
- horizon-block failure table;
- information-set parity table;
- failure-mode scorecard;
- recommended next action per region/fold;
- explicit statement that no Stage-M surface mutation occurred;
- exact next command if a Stage-S grid is later approved.

## Recommended Next Move

Implement Stage R as a diagnostic-only pass.  Do not launch another grid until
Stage R identifies a row-level failure mode and a selection rule that is more
credible than median validation AQL alone.

This is the most efficient path because it uses the already expensive Stage-N
and Stage-Q outputs to decide whether any new compute is scientifically
justified.  It also keeps the article evidence reproducible: Stage-M remains
unchanged, Stage-Q remains negative evidence, and any future Stage-S launch
must be linked to a documented diagnostic finding.

## Closeout

Stage R was implemented and closed out in:

```text
docs/implementation_notes/pricefm_stage_r_selection_diagnostics_20260627.md
```

The ignored local outputs are under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r_selection_diagnostics_20260627/
```
