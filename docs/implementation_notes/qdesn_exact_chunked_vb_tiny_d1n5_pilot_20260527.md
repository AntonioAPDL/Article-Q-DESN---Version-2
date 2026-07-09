# Q-DESN Exact Chunked VB Tiny D1N5 Pilot

Date: 2026-05-27

## Purpose

This note records a cheap real-data article-side pilot for exact chunked
latent-path AL-VB. The full-spec Dec. 25 pilot is too expensive for repeated
development checks, so this gate keeps the same application data path and
posterior-draw contract but reduces the design to D=1 and n=5.

This is an exact chunking gate. It does not implement or validate stochastic,
hybrid, exAL approximate, article approximate, or multivariate batching.

## Repo State

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- pre-pilot HEAD: `868a8e8 Add PriceFM data pipeline pilot`
- relevant prior exact-chunked pilot commit:
  `81a60f9 Add full-spec exact chunked VB pilot comparison`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- engine commit used by the original tiny pilot run:
  `73c043f0436b508808366f312350fd44c2d06771`
- engine commit pinned after the package stochastic AL implementation:
  `246554eea52cc5c2f1e5f4f515f7897ae4075b86`
- engine commit pinned after the package comparison harness:
  `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`

Unrelated local PriceFM work was left untouched.

## Configs

Tracked tiny pilot configs:

- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml`
- `application/config/model_grid_latent_path_al_vb_dec25_tiny_d1n5_pilot.csv`

Both YAML files use the authoritative Dec. 25 input bundle:

- `application/config/input_bundle_authoritative_dec25.yaml`

The pilot is made economical by:

- limiting the history panel to 365 rows
- using the Dec. 25 latent smoke cutoffs and horizons 1:2
- limiting ensemble members per horizon to 2
- setting reservoir `D: 1`, `n: [5]`, `n_tilde: []`, and `m: 5`
- using lag and covariate windows 0:5 or 1:5
- capping VB at `max_iter: 3`
- using `n_samp_xi: 50` and `n_draws: 32`

The exact-chunked twin differs from the unchunked twin only by the controlled
chunking block and deliberately separate application/cache metadata:

```yaml
chunking:
  enabled: true
  mode: exact
  chunk_size: 512
  order: sequential
  trace: false
```

## Commands

Logs and result objects were written to the ignored local directory:

`application/logs/exact_chunked_vb_tiny_d1n5_20260527/`

Unchunked fit:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml \
  --label tiny_d1n5_unchunked \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527 \
  > application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked.console.log 2>&1
```

Exact-chunked fit:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml \
  --label tiny_d1n5_exact_chunked \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527 \
  > application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked.console.log 2>&1
```

Paired comparison:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode compare \
  --left_result application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked__fit_state.rds \
  --right_result application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked__fit_state.rds \
  --left_time_log application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_unchunked.time.log \
  --right_time_log application/logs/exact_chunked_vb_tiny_d1n5_20260527/tiny_d1n5_exact_chunked.time.log \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_20260527 \
  --comparison_prefix paired_tiny_d1n5_exact_chunked \
  --comparison_title 'Exact Chunked VB Tiny D1N5 Pilot Comparison' \
  --tolerance 1e-7
```

## Results

The tiny real-data pair passed the fitted-state equivalence gate.

| Quantity | Unchunked | Exact Chunked |
| --- | ---: | ---: |
| wall time | 18.61 s | 18.38 s |
| fit elapsed time | 9.951 s | 9.696 s |
| max RSS | 139,776 KB | 139,908 KB |
| fixed historical rows | 670 | 670 |
| stacked rows | 676 | 676 |
| augmented features | 12 | 12 |
| VB iterations | 3 | 3 |
| converged | false | false |
| posterior identity max abs | 0 | 0 |
| no-leakage audits checked | 3 | 3 |
| future covariance min eigenvalue | 0.0177246589125717 | 0.0177246589125717 |

Comparison gate:

| Metric | Max abs diff | Gate |
| --- | ---: | --- |
| theta_mean | 3.98570065840431e-14 | pass |
| theta_cov | 5.12827627585644e-17 | pass |
| sigma_mean | 3.19189119579733e-16 | pass |
| sigma_shape | 0 | pass |
| sigma_rate | 1.63424829224823e-13 | pass |
| y_future_mean | 2.94209101525666e-15 | pass |
| y_future_cov | 5.89805981832114e-17 | pass |
| elbo_trace | 1.71951342053944e-12 | pass |

Overall maximum gated difference: `1.71951342053944e-12`, below the
`1e-7` tolerance.

The two cleaned configs were equivalent after removing the intentional
application name, description, cache, chunking, and launch-note differences.
They used the same engine SHA, design hash, model id, fit id, and cutoff id.

## Package 246554e Repin Check

After package stochastic AL VB was implemented, the tiny D1N5 twins were
repinned to package commit:

`246554eea52cc5c2f1e5f4f515f7897ae4075b86`

The twin config structure check passed after removing only the intended
application name, description, cache, chunking, prelaunch, and launch-note
differences.

Logs and result objects were written to the ignored local directory:

