# GloFAS constrained median screening

Date: 2026-08-11

## Objective

Prepare a reproducible, range-driven p50 screen that can improve forecast-window
performance without repeating the earlier failure mode in which forecast CRPS
improved while the pre-cutoff USGS fit deteriorated sharply. The screen keeps
the reference/shared-quantile and discrepancy DESNs independently configurable,
uses warm starts only under an explicit semantic-compatibility contract, and
does not launch or promote a model without a separate decision.

This implementation prepares the machinery only. Parameter ranges remain empty
until they are supplied and reviewed by the investigator.

## Audit conclusions

1. The current application is already a two-block model: the reference block is
   driven by transformed USGS history and the discrepancy block by the
   retrospective GloFAS-minus-USGS path. It also uses separate reservoir seeds
   and separate regularized-horseshoe global scales.
2. Before this change, both blocks still inherited the same global reservoir,
   reservoir-input, and direct-readout config. Independent block calibration was
   therefore not represented cleanly in the public application config.
3. `reservoir.m` is not, by itself, the operative lag contract in the
   covariate-aware implementation. The actual response and ppt/soil lags are
   specified under `feature_contract.reservoir_input`; direct readout lags are a
   separate contract.
4. The previous VB warm start checked dimensions, but equal dimensions do not
   prove equal feature meaning. A changed lag order, seed, or architecture can
   produce a vector of the same length with incompatible coordinates.
5. A p50 fit cannot identify a synthesized predictive distribution. Its proper
   screening score is p50 check loss; at p50 this is one half of absolute error.
   Genuine quantile-grid CRPS is available only after a multi-quantile refit.
6. FR09 is now represented by a SHA-pinned baseline contract. Preparation
   recomputes its declared p50 scores from the promoted evidence, verifies its
   source fit and semantic design contract, checks the promotion registry, and
   requires the frozen article engine at commit `73c043f`.

## Implemented contracts

### Independent feature blocks

Optional overrides live at:

```yaml
feature_contract:
  blocks:
    reference:
      reservoir: {}
      reservoir_input: {}
      readout: {}
      reservoir_seed: 20260512
    discrepancy:
      reservoir: {}
      reservoir_input: {}
      readout: {}
      reservoir_seed: 20261521
```

If these overrides are absent, the old global configuration is used unchanged.
If washouts differ, both blocks use the larger washout so their retained dates
remain aligned. Fitted and future-state builders resolve the same effective
block configs and record separate SHA-256 hashes in design summaries.

### Lag semantics

For a candidate that changes `m` but does not supply explicit reservoir lag
maxima, the planner materializes:

- response lags `1:m`;
- ppt and soil lags `0:(m-1)`.

Explicit `reservoir_output_lag_max` and
`reservoir_covariate_lag_max` values override that convention. Direct readout
lags change only when their own parameters are supplied. This prevents an `m`
label from changing while the operative lag matrix remains unchanged.

### Semantic VB warm starts

Every new latent-path fit stores a warm-start contract containing:

- quantile level;
- full design hash;
- ordered coefficient-name hash;
- coefficient dimension;
- forecast-key hash and horizon length.

Forecast keys are canonicalized to ISO dates and integer horizons with row names
removed. Row names inherited from panel indices are not part of feature meaning
and therefore cannot create a false incompatibility.

The planner selects one of three policies:

| Policy | Required compatibility | Transfer |
|---|---|---|
| `exact_design` | Full design, quantile, coordinates, and future key | coefficients, future path, source scales |
| `coordinate_transfer` | Same ordered coordinates, quantile, and future key | coefficients, future path, source scales; mandatory cold confirmation |
| `state_only` | Same quantile and future key | future path and source scales only; mandatory cold confirmation |

If the source fit or semantic contract is unavailable, the candidate starts
cold. The preparer first honors an explicit contract and otherwise discovers a
contract embedded in a new-format source fit. It snapshots that contract and
its hash with the runtime provenance. Equal parameter count alone never
authorizes coefficient transfer.

