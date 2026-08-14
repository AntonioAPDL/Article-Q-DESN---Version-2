# Q-DESN Exact Chunked VB Full-Spec Pilot

Date: 2026-05-27

## Scope

This note records the separate-process full-specification pilot requested after
the exact chunked VB validation pass. The goal was to compare the article
latent-path AL-VB fit with and without exact chunking using the main Dec. 25
model specification, while keeping the iteration and draw budget small enough
for a controlled pilot.

This pass did not implement stochastic, hybrid, variance-reduced, streaming, or
article-side approximate batching. Exact chunking remains full-data VB, not a
stochastic approximation.

The Overleaf/main worktree was not edited.

## Repository State

Article repo:

- Path: `/data/jaguir26/local/src/Article-Q-DESN`
- Branch: `application-ensemble-likelihood-redesign`
- Starting HEAD for this pilot pass:
  `e7a516a98a27e7d2f8db645d73af41258e781a29`
- Remote: `origin https://github.com/AntonioAPDL/Article-Q-DESN.git`
- Upstream: `origin/application-ensemble-likelihood-redesign`

Package/shared validation repo:

- Path: `/data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0`
- Branch: `validation/shared-fitforecast-v2-1.0.0`
- HEAD: `73c043f0436b508808366f312350fd44c2d06771`
- Remote: `origin git@github.com:AntonioAPDL/exdqlm.git`
- Upstream: `origin/validation/shared-fitforecast-v2-1.0.0`

Package stashes on other branches were left untouched.

## Configs and Script

Created two tracked pilot configs:

- `application/config/glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml`
- `application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml`

Both configs keep the Dec. 25 main latent-path design scale:

- authoritative Dec. 25 cutoff table
- main latent-path model grid
- `D = 2`
- `n = (1000, 1000)`
- `n_tilde = 500`
- `m = 360`
- `washout = 500`
- package engine commit `73c043f0436b508808366f312350fd44c2d06771`

Both configs bound the pilot:

- `max_iter = 5`
- `max_iter_hard_cap = 50`
- `n_samp_xi = 100`
- `n_draws = 64`
- `post_analysis.enabled = false`
- `post_analysis.run_after_outputs = false`
- `execution.prelaunch.enabled = true`
- `execution.final_launch.enabled = false`

The exact-chunked twin adds only the intended chunking block, plus descriptive
name/cache/purpose text:

```yaml
chunking:
  enabled: true
  mode: exact
  chunk_size: 512
  order: sequential
  trace: false
```

Config hashes:

| Config | SHA-256 |
| --- | --- |
| unchunked pilot | `46e4f3957868f51fdbf6f8fc86954b6c7423864fecce7c8ac3c01709c028be89` |
| exact-chunked pilot | `04916c1409448668db1d59b0262412e2d09e42b019e34ef7fb2cb988cae935c3` |

Created comparison helper:

- `application/scripts/03_compare_exact_chunked_vb_pilot.R`

The script supports:

- `--mode fit`: run one pilot config and save a compact fitted-state RDS plus
  a CSV summary.
- `--mode compare`: compare unchunked and exact-chunked fitted states and
  write CSV/Markdown summaries under the ignored local log directory.

After the exact-chunked pilot failed without a useful R traceback, the script
was hardened so future failures print a traceback before exiting.

## Commands Run

Logs were written under ignored local path:

`application/logs/exact_chunked_vb_fullspec_pilot_20260527/`

Unchunked pilot:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_unchunked_pilot.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml \
  --label fullspec_unchunked_pilot \
  --output_dir application/logs/exact_chunked_vb_fullspec_pilot_20260527 \
  > application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_unchunked_pilot.console.log 2>&1
```

Exact-chunked pilot:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_exact_chunked_pilot.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml \
  --label fullspec_exact_chunked_pilot \
  --output_dir application/logs/exact_chunked_vb_fullspec_pilot_20260527 \
  > application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_exact_chunked_pilot.console.log 2>&1
```

## Results

| Run | Exit | Wall time | Max RSS KB | Fit state | Notes |
| --- | ---: | ---: | ---: | --- | --- |
| Unchunked full-spec pilot | 0 | 1:50:53 | 4,925,124 | written | Completed five VB iterations. |
| Exact-chunked full-spec pilot | 1 | 2:26:34 | 4,807,296 | not written | Failed before a fitted state was saved. |

Unchunked fit summary:

- engine SHA:
  `73c043f0436b508808366f312350fd44c2d06771`
- design hash:
  `248877451b0eddde39bfba41cefe81e0f7ec2d7f3cceaace18f4a10cd58b5d6d`
- cutoff id: `dec25_2022`
- origin date: `2022-12-25`
- model id: `qdesn_latent_path_rhs_al_vb_main_p50`
- fixed rows: `24990`
- stacked rows: `26446`
- augmented features: `3002`
- VB iterations: `5`
- converged: `FALSE`, expected because this pilot intentionally caps at five
  iterations
