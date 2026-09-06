# PriceFM Stage-R57 joint seven-quantile campaign

## Objective

Stage-R57 replaces the independent seven-model PriceFM quantile bundle with one
joint ordered-quantile model in each of the 114 region/fold cells. It does not
search for one global DESN. Each cell inherits the authoritative DESN geometry,
information set, likelihood family, and RHS-NS hyper-scale selected for that
cell. The seven quantiles are
`0.10, 0.25, 0.45, 0.50, 0.55, 0.75, 0.90`.

The frozen surface contains 27 AL cells and 87 exAL cells. AL cells use the
joint AL CAVI implementation. exAL cells use the explicit
`VB1_structured_v` approximation for screening. A later exact MCMC confirmation
may use standard joint AL Gibbs updates for AL cells and
`M0_v_collapsed_support_logit` for exAL cells. MCMC remains gated on the
validation closeout.

## Scientific contract

- One joint model is fit per region/fold; there is no post-hoc quantile synthesis.
- The source adapter intercept is verified and removed before fitting because the
  joint model estimates ordered quantile-specific intercepts explicitly.
- The source local or graph feature policy and complete DESN specification are
  inherited without pooling across cells.
- The anchor and innovation RHS-NS blocks both use the inherited
  `tau0=0.001`. Stage-R57 does not screen `tau0`.
- Raw joint predictions are scored. Isotonic or other post-hoc crossing repair is
  not part of the primary result.
- Validation is the only selection split. Current Q-DESN and cached PriceFM test
  outcomes reside in a separate sealed ledger until validation decisions freeze.
- Registry and article mutation remain blocked.

## Scalable exact MCMC algebra

The historical joint MCMC path constructs an explicit block-diagonal stacked
design. On the PriceFM surface this would contain roughly 104 million to 213
million nonzero entries per case. The PriceFM-scoped compact backend instead
computes each quantile block as

```text
A_k = Z' W_k Z
r_k = Z' W_k y*_k
K_beta = blockdiag(A_1, ..., A_7) + P_beta
```

in bounded row chunks. This is algebraically identical to the stacked design and
retains the joint RHS-NS prior coupling. The shared joint-validation implementation
is not modified. The compact backend is installed only around a PriceFM MCMC call.
Small-fixture tests compare precision, right-hand side, and posterior mean against
the historical stacked calculation.

The current full-surface launch is VB. Existing joint VB code already builds the
same block crossproducts without constructing `Z_stack`; its declared dense
coefficient bound is raised deliberately to 2,500. The observed PriceFM joint
dimensions are 994--1,827.

## Pipeline

1. `200_freeze_pricefm_stage_r57_joint_authority.py` recovers exactly one source
   configuration for every authoritative region/fold cell and writes a runnable
   authority with no test outcomes.
2. `201_prepare_pricefm_stage_r57_joint_vb.py` materializes 114 adapter and runtime
   configurations containing only `train` and `val`.
3. `202_run_pricefm_stage_r57_joint_vb_case.R` rebuilds the inherited adapter,
   verifies the intercept and split firewall, fits the joint model, scores
   validation, and saves a compact MCMC initializer.
4. `203_launch_pricefm_stage_r57_joint_vb.py` assigns one sequential lane to each
   explicitly selected CPU. Every process is pinned and every numerical library
   is restricted to one thread.
5. After successful validation scoring, each worker removes rebuilt `X`, `y`, and
   row CSVs. It retains adapter manifests and feature-map hashes, predictions,
   metrics, traces, parameter summaries, crossing diagnostics, and the compact
   initializer.
6. `204_closeout_pricefm_stage_r57_joint_vb.py` refuses partial surfaces and uses
   original-scale validation AQL only. A case enters the future MCMC queue only if
   it improves on authoritative validation AQL, reports convergence, and has zero
   raw validation crossing rows.

## Reproducible commands

Use the PriceFM Python environment from the historical artifact repository:

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/venv/bin/python

$PRICEFM_PY application/scripts/pricefm/200_freeze_pricefm_stage_r57_joint_authority.py
$PRICEFM_PY application/scripts/pricefm/201_prepare_pricefm_stage_r57_joint_vb.py

$PRICEFM_PY application/scripts/pricefm/203_launch_pricefm_stage_r57_joint_vb.py \
  --manifest /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/experiment_grids/pricefm_stage_r57_joint_vb_20260824/launch_manifest.csv \
  --runner application/scripts/pricefm/202_run_pricefm_stage_r57_joint_vb_case.R \
  --cpu-list <audited-unused-logical-cpus> --workers <worker-count> \
  --resume true --force false
```

The launcher must be started only after a live process and CPU-topology audit.
Do not infer free CPUs from load average alone.

## Validation

Focused tests are:

```bash
Rscript application/tests/test_pricefm_joint_quantile_compact_kernel.R

$PRICEFM_PY -m pytest -q \
  application/tests/test_pricefm_stage_r57_joint_authority.py \
  application/tests/test_pricefm_stage_r57_joint_vb_campaign.py
```

The Python suite covers the 114-case prep contract, a real tiny joint AL fit,
CPU-lane scheduling, sealed-test isolation, and validation-only closeout. No test
adapter, registry mutation, article edit, or manuscript asset is produced by
Stage-R57.

## Live recovery amendment

The 2026-08-24 live audit identified a recoverable postfit metadata failure and a
scoring-policy mismatch with the repository-wide joint monotone contract. The
fit campaign remains scientifically usable. The authoritative recovery,
dual-role audit, and continuation gates are documented in
`pricefm_stage_r57_r58_joint_recovery_20260824.md`; that note supersedes the
zero-raw-crossing hard gate above until the full-surface scoring contract is
explicitly frozen.