The promoted FR09 fit predates embedded contracts. Its tracked semantic contract
was derived once from the exact SHA-pinned design object and is cross-checked
against the design summary, p50 prediction keys, coefficient dimension, future
dimension, and source-fit SHA before reuse.

### Selection gates

The p50 screen reports forecast check loss and historical log1p MAE. It does not
call median absolute error CRPS. Default gates relative to the reviewed baseline
are:

| Window | Default rule | Role |
|---|---:|---|
| All pre-cutoff observations | at most 1.05 times baseline MAE | hard |
| Last 1000 | at most 1.05 times baseline MAE | hard |
| Last 200 | at most 1.10 times baseline MAE | hard |
| Last 50 | at most 1.15 times baseline MAE | soft by default |
| Forecast window | at least 3% lower p50 check loss | hard |

These values are configurable in the screening-space YAML. A candidate must also
have finite fit diagnostics. `vb_converged` can be made a hard gate, but is not
hard by default because a stable finite fit can end at the configured iteration
cap after its ELBO has effectively flattened.

An eligible p50 candidate is only **eligible for review**. The framework sets
both `auto_launch_full7` and automatic promotion to false. The required sequence
is diagnostic review, cold p50 confirmation when any heuristic warm start was
used, then seven independent quantile fits and genuine CRPS comparison.

## Range specification

The generic tracked template is:

```text
application/config/glofas_constrained_median_screen_space_TEMPLATE.yaml
```

The ready-to-fill FR09 template and its evidence contracts are:

```text
application/config/glofas_constrained_median_screen_space_FR09_TEMPLATE.yaml
application/config/glofas_constrained_median_baseline_fr09.yaml
application/config/glofas_constrained_median_fr09_warm_start_contract.yaml
```

The FR09 contract records the exact comparison point:

| Field | Reference/shared | Discrepancy |
|---|---:|---:|
| `D` | 1 | 1 |
| `n` | 300 | 300 |
| `m` | 360 | 360 |
| washout | 500 | 500 |
| `alpha` | 0.10 | 0.10 |
| `rho` | 0.95 | 0.95 |
| `pi_w`, `pi_in` | 0.03, 1.00 | 0.03, 1.00 |
| input scale | 0.18 | 0.18 |
| seed | 20260512 | 20261521 |
| RHS `tau0` | 0.10 | 0.001 |

Reservoir output lags are `1:360`, reservoir ppt/soil lags are `0:360`,
and direct-readout output and ppt/soil lags are `1:180` and `0:180`,
respectively. Exact p50 comparison metrics are forecast check loss
`0.798826956115941` and pre-cutoff log1p MAE `0.0624424466662982` overall,
`0.0388437273850094` for the last 1000 dates, `0.05360828353558` for the
last 200, and `0.178787719773148` for the last 50.

Each `candidate_set` is expanded independently. This supports staged searches
and avoids an accidental Cartesian product across every proposed range. The
supported scalar-per-candidate fields for each of `reference` and `discrepancy`
are:

```text
D, n, n_tilde, m, washout, alpha, rho, pi_w, pi_in,
win_scale_global, win_scale_bias, seed,
reservoir_output_lag_max, reservoir_covariate_lag_max,
direct_output_lag_max, direct_covariate_lag_max,
include_input_block, rhs_tau0
```

`n` and `n_tilde` denote homogeneous per-layer widths in the range schema. An
explicit non-homogeneous architecture should be added as an explicit candidate
rather than encoded ambiguously as a range value. Quote the YAML key as `'n'`;
the parser also normalizes the YAML 1.1 boolean-key interpretation defensively.

### Linked two-block factorial

The August 11 linked screen adds a stricter `linked_factorial` schema for the
case where the reference and discrepancy blocks must use the same DESN and lag
specification. The blocks remain distinct reservoirs because they use different
input streams and seeds. Their regularized-horseshoe global scales also remain
separate and are crossed independently.

The reviewed full universe is defined in:

```text
application/config/glofas_p50_linked_d1d2_full_space_20260811.yaml
```

It contains five architecture profiles, two reservoir-memory profiles, two
matched direct-memory profiles, three leak rates, two spectral radii, and nine
ordered RHS prior pairs. Its exact cardinality is

