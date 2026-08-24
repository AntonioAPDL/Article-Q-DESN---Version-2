# PriceFM operational post-closeout audit

Date: 2026-08-23

## Objective

Freeze and independently replay the completed operational PriceFM
public-architecture campaign before any registry or article integration. The
audit verifies campaign completeness, validation-only selection, fitted-model
hashes, test predictions, metrics, selector sensitivity, historical-reference
lineage, and the disposition of the superseded Stage-R56 plan.

This stage is read-only with respect to scientific state. It launches and fits
no model, writes no YAML, and cannot mutate the Q-DESN registry or article.

## Frozen campaign

- Run tag: `pricefm_operational_public_architecture_fullshot_20260812`.
- Campaign completion: 2026-08-22 19:02:58 UTC.
- Validation fits: 9 Phase-I, 1,047 Phase-II screen, and 48 stability fits.
- Test predictions: 136 unique frozen-selector tasks.
- Scheduler evidence: 21,455 events, zero failure/error/retry events, and a
  final `completed` event.
- Pinned campaign inputs and closeout products: 17 SHA-256 contracts.
- Rehashed audit surface: 4,337 unique files and 5,334,483,902 unique bytes.

The canonical artifact root is:

```text
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/benchmarks/pricefm_operational_public_architecture_fullshot_20260812
```

The post-closeout output is retained below that root in
`post_closeout_audit/`. It contains 18 CSV, JSON, and Markdown files and no
fitted-model object or launch configuration.

## Audit wiring

`199_audit_pricefm_operational_postcloseout.py` performs the following checks:

1. Pins campaign protocol, data manifests, winner freezes, test products,
   closeout products, scheduler health/events, and historical reference
   ledgers by SHA-256.
2. Rehashes every validation checkpoint and metric file for all 1,104 fits.
3. Replays all 136 test prediction artifacts against the frozen test windows,
   including response anchors, AQL, AQCR, MAE, and RMSE.
4. Recomputes case, quantile, four horizon-block, horizon-by-quantile, and
   calibration diagnostics for both frozen selectors.
5. Runs a deterministic 2,000-replicate circular seven-origin block bootstrap
   for the operational prediction surface.
6. Keeps the preregistered cell-specific selector controlling and treats the
   region-global selector as sensitivity evidence only.
7. Audits the scalar and retained-prediction lineage of current Q-DESN and
   cached PriceFM references.
8. Emits an all-or-none operational comparator proposal, a separate Q-DESN
   harm-guard ledger, and an explicit Stage-R56 supersession ledger.

## Reproduction command

Run from the dedicated PriceFM worktree:

```bash
/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv_pricefm_tf/bin/python \
  application/scripts/pricefm/199_audit_pricefm_operational_postcloseout.py \
  --artifact-root /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/benchmarks/pricefm_operational_public_architecture_fullshot_20260812 \
  --qdesn-registry /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_decision_registry.csv \
  --qdesn-horizon-diagnostics /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_full_surface_decision_closeout_20260704/pricefm_full_surface_horizon_diagnostics.csv \
  --reference-repo-root /data/jaguir26/local/src/Article-Q-DESN \
  --campaign-health /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/logs/pricefm_operational_public_architecture_fullshot_elastic_20260820/campaign_health.json \
  --campaign-events /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/logs/pricefm_operational_public_architecture_fullshot_elastic_20260820/campaign_events.jsonl \
  --stage-r55-dir /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r55_functional_convergence_20260820 \
  --stage-r56-prep-dir /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/authoritative/pricefm_stage_r56_ee_f1_confirmation_prep_20260820 \
  --output-dir /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/benchmarks/pricefm_operational_public_architecture_fullshot_20260812/post_closeout_audit \
  --bootstrap-replicates 2000 \
  --bootstrap-block-origins 7 \
  --bootstrap-seed 20260823 \
  --force true
```

Forced replacement is constrained by the script to a flat directory inside
the pinned campaign artifact root.

## Main result

