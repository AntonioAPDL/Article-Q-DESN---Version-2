# Joint exQDESN Phase 171-175 M0 Article Confirmation

## Purpose

This workflow closes the exAL inference update for the balanced joint-QDESN
simulation study. It reruns only the 16 exAL cells: eight original article
mechanisms under Joint exQDESN RHS and Independent exQDESN RHS. The 16 AL cells
remain frozen. This is an inference confirmation at already selected,
scenario-specific model controls; it is not another DESN or prior screen.

The statistical estimand remains the posterior quantile grid. Posterior-mean
quantile paths are scored after the declared monotone contract. Raw crossings
remain diagnostics. No scalar predictive density is constructed from the
composite exAL working likelihood.

## Why M0

Phase 169R compared the exact exAL transitions at equal effort, and Phase 170
promoted `M0_v_collapsed_support_logit` as the production default. The present
workflow nevertheless passes M0 explicitly in every production call. It does
not compare sampler methods again and does not select a method from realized
forecast scores.

Phase 169R used replicate-001 method-development fixtures. Phase 171 instead
freezes the eight original article fixtures, so Phase 169R scores cannot be
copied into the article table.

## Design

The registry is
`application/config/joint_exqdesn_m0_balanced_article_confirmation_v1.csv`.
It contains 16 cells and freezes:

- the original eight article scenarios;
- joint and independent exAL readouts;
- scenario-specific DESN and regularized-horseshoe controls;
- the `VB0_point_v` to `VB1_structured_v` initializer hierarchy;
- eight dispersed starts per cell;
- eight chains, 24,000 iterations, 4,000 burn-in iterations, and thinning by
  four;
- explicit M0 inference;
- the posterior quantile-grid scoring contract.

The campaign has 128 top-level workers. Joint cells contribute one sampler per
worker; independent cells contribute seven quantile-specific components. The
physical total is 512 component runs. Phase 171 materializes every seed and
requires global uniqueness. This removes the avoidable cross-tau seed overlap
identified in historical independent runs.

## Phases

### Phase 171: immutable readiness freeze

Phase 171 verifies historical manifests, current article-asset hashes, exact
controls, original fixtures, split metadata, the eight-scenario scope, and the
intentional exclusion of `heteroskedastic_seasonal`. It computes VB0 and VB1
initializers without model selection, freezes starts and seeds, performs score
preflights, and writes a SHA-256 manifest. It requires a clean implementation
worktree and modifies no article asset.

```bash
Rscript application/scripts/232_prepare_joint_exqdesn_phase171_m0_article_freeze.R --cores 8
```

### Phase 172: balanced M0 confirmation

Each worker verifies the Phase 171 freeze, runs one top-level chain, writes a
compressed post-fit checkpoint before scoring, verifies checkpoint identity,
and writes finite fit/forecast diagnostics. No `.RData`, `.rda`, or `.rds`
workspace is produced.

The launcher requires 24-32 explicitly listed, currently idle logical CPUs,
at least 100 GiB available RAM, and at least 10 GiB free disk. It binds one
single-threaded worker to each CPU and submits four balanced waves. It refuses
to compete with a high-CPU process found on any selected slot. By default it
uses the authoritative shared cache at
`/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache`, matching
the R workflow. `JOINT_EXQDESN_CACHE_ROOT` or `--cache-root` may override that
location explicitly for a reproducible alternate deployment.

```bash
bash application/scripts/234_launch_joint_exqdesn_phase172_m0_confirmation.sh \
  --jobs 32 \
  --cpu-list 16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,42,43,44,45,46,47
```

The CPU list above is illustrative, not a reservation. It must be regenerated
from the launch-time process audit.

```bash
Rscript application/scripts/235_check_joint_exqdesn_phase172_m0_confirmation.R
```

### Phase 173: posterior and functional audit

Phase 173 requires 128 verified workers and pools exactly eight chains per
cell. It reports every beta and alpha coordinate, gamma, sigma, bounded gamma
probability, actual standard deviation, and the M0 scale-shape combination.
It also computes:

- first-four versus last-four and odd versus even quantile-path comparisons;
- leave-one-chain-out fit and forecast sensitivity;
- chain-cluster jackknife Monte Carlo error;
- posterior mean, median, and trimmed-mean sensitivity;
- fit, forecast, check-loss, grid-CRPS, hit-rate, interval, crossing, and
  monotone-adjustment summaries;
- historical-versus-M0 differences.

Outcomes are `pass`, `qualified_article_ready`, `review_hold`, or `fail`.
Mild scalar gamma review is not itself disqualifying when readout and
quantile-path functionals are stable. A held cell writes an unlaunched,
48,000-iteration rescue plan. No rescue is launched automatically and rescue
draws may never be concatenated with the deterministic primary prefix.

```bash
Rscript application/scripts/236_finalize_joint_exqdesn_phase173_m0_article_audit.R
```

### Phase 174: balanced packet and staging

Phase 174 is permitted only when all 16 exAL cells are `pass` or
`qualified_article_ready`. It preserves the 16 historical AL rows
value-for-value, replaces the 16 exAL rows, recomputes full-precision winners,
and writes a 32-cell packet. It then builds article tables under an ignored
staging directory and verifies that current tracked article assets did not
change.

```bash
Rscript application/scripts/237_build_joint_qdesn_phase174_article_assets_staging.R
```

### Phase 175: explicit article promotion

The module provides an allow-listed, atomic promotion function, but it rejects
all calls unless `approved=TRUE`. Promotion is intentionally not part of the
long-run launcher. Human review of Phase 173 diagnostics, Phase 174 table
diffs, winner Monte Carlo error, manuscript wording, and a clean LaTeX compile
must occur first.

## Gates

Hard failures include missing hashes, wrong fixtures or controls, seed
collisions, wrong method IDs, incomplete cells or chains, nonfinite draws or
scores, invalid exAL support, split leakage, and crossings after the monotone
contract.

Review conditions include raw crossings, material monotone adjustments, scalar
R-hat/ESS limitations, quantile-path partition instability, leave-one-chain-out
score sensitivity, unresolved winner margins, and runtime outliers. Favorable
realized scores do not override these gates.

## Verification

Focused tests:

```bash
Rscript application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R
Rscript application/tests/test_joint_exqdesn_inference_dispatch.R
Rscript application/tests/test_joint_exqdesn_phase167_169_mcmc_method_selection.R
Rscript application/tests/test_joint_exqdesn_phase169r_recovery.R
Rscript application/tests/test_joint_exqdesn_phase170_default_promotion.R
Rscript application/tests/test_joint_qdesn_phase154_mcmc_evidence_reconciliation.R
Rscript application/tests/test_joint_qdesn_phase155_article_promotion.R
```

The first expensive computation is the complete Phase 172 campaign. No extra
production smoke or broad calibration campaign is introduced.