`application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/`

Rerun commands:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_unchunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_unchunked_pilot.yaml \
  --label tiny_d1n5_unchunked_pkg246554e \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527 \
  > application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_unchunked.console.log 2>&1

/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_exact_chunked.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_tiny_d1n5_exact_chunked_pilot.yaml \
  --label tiny_d1n5_exact_chunked_pkg246554e \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527 \
  > application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_exact_chunked.console.log 2>&1

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode compare \
  --left_result application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_unchunked_pkg246554e__fit_state.rds \
  --right_result application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_exact_chunked_pkg246554e__fit_state.rds \
  --left_time_log application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_unchunked.time.log \
  --right_time_log application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527/tiny_d1n5_exact_chunked.time.log \
  --output_dir application/logs/exact_chunked_vb_tiny_d1n5_pkg246554e_20260527 \
  --comparison_prefix paired_tiny_d1n5_pkg246554e_exact_chunked \
  --comparison_title 'Exact Chunked VB Tiny D1N5 Pilot Comparison on Package 246554e' \
  --tolerance 1e-7
```

The rerun passed the fitted-state equivalence gate.

| Quantity | Unchunked | Exact Chunked |
| --- | ---: | ---: |
| wall time | 19.33 s | 18.11 s |
| fit elapsed time | 10.775 s | 10.046 s |
| max RSS | 140,012 KB | 140,108 KB |
| VB iterations | 3 | 3 |
| converged | false | false |
| posterior identity max abs | 0 | 0 |
| no-leakage audits checked | 3 | 3 |
| future covariance min eigenvalue | 0.0177246589125717 | 0.0177246589125717 |

Comparison gate:

| Metric | Max abs diff | Gate |
| --- | ---: | --- |
| theta_mean | 3.98570065840431e-14 | pass |
| theta_cov | 5.12827627585644e-17 | pass |
| sigma_mean | 3.19189119579733e-16 | pass |
| sigma_shape | 0 | pass |
| sigma_rate | 1.63424829224823e-13 | pass |
| y_future_mean | 2.94209101525666e-15 | pass |
| y_future_cov | 5.89805981832114e-17 | pass |
| elbo_trace | 1.71951342053944e-12 | pass |

Overall maximum gated difference: `1.71951342053944e-12`, below the
`1e-7` tolerance. The rerun used the same engine SHA, design hash, model id,
fit id, and cutoff id across the paired configs.

## Package 37bdd3a Comparison-Harness Repin Check

After the package comparison harness was added, the tiny D1N5 twins were
repinned to package commit:

`37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`

This package commit is a comparison-harness commit on top of the stochastic AL
implementation; it does not change the LDVB engine logic. The rerun keeps the
article source-policy gate aligned with the checked-out shared validation
package branch.

Logs and result objects were written to the ignored local directory:

`application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/`

The rerun passed the fitted-state equivalence gate.

| Quantity | Unchunked | Exact Chunked |
| --- | ---: | ---: |
| wall time | 20.48 s | 21.31 s |
| fit elapsed time | 11.447 s | 11.851 s |
| max RSS | 140,068 KB | 139,784 KB |
| VB iterations | 3 | 3 |
| converged | false | false |
| posterior identity max abs | 0 | 0 |
| no-leakage audits checked | 3 | 3 |
| future covariance min eigenvalue | 0.0177246589125717 | 0.0177246589125717 |

Comparison gate:

| Metric | Max abs diff | Gate |
| --- | ---: | --- |
| theta_mean | 3.98570065840431e-14 | pass |
| theta_cov | 5.12827627585644e-17 | pass |
| sigma_mean | 3.19189119579733e-16 | pass |
| sigma_shape | 0 | pass |
| sigma_rate | 1.63424829224823e-13 | pass |
| y_future_mean | 2.94209101525666e-15 | pass |
| y_future_cov | 5.89805981832114e-17 | pass |
| elbo_trace | 1.71951342053944e-12 | pass |

Overall maximum gated difference: `1.71951342053944e-12`, below the
`1e-7` tolerance. The rerun used the same engine SHA, design hash, model id,
fit id, and cutoff id across the paired configs.

## Interpretation

The tiny D1N5 pilot confirms that article-side exact chunking preserves the
full-data latent-path AL-VB fitted state on the real application data path when
the design is small enough for cheap repeated checks. This gives us an
economical regression gate for exact chunking.

It does not replace the full-spec manuscript gate. The full-spec exact-chunked
pilot recorded in
`docs/implementation_notes/qdesn_exact_chunked_vb_fullspec_pilot_20260527.md`
still failed before writing a fitted state, and the main Dec. 25 configuration
should remain unchunked until that larger gate is diagnosed or replaced by a
validated production-scale alternative.

## Ready State

Use this tiny pair for fast article-side exact chunking checks while developing
or reviewing subsequent batching changes.

Stochastic or hybrid mini-batch VB remains unavailable for the article
GloFAS latent-path application. Any approximate package-level AL work should
continue to follow the derivation contract in
`docs/implementation_notes/qdesn_vb_batching_derivations_20260527.md` and must
remain clearly labeled approximate.
