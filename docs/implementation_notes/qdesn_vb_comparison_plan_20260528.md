# Q-DESN VB Comparison Plan

Date: 2026-05-28

## Purpose

This plan defines comparison-ready examples for the VB batching methods that
are already implemented. It intentionally excludes methods that remain gated.

Source-of-truth derivation:

- `docs/implementation_notes/qdesn_vb_batching_derivations_20260527.md`

Availability note:

- `docs/implementation_notes/qdesn_vb_method_availability_20260528.md`

## Tier A: Package Synthetic/Static and Q-DESN Examples

Script:

- package repo:
  `scripts/run_qdesn_vb_batching_comparison_20260528.R`

Default command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/usr/bin/time -v \
  -o results/qdesn_vb_batching_comparison_20260528/package_comparison.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_batching_comparison_20260528.R \
  --output-dir results/qdesn_vb_batching_comparison_20260528 \
  --seed 20260528 \
  > results/qdesn_vb_batching_comparison_20260528/package_comparison.console.log 2>&1
```

Output path:

- `results/qdesn_vb_batching_comparison_20260528/`

This path is ignored by the package repo. The script writes:

- `repo_state.csv`
- `method_summary.csv`
- `exact_equivalence.csv`
- `stochastic_diagnostics.csv`
- `forbidden_modes.csv`
- `qdesn_vb_batching_comparison_summary.md`

### Static AL

- dataset: synthetic static readout with `n = 100`,
  `X = [1, x, x^2]`, beta `(0.2, 0.6, -0.3)`, Gaussian noise sd `0.08`
- seed: `20260528`
- likelihood family: `al`
- controls:
  - unchunked: `max_iter = 35`, `n_samp_xi = 32`, ridge tau2 `50`
  - exact chunked: same plus `chunking = list(enabled = TRUE, mode = "exact",
    chunk_size = 17)`
  - stochastic: `max_iter = 80`, `mode = "stochastic"`, `chunk_size = 20`,
    `order = "random"`, Robbins-Monro learning rate, periodic full/local/sigma
    and RHS refreshes
- exact equivalence gate: max fitted-state difference <= `1e-7`
- stochastic diagnostics: finite state, stochastic trace present, approximate
  note present, max beta mean distance <= `0.25`
- runtime/memory: per-fit elapsed seconds from R; whole-script peak RSS from
  `/usr/bin/time -v`

### Static exAL

- dataset: same static synthetic data
- likelihood family: `exal`
- controls:
  - unchunked: `max_iter = 35`, `n_samp_xi = 32`, ridge tau2 `50`
  - exact chunked: same plus exact chunking
- exact equivalence gate: max fitted-state difference <= `1e-7`
- excluded: stochastic exAL must fail early with an AL-only message

### Univariate Q-DESN AL

- dataset: synthetic smooth series
  `0.2 * sin(t / 3) + 0.05 * cos(t / 5)`, `t = 1,...,30`
- reservoir: `D = 1`, `n = 4`, `m = 1`, `washout = 4`, `add_bias = TRUE`
- reservoir seed: `20260532`
- likelihood family: `al`
- controls:
  - unchunked: `max_iter = 20`, `n_samp_xi = 16`, ridge tau2 `10`
  - exact chunked: same plus exact chunking with `chunk_size = 5`
  - stochastic: `max_iter = 40`, stochastic chunking with `chunk_size = 5`
    and seed `43`
- exact equivalence gate: same DESN design and max fitted-state difference
  <= `1e-7`
- stochastic diagnostics: finite state, approximate label, stochastic trace,
  max beta mean distance <= `0.25`

### Univariate Q-DESN exAL

- dataset and reservoir: same smooth synthetic Q-DESN setup
- reservoir seed: `20260533`
- likelihood family: `exal`
- controls:
  - unchunked: `max_iter = 20`, `n_samp_xi = 16`, ridge tau2 `10`
  - exact chunked: same plus exact chunking with `chunk_size = 5`
- exact equivalence gate: same DESN design and max fitted-state difference
  <= `1e-7`
- excluded: stochastic exAL is not implemented

## Tier B: Article Tiny D1N5 Real-Data Example

Use the existing article tiny gate:

- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`

Dataset/source:

- authoritative Dec. 25 GloFAS/USGS input bundle
- reduced real-data design with `D = 1`, `n = 5`, `m = 5`

Compare only:

- article latent-path AL-VB unchunked
- article latent-path AL-VB exact chunked

Default commands:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
mkdir -p application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528

/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_unchunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml \
  --label tiny_d1n5_unchunked_pkg37bdd3a \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528 \
  > application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_unchunked.console.log 2>&1

/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_exact_chunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml \
  --label tiny_d1n5_exact_chunked_pkg37bdd3a \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528 \
  > application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_exact_chunked.console.log 2>&1

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode compare \
  --left_result application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_unchunked_pkg37bdd3a__fit_state.rds \
  --right_result application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_exact_chunked_pkg37bdd3a__fit_state.rds \
  --left_time_log application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_unchunked.time.log \
  --right_time_log application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/tiny_d1n5_exact_chunked.time.log \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528 \
  --comparison_prefix paired_tiny_d1n5_pkg37bdd3a_exact_chunked \
  --comparison_title 'Exact Chunked VB Tiny D1N5 Pilot Comparison on Package 37bdd3a' \
  --tolerance 1e-7
```

Pass/fail criteria:

- same engine SHA, design hash, model id, fit id, and cutoff id
- intended config differences only
- no-leakage audits checked
- posterior draw identity max abs equals zero
- future covariance minimum eigenvalue is positive
- max fitted-state difference <= `1e-7`
- separate-process runtime and peak RSS captured by `/usr/bin/time -v`

## Explicit Exclusions

- stochastic exAL: not implemented; must fail early
- hybrid AL: not implemented; requires a separate contract
- variance-reduced SVI: deferred until stochastic/hybrid AL are stable
- streaming/posterior-as-prior: requires a posterior-state handoff contract
- article stochastic/hybrid: not implemented and not exposed in article configs
- multivariate Q-DESN: design-only for now