| Quantity | Result |
| --- | ---: |
| Region/fold cells | 114 |
| Mean operational PriceFM AQL | 6.009387 |
| Mean current Q-DESN AQL | 6.826019 |
| Mean cached PriceFM AQL | 7.038685 |
| Operational below current Q-DESN | 103 / 114 |
| Operational below cached PriceFM | 106 / 114 |
| Primary pointwise dual-reference rows | 99 / 114 |
| Both selectors dual-reference rows | 97 / 114 |
| Operational-only upper interval below both fixed scalars | 41 / 114 |
| Current Q-DESN harm-guard rows | 11 / 114 |

The valid comparator proposal is the complete 114-row operational replay or
none of it. Selecting only the 99 test-winning rows would choose comparator
membership after observing test outcomes and is therefore forbidden.

The 41 interval rows are also not paired superiority results. Their intervals
quantify only operational-replay uncertainty while treating historical scalar
references as fixed thresholds.

## Mechanism diagnostics

- Quantile crossing is absent: mean AQCR is exactly zero.
- The predictive distribution is generally underdispersed: mean empirical
  10th-to-90th percentile coverage is 0.6926 against nominal 0.80, and mean
  25th-to-75th percentile coverage is 0.4221 against nominal 0.50.
- Mean absolute quantile calibration error is 0.0704; the mean worst-quantile
  absolute error is 0.1246.
- The hardest horizon block is 49-72 quarters with mean AQL 7.3499, followed
  by 25-48 with 6.7919, 73-96 with 6.2496, and 1-24 with 3.6462.
- The largest case-level calibration deviations occur at EE/fold 2,
  SE_3/fold 2, and SI/fold 3.
- Selected graph degrees are concentrated at degree 0 (46 rows), degree 1
  (32), and degree 2 (24); only eight rows use degrees 3 or 4. Four rows retain
  Phase-I candidates.

These results support a calibration and long-horizon diagnosis after the
comparator decision. They do not justify selecting a different candidate from
test data or launching another broad search immediately.

## Reference limitation

The declared historical scalar registry remains the authority for the current
Q-DESN and cached PriceFM comparison. However:

- only 84/114 rows name the same validation-selected Q-DESN method in their
  immediate source ledger;
- only 72/114 rows retain four historical horizon-delta summaries;
- 0/114 rows retain an exact Q-DESN prediction surface whose scalar metric
  matches the authority used in this audit;
- 0/114 rows retain an equivalent cached PriceFM prediction surface.

This limitation does not invalidate the scalar comparison ledger. It blocks
symmetric paired horizon, quantile, calibration, and uncertainty claims until
a matched, validation-selected Q-DESN prediction surface is reconstructed on
the same anchors.

## Stage-R56 disposition

The former EE/fold-1 Stage-R55 candidate has test AQL 15.113837. The completed
operational PriceFM replay has AQL 14.692011 for that cell. The old candidate
therefore loses by 0.421825 and Stage-R56 is superseded. It must not launch.
The prior R56 preparation artifacts were audited but not changed.

## Validation and reproducibility

- `py_compile` passed for the audit script and focused tests in the pinned
  TensorFlow environment.
- Focused suite: 22 tests passed, covering this audit and the operational
  full-shot implementation.
- Two independent complete materializations were byte-for-byte identical.
- Canonical `summary.json` SHA-256:
  `6959f578e2de8c079abc3561e8011a934046f5caf2f80ab723de1cfe74a00192`.
- Canonical `output_manifest.csv` SHA-256:
  `4d1dc346bf7fcf95ab2da6846f266bd8402894d575b9478a05d5c1bad0ddb128`.
- Canonical `report.md` SHA-256:
  `20eb928aee39275ed1459c51eb058d5548389d20ade3d7285406adada8cff67a`.
- `git diff --check` passed.

## Decision and next action

The complete operational PriceFM surface is ready for an independent
integration review as a separate public-architecture operational replay. It
must remain distinct from the paper's Table-II/Table-IV result and from the
cached released-checkpoint replay.

Before any paired superiority claim or article mutation, reconstruct and
freeze a validation-selected Q-DESN prediction manifest on the same test
anchors with all seven quantiles. Then run a paired read-only audit while
preserving the 11 current-Q-DESN-win cells as harm guards.

Until that review is complete:

- do not mutate the Q-DESN registry or article;
- do not launch Stage-R56;
- do not start another expensive PriceFM search;
- do not clean the 4.8 GiB campaign evidence bundle;
- do not touch GloFAS, joint-QDESN, independent-validation, or other lanes.
