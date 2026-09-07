# PriceFM Stage-R94 Coherent exAL Initialization Repair

## Scope and decision

Stage-R94 is a prospective repair for the independent PriceFM exAL VB step. It
does not alter or resume the live Stage-R93 process. It does not refit Ridge,
normal-RHS, DESN features, or AL models; open test data; select on test; fit a
joint model or MCMC; mutate the registry; or update the article.

The immediate goal is narrower: make the same-tau AL-to-exAL transition
internally coherent, replace a scale-sensitive failure label with trajectory
checks, and prepare exactly seven reusable atomic exAL tasks after R93 has
finished all seven AL and seven exAL atoms.

## Audited evidence

1. The completed R93 exAL atoms are finite and have bounded final sigma, gamma,
   and coefficient norms. Their only failing numerical check is
   `first_state_delta_below_100`.
2. The first `delta_state` is the maximum raw coordinate change in beta. It is
   therefore affected by feature and coefficient scaling.
3. The 280 R87 exAL traces include 36 first deltas at or above 100. The R82
   three-case diagnostic that motivated 100 was too small to define a universal
   scientific boundary.
4. R82 imports the AL coefficient mean, but resets the covariance to the prior,
   initializes the RHS variational state from scratch, and starts latent `v`
   and `s` moments from generic constants. The first q(beta) update therefore
   measures a partial-initialization transition.
5. R82's point-mass sigma/gamma plug-in at gamma zero fixed a separate,
   well-identified non-smooth curvature problem. That correction remains in
   R94 unchanged.
6. The configured post-warmup damping is consumed by later structured
   sigma/gamma updates, but it does not govern the first beta update. R94
   therefore preserves R93's damping exactly. Raising `max_iter` can allow
   additional contraction, but cannot by itself repair the initialization
   mismatch.

The evidence-led conclusion is that the R93 first-delta failures do not prove
that exAL is numerically invalid. They do justify a prospective rerun under a
coherent initializer and a pre-registered numerical contract. Existing R93
results are not relabelled in place.

## Repair contract

The R94 runtime derives from the exact hash-pinned R82 source, which derives
from CRAN exdqlm 1.1.1. The local version is `1.1.1.9005`; this is provenance,
not a claim of a new public exdqlm release.

For `warm_start_mode = al_qbeta_rhs_latent_first`, R94:

- imports the AL coefficient mean and covariance diagonal;
- initializes the RHS variational state from that q(beta);
- resets only the RHS iteration bookkeeping afterward so the original
  freeze/update schedule still begins at model iteration 1;
- computes q(v) and q(s) moments from the imported AL state before the first
  exAL q(beta) update;
- retains the R82 structured sigma/gamma point-mass plug-in;
- records raw, relative-coordinate, and prediction-scaled beta changes.

The absolute first beta delta remains in every output as a diagnostic. It is
not an eligibility criterion. Numerical eligibility instead requires finite
core outputs and traces, at least 35 structured updates, `0 < sigma < 100`,
`abs(gamma) < 4`, final-to-initial beta L2 ratio below 10, tail state/sigma
deltas below 2, tail relative-state change below 0.01, and tail
prediction-scaled change below 0.01. Formal package convergence is reported
separately. First-step size and tail-to-first contraction are retained as
diagnostics only: making contraction mandatory would incorrectly reject an
initializer whose first step was already small. This avoids turning a
coordinate-dependent first iteration into a scientific exclusion while
retaining strict endpoint and trajectory guards.

## Workflow

1. `297_audit_pricefm_stage_r94_exal_initialization.py` materializes the R93
   atom audit, 280-trace R87 first-delta ledger, root-cause ledger, repair
   contract, source hashes, and report. It may audit an incomplete R93 run, but
   it authorizes production preparation only when R93 is complete.
2. `298_materialize_pricefm_stage_r94_exal_runtime.py` verifies the R82 source
   hashes, applies exact one-time source edits, optionally installs the isolated
   runtime, and runs a small public-API numerical probe.
3. `302_materialize_pricefm_stage_r94_adapter.py` deterministically regenerates
   the large R93 train/validation design matrices into a separate R94 adapter
   directory after R93 cleanup. It requires exact equality with the X, y, row,
   and reservoir-map hashes recorded by R93.
4. `300_prepare_pricefm_stage_r94_exal_refit.py` requires complete R93 and R94
   audit gates, then freezes the adapter files, all nested adapter scripts, Git
   identity, seven AL q(beta) warm starts, and seven JSON task files. It writes
   no YAML and grants no launch permission.
5. `299_run_pricefm_stage_r94_exal_component.R` is the atomic train/validation-
   only worker. It emits CSV/JSON diagnostics and no R binary model artifact.
6. `301_launch_pricefm_stage_r94_exal_refit.py` performs resource, Git, and hash
   preflight; quarantines invalid partial atoms; records live PID/CPU/RSS and
   CPU-time observations; and uses at most seven distinct CPUs. An actual
   launch requires `RUN_PRICEFM_R94_COHERENT_EXAL_REFIT`.
7. `303_closeout_pricefm_stage_r94_validation_family.py` recomputes original-
   scale metrics from atomic predictions and freezes one complete AL or exAL
   family by raw Fold-1 validation AQL. It never mixes families by quantile.
8. `306_orchestrate_pricefm_stage_r94.py` automates audit, runtime probe,
   adapter regeneration, task preparation, preflight, seven-atom execution,
   and validation closeout, then stops before all-fold fitting or test access.

## Reuse on later regions

The prep reads the source R93 semantic contract rather than hard-coding a new
DESN. Thus each later region/fold can retain its own selected feature policy,
depth, units, lag window, alpha, rho, input scale, state output, and tau0. The
workflow operates on one independently calibrated region/fold case at a time
and never searches for one common DESN specification across all cases.

For a later case, the required inputs are a complete seven-quantile AL surface,
its train/validation-only adapter, a frozen semantic contract, and the R94
runtime/audit hashes. The same seven-atom exAL stage can then be prepared and
run independently. Only paths and immutable case identity change.

## Post-run decision path

After an R94 run, the read-only closeout verifies all seven
atom hashes and numerical gates and compares AL versus exAL using validation
only. Test data remains sealed until a complete family is selected. A later
test audit may compare that frozen family against authoritative Q-DESN and
cached PriceFM. Registry and article promotion remain separate explicit gates.

## Do not do yet

- Do not stop, alter, or relaunch R93.
- Do not run the R94 production launcher.
- Do not reuse the incomplete R93 exAL family for selection.
- Do not tune the R94 gate from test AQL or future test outcomes.
- Do not rerun Ridge, normal-RHS, DESN, or AL merely to repair exAL.
- Do not fit joint Q-DESN or MCMC.
- Do not mutate registry or article files.

The exact next operational action is to wait for R93 to finish, rerun the R94
audit with `--require-complete`, materialize the seven-task prep, and perform
launcher preflight. A production launch still requires a later explicit user
authorization.