- posterior identity max absolute error:
  `2.22044604925031e-16`
- no-leakage audits checked: `3`
- future covariance minimum eigenvalue:
  `0.00120681071455187`

Exact-chunked failure log:

```text
Timing stopped at: 8542 36.8 8787
Execution halted
```

The timed wrapper reported exit status 1. No exact-chunked fitted-state RDS was
written, so no fitted-state equivalence comparison was possible.

## Paired Comparison Gate

The paired full-spec gate did not pass.

The failure mode was not a numerical inequivalence between completed fitted
states. Instead, the exact-chunked full-spec pilot did not complete, so the
required comparison of theta moments, sigma summaries, future path moments,
ELBO trace, posterior draw identity, and no-leakage checks could not be run.

No pilot R processes remained active after the exact-chunked failure.

## Activation Decision

Do not enable exact chunking in
`application/config/glofas_latent_path_al_vb_dec25_main.yaml` from this pilot.

Reasons:

- The exact-chunked full-spec pilot exited nonzero.
- It did not write a fitted state.
- Its observed wall time before failure, 2:26:34, was longer than the
  successful unchunked pilot.
- Its peak resident set size, about 4.81 GB, was only modestly below the
  unchunked pilot's 4.93 GB.

The existing exact-chunked smoke config remains useful as a controlled
small-scale gate. Manuscript-scale Dec. 25 runs should remain unchunked unless
a later exact-chunked full-spec rerun completes and passes fitted-state
equivalence.

## Example-Comparison Readiness

Available now:

- article latent-path AL-VB unchunked
- article latent-path AL-VB exact chunked at smoke scale
- package static AL LDVB unchunked and exact chunked
- package static exAL LDVB unchunked and exact chunked
- univariate Q-DESN AL/exAL VB through `qdesn_fit_vb()` with exact chunking

Not ready from this full-spec pilot:

- article latent-path exact-chunked manuscript-scale examples
- promotion of exact chunking into the main Dec. 25 config

Still not implemented:

- stochastic mini-batch VB
- hybrid AL SVI
- variance-reduced SVI
- stochastic/hybrid exAL batching
- stochastic/hybrid article GloFAS latent-path batching
- multivariate Q-DESN batching

## Next Commands

For package-level exact-chunked examples, use focused package tests or small
synthetic examples under the shared validation exdqlm worktree.

For article-side work, the next exact-chunked command should be a diagnostic
rerun with the traceback-hardened comparison script, not a main launch:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN
/usr/bin/time -v \
  -o application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_exact_chunked_pilot_rerun.time.log \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode fit \
  --config application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml \
  --label fullspec_exact_chunked_pilot_rerun \
  --output_dir application/logs/exact_chunked_vb_fullspec_pilot_20260527 \
  > application/logs/exact_chunked_vb_fullspec_pilot_20260527/fullspec_exact_chunked_pilot_rerun.console.log 2>&1
```

Only after that rerun completes should the `--mode compare` command be run.

## Validation Checks

Post-pilot checks run with R 4.6.0:

```sh
cd /data/jaguir26/local/src/Article-Q-DESN

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/scripts/03_compare_exact_chunked_vb_pilot.R \
  --mode invalid

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript - <<'RS'
source('application/R/00_packages.R')
app_set_repo_root(getwd())
source(app_path('application/R/launch_control.R'))
clean <- function(path) {
  cfg <- app_read_yaml(path)
  cfg$application_name <- NULL
  cfg$description <- NULL
  cfg$paths$cache <- NULL
  cfg$inference$vb_ld$chunking <- NULL
  cfg$execution$prelaunch$purpose <- NULL
  cfg$execution$final_launch$note <- NULL
  cfg
}
stopifnot(identical(
  clean('application/config/glofas_latent_path_al_vb_dec25_fullspec_unchunked_pilot.yaml'),
  clean('application/config/glofas_latent_path_al_vb_dec25_fullspec_exact_chunked_pilot.yaml')
))
RS

/data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
git diff --check
```

Results:

- invalid-mode script smoke failed as expected and printed a traceback
- cleaned twin configs were identical
- `application/tests/run_tests.R` passed
- `git diff --check` passed

## Remaining Risks

- The full-spec exact-chunked article path may have a late failure in
  fixed-row chunking, source-specific sigma accumulation, posterior summary
  construction, or future-path prediction that did not surface in the smoke
  run.
- The failed pilot did not provide an R traceback because the original
  comparison script did not install an error handler.
- Exact chunking may not improve memory materially at the current full-spec
  scale because dense posterior covariance and future-path summaries still
  dominate memory.
- Stochastic or hybrid batching must remain gated by the separate derivation
  contract in
  `docs/implementation_notes/qdesn_vb_batching_derivations_20260527.md`.
