# Independent Q--DESN native catalog and historical feature comparison

## What this source provides

`scripts/ind_qdesn_native_catalog.R` contains three pure functions. It does
not read fitted payloads, call a fitter, generate draws, reconstruct a
reservoir, launch work or authenticate an external source.

- `ind_qnc_requests(contracts)` checks the frozen 78 Q--DESN chain requests:
  26 specification groups, three chains each; 18 forecast-MAE groups and
  eight additional forecast-check groups. It records the historical root
  refit flag without treating it as current permission. Task-level refitting
  must be false. All request counts remain explicitly unverified against
  payloads.
- `ind_qnc_extract(payload,case,contract)` extracts all 20,000 native
  beta/sigma/gamma rows of one source-defined chain, without using historical
  1,000/4,000 metric-draw labels. Original rows map to retained iterations
  5001--25000 and carry equal within-model weight 1/60,000. It validates
  native likelihood, support, saved/requested prior-family declarations,
  dimensions and the retained training-row map. Matching declared prior
  family is not a posterior-target correctness audit.
- `ind_qnc_feature_replay(reference,replay)` compares compact, explicitly
  supplied historical feature fixtures and replay values, including native
  row/column order, fixed metadata, response transformations represented in
  that metadata, and observed-origin layer states. Missing fixtures block
  the comparison rather than generating arbitrary reservoir weights.

## Source-supported payload shape

The archived c72/d6bc pipeline stores the static fit at
`forecast_objects$fits_fc[[1]]$fit_train$fit`, with fitting-row and design
metadata at `fit_train$meta$keep_idx` and `fit_train$meta$fit_meta`.
The source `R/exal_mcmc_fit.R` returns `samp.beta` as native-row-by-coefficient,
paired `samp.sigma`/`samp.gamma`, `X`, `control`, `p0`, `likelihood_family`
and `beta_prior`. These exact fields are required; there is no fuzzy search,
transpose guess, fallback to metric draws or namespace substitution.

The native sampler may leave beta column names absent while retaining names
on X. In that case the catalog preserves both name fields as saved and the
original native matrix positions; it does not manufacture names. If both
sets of names exist, they must agree. The original source stores each beta
vector in that native matrix order; authentic feature replay must still
prove the corresponding design and scaling.

This code has not loaded any of the 78 actual large fitted payloads. Exact
native counts, source payload hashes, state/feature context, training series
and original parameter weights still require bounded authentic enrollment.
The nominal 1.56 million Q--DESN native rows are requested counts, not a
completed catalog. Extraction results retain false source-authentication,
feature-replay and production flags. Their source and prior metadata are
evidence for a later audit, not a claim that a historical fit is correct.

## Feature-comparison schema and read-only CLI

Each compact reference/replay object has exactly these fields:

```
schema_version = "ind_qdesn_feature_values_v1"
source_commit, fit_sha256
X_fit, y_fit, keep_idx, fit_meta
origin_states = list(original_origin_id = list(
  prefix_source_end = original_observed_prefix_end,
  layers = list(original_layer_id = native_numeric_state_array)))
```

The native arrays, indices and metadata must come from authentic retained
evidence or a separately qualified source reconstruction. They are not
available merely because a seed and configuration exist. The comparator
does not generate this reference, call the historical pipeline, or use any
forecast-period truth. In particular, sourcing `pipeline_sim_main.R` would
execute fitting and is not an acceptable way to populate a fixture.

`scripts/check_ind_qdesn_feature_replay.R` compares two explicitly pinned
compact RDS fixtures, each no larger than 8 MiB, through:

```
Rscript scripts/check_ind_qdesn_feature_replay.R \
  --reference /absolute/reference.rds --reference-sha256 FULL_SHA256 \
  --replay /absolute/replay.rds --replay-sha256 FULL_SHA256
```

The files must be nonsymlinked and immutable during the comparison. The
result says `FEATURE_VALUES_MATCH_REFERENCE_PROVENANCE_NOT_AUTHENTICATED`.
Matching values/hashes cannot establish that a purported reference is the
authentic historical reference. That provenance must be supplied and checked
through the coordinator's source/producer contracts. This CLI is not an
enrollment, numerical qualification, fitting or production launcher.

## Remaining gates

The new focused synthetic test checks complete group requests, native row
pairing and weights, rejection of metric-sized subsets, likelihood/support,
prior-family mismatches, missing context, feature/order/scaling differences,
origin-state differences, source pins, CLI arguments and missing fixtures.
It uses no authentic model, data, forecast or future truth.

A05/B08 can advance using this source without waiting for the new dynamic
filter, but authentic payload enrollment and reconstruction of historical
features remain incomplete. A bounded collector must bind every original
payload/request/source manifest, read one fit at a time, validate its actual
row counts and raw/transformed training data, write compact native blocks,
and authenticate a genuine design/origin-state reference before claiming
feature replay. Its resource limits depend on the actual coefficient counts
and input sizes; the dynamic catalog's small two-scalar output cap is not a
valid assumed Q--DESN budget. Missing context remains a reported blocker.

Do not alter old fits, priors, seeds, selected specifications, runtime
repositories or historical metadata to satisfy these checks. Confirmed
fitted-target issues require a separate scientific-owner decision. No refit,
new VB approximation, forecast reconstruction or article replacement is
authorized or established by this source-only contribution.
