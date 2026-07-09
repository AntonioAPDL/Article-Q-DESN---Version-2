# Q-DESN VB Comparison Results

Date: 2026-05-28

## Repo State

Article repo:

- path: `/data/jaguir26/local/src/Article-Q-DESN`
- branch: `application-ensemble-likelihood-redesign`
- comparison-readiness parent: `f271463`

Package repo:

- path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- branch: `validation/shared-fitforecast-v2-1.0.0`
- comparison harness commit: `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`

The article main, exact-chunked smoke, and tiny D1N5 pilot configs are repinned
to package commit `37bdd3a24920997e7c1cd7bbd41f3ec9ec659da3`.

## Tests Run

Package focused tests:

| Test file | Result |
| --- | ---: |
| `test-exal-exact-chunking-stats.R` | 38 pass |
| `test-exal-likelihood-family-al.R` | 35 pass |
| `test-exal-inference-config.R` | 203 pass |
| `test-qdesn-vb-likelihood-family.R` | 12 pass |
| `test-exal-stochastic-al-vb.R` | 38 pass |
| `test-exal-batching-controls.R` | 49 pass |
| `test-qdesn-vb-batching-modes.R` | 20 pass |
| `test-static-beta-prior-rhs.R` | 110 pass |

Article tests:

- `application/tests/run_tests.R`: pass

Checks:

- package `git diff --check`: pass
- article `git diff --check`: pass

## Package Comparison Command

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

Whole-script timing:

- wall time: 39.64 s
- max RSS: 513,108 KB
- exit status: 0

## Package Method Summary

| Method | Likelihood | Chunking | Iter | Runtime | Finite |
| --- | --- | --- | ---: | ---: | --- |
| static AL unchunked | AL | none | 35 | 2.193 s | true |
| static AL exact chunked | AL | exact | 35 | 11.085 s | true |
| static AL stochastic | AL | stochastic | 80 | 1.340 s | true |
| static exAL unchunked | exAL | none | 35 | 1.728 s | true |
| static exAL exact chunked | exAL | exact | 35 | 1.583 s | true |
| Q-DESN AL unchunked | AL | none | 20 | 0.226 s | true |
| Q-DESN AL exact chunked | AL | exact | 20 | 3.613 s | true |
| Q-DESN AL stochastic | AL | stochastic | 40 | 0.485 s | true |
| Q-DESN exAL unchunked | exAL | none | 20 | 0.775 s | true |
| Q-DESN exAL exact chunked | exAL | exact | 20 | 0.670 s | true |

These runtimes are small-example diagnostics, not performance benchmarks.

## Exact Chunking Equivalence

Tolerance: `1e-7`.

| Pair | Max gate diff | Passed |
| --- | ---: | --- |
| static AL unchunked vs exact chunked | 7.48545669893019e-12 | true |
| static exAL unchunked vs exact chunked | 7.16182599336257e-08 | true |
| Q-DESN AL unchunked vs exact chunked | 7.2325756494962e-11 | true |
| Q-DESN exAL unchunked vs exact chunked | 1.59978741365308e-09 | true |

The Q-DESN exact comparisons also verified identical DESN design matrices.

## Stochastic AL Diagnostics

Stochastic AL is approximate. These diagnostics do not claim full-data
equivalence.

| Pair | Max beta mean diff | Max beta variance diff | Trace rows | Passed |
| --- | ---: | ---: | ---: | --- |
| static AL unchunked vs stochastic | 0.0062932487955723 | 5.44727068440161e-05 | 80 | true |
| Q-DESN AL unchunked vs stochastic | 0.000218509118924803 | 0.000146811349807805 | 40 | true |

Both stochastic fits were finite, carried `misc$stochastic = TRUE`, and stored
an approximate-objective note.

Stochastic exAL was attempted as a forbidden-mode check and failed early with:

`stochastic VB chunking is currently supported only for likelihood_family = 'al'.`

## Article Tiny D1N5 Comparison

The article tiny real-data gate was rerun after repinning configs to package
`37bdd3a`.

Output path:

`application/logs/exact_chunked_vb_tiny_d1n5_pkg37bdd3a_20260528/`

| Quantity | Unchunked | Exact chunked |
| --- | ---: | ---: |
| wall time | 20.48 s | 21.31 s |
| fit elapsed time | 11.447 s | 11.851 s |
| max RSS | 140,068 KB | 139,784 KB |
| VB iterations | 3 | 3 |
| converged | false | false |
| posterior identity max abs | 0 | 0 |
| no-leakage audits checked | 3 | 3 |
| future covariance min eigenvalue | 0.0177246589125717 | 0.0177246589125717 |

Equivalence gate:

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

Overall max gate diff: `1.71951342053944e-12`, below `1e-7`.

The pair used the same engine SHA, design hash, model id, fit id, and cutoff
id. The cleaned configs differed only by intended metadata/cache/chunking
fields.

## Excluded Methods

- stochastic exAL: gated; fails early
- hybrid AL: not implemented; requires a separate full-refresh contract
- variance-reduced SVI: deferred
- streaming/posterior-as-prior VB: requires a state handoff contract
- article stochastic/hybrid batching: not implemented and not exposed in
  article configs
- multivariate Q-DESN: not implemented

## Readiness Decision

We are ready to run a user-chosen comparison example across all currently
implemented approaches:

- Tier A package synthetic/static and Q-DESN comparisons can include AL
  unchunked, AL exact chunked, AL stochastic, exAL unchunked, and exAL exact
  chunked.
- Tier B article real-data comparison can include only latent-path AL-VB
  unchunked and exact chunked on the tiny D1N5 gate.

No comparison should present stochastic/hybrid exAL, article stochastic/hybrid,
variance-reduced, streaming, or multivariate methods as available.

## Next Commands

Package comparison:

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

Article tiny D1N5 comparison:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
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