```text
5 * 2 * 2 * 3 * 2 * 9 = 1080 p50 fits.
```

The launchable Stage-A slice is:

```text
application/config/glofas_p50_linked_d1d2_stage_a_20260811.yaml
```

Stage A runs all 120 structural/dynamic designs at the FR09 prior pair
`tau0_beta=0.1`, `tau0_alpha=0.001`. The implementation rejects a candidate if
the effective DESN, reservoir-input lags, or direct-readout lags differ between
blocks. Seeds are intentionally excluded from that equality check.

`execution.expected_candidates` is an exact-cardinality invariant;
`max_candidates` is retained as a second protection against accidental
expansion. The full-space definition is launch-inert. It documents the complete
universe without scheduling all 1080 fits blindly.

After Stage A is complete and finalized, the score-balanced continuation is
materialized with:

```bash
Rscript application/scripts/glofas_constrained_median_screen_prepare_stage_b.R \
  --stage_a_output_root local_trackers/runtime_configs/glofas_p50_linked_d1d2_stage_a_20260811 \
  --top_k 20
```

The selector first retains the best historically admissible candidate from
each architecture, reservoir-memory, direct-memory, leak-rate, and
spectral-radius level, then fills remaining positions by the p50 screen rank.
Each selected anchor generates its eight non-anchor prior pairs. Those variants
reuse the anchor's exact design and embedded semantic warm-start contract. A
cold p50 confirmation is still required before a full-seven fit whenever a
non-exact transfer was used upstream.

### Investigator range handoff

The investigator can return the following compact block. Bracketed values are
ranges; `inherit` keeps FR09. Separate candidate-set groupings should be named
when a full Cartesian product is not intended.

```text
Screen label:

Reference/shared DESN:
D = [ ]                 # current 1
n = [ ]                 # current 300 per layer
n_tilde = [ ]           # current none (D=1)
m = [ ]                 # current 360
washout = [ ]           # current 500
alpha = [ ]             # current 0.10
rho = [ ]               # current 0.95
pi_w = inherit          # current 0.03
pi_in = inherit         # current 1.00
win_scale_global = [ ]  # current 0.18
win_scale_bias = [ ]    # current 0.18
seed = [ ]              # current 20260512
reservoir output lag max = [ ]     # current 360
reservoir ppt/soil lag max = [ ]   # current 360
direct output lag max = [ ]        # current 180
direct ppt/soil lag max = [ ]      # current 180
RHS tau0 = [ ]          # current 0.10

Discrepancy DESN:
D = [ ]                 # current 1
n = [ ]                 # current 300 per layer
n_tilde = [ ]           # current none (D=1)
m = [ ]                 # current 360
washout = [ ]           # current 500
alpha = [ ]             # current 0.10
rho = [ ]               # current 0.95
pi_w = inherit          # current 0.03
pi_in = inherit         # current 1.00
win_scale_global = [ ]  # current 0.18
win_scale_bias = [ ]    # current 0.18
seed = [ ]              # current 20261521
reservoir output lag max = [ ]     # current 360
reservoir ppt/soil lag max = [ ]   # current 360
direct output lag max = [ ]        # current 180
direct ppt/soil lag max = [ ]      # current 180
RHS tau0 = [ ]          # current 0.001

Candidate-set grouping:
Maximum candidates:
Parallel jobs / approved cores:
```

The activation functions, input bound, standardization, internal bias, RHS slab
and beta-prime hyperparameters, two-block inputs, transition rule, likelihood,
and p50 VB method remain fixed unless a later scientific decision explicitly
widens scope.

## Workflow

1. Start from the FR09 template and insert only investigator-reviewed ranges.
2. Run the inert audit before adding or launching candidates:

   ```bash
   Rscript application/scripts/glofas_constrained_median_screen_prepare.R \
     --space application/config/glofas_constrained_median_screen_space_FR09_TEMPLATE.yaml \
     --audit_only true
   ```

   This checks the base config, model grid, baseline metrics, source fit,
   semantic contract, promotion registry, and frozen engine without generating
   candidates or authorizing a launch.
3. Insert investigator-approved candidate ranges. Keep
   `launch_authorized: false` during review.
4. Prepare deterministic candidate configs and manifests:

   ```bash
   Rscript application/scripts/glofas_constrained_median_screen_prepare.R \
     --space PATH_TO_REVIEWED_SPACE.yaml
   ```

5. Inspect `candidate_manifest.csv`, `candidate_contracts.csv`,
   `runtime_manifest.csv`, `provenance.csv`, and the generated configs.
6. To authorize a later launch, set `launch_authorized: true`, regenerate with
   `--authorize_launch true`, and run the generated `launch_screen.sh`. Merely
   preparing a screen cannot launch it.
7. After every candidate finishes, finalize:

   ```bash
   Rscript application/scripts/glofas_constrained_median_screen_finalize.R \
     --output_root local_trackers/runtime_configs/SCREEN_ID
   ```

8. Review `constrained_median_ranking.csv` and diagnostics. Do not promote from
   the p50 ranking alone.

The p50 screen and cold finalist confirmation both use `max_iter=400`, a hard
cap of 400, and `tol=tol_par=1e-4`. Optimization stops earlier when converged.
The FR09 p50 reference converged in 103 iterations under these tolerances, so
the new cap preserves its effective optimization budget while avoiding a
nominal 1000-iteration contract. A transferred warm start never removes the
requirement for a cold finalist confirmation when the design itself changed.

Runtime artifacts remain under ignored `local_trackers/runtime_configs/`.
Tracked source, tests, template, and this note are sufficient to reproduce how
those artifacts are constructed.

For the linked Stage-A launch, the preparer also copies the SHA-verified
baseline `application_panel.rds` into the owned common cache and validates the
fit/design retention policy required by post-analysis before it writes an
authorized manifest. The active runtime root is:

```text
local_trackers/runtime_configs/glofas_p50_linked_d1d2_stage_a_20260811
```

The scheduler is pinned to 20 one-thread workers on reviewed cores 40--59.
`scheduler_state.csv`, per-candidate status files, and worker logs are the
authoritative live-health surfaces. `prelaunch_incident_resolution.csv` records
two launch-contract failures that were caught before model computation and the
source-level corrections applied before the production launch.

## Checklist

- [x] Audit existing two-block data, seed, lag, prior, warm-start, and scoring contracts.
- [x] Add backward-compatible block-specific reservoir/input/readout resolution.
- [x] Use block-specific configs in historical and future feature construction.
- [x] Align different block washouts by a common maximum.
- [x] Add semantic warm-start fingerprints and fail-closed strict modes.
- [x] Persist semantic contracts in newly produced latent-path fit objects.
- [x] Add deterministic staged range expansion with a candidate-count guard.
- [x] Add linked two-block profiles with an exact 120/1080 cardinality contract.
- [x] Preserve distinct seeds and RHS priors while enforcing the same DESN specification.
- [x] Add score-balanced Stage-B prior expansion with anchor-specific semantic warm starts.
- [x] Set screening and confirmation VB iteration caps to 400 at `1e-4` tolerances.
- [x] Add inert-by-default runtime preparation and provenance manifests.
- [x] Add constrained historical/forecast ranking without p50-as-CRPS language.
- [x] Prohibit automatic full7 launch and automatic promotion.
- [x] Freeze exact FR09 source artifacts, metrics, promoted status, and engine.
- [x] Derive and verify the legacy FR09 semantic warm-start contract.
- [x] Add an audit-only preflight that cannot launch candidates.
- [x] Investigator supplies and approves screening parameter ranges.
- [x] Recheck authoritative baseline paths and hashes at materialization time.
- [x] Materialize and review the 120-candidate Stage-A manifest.
- [x] Obtain explicit Stage-A launch authorization.
- [x] Launch 20 pinned Stage-A workers after live resource and contract checks.
- [ ] Complete the p50 screen and inspect diagnostics.
- [ ] Cold-refit any warm-started finalist.
- [ ] Run full seven-quantile confirmation for a qualifying candidate.
- [ ] Compare genuine forecast and observational-window CRPS before promotion.
