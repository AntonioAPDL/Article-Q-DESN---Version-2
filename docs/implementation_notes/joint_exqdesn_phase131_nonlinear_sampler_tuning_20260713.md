# Phase131 Joint exQDESN exAL-RHS Nonlinear Sampler Tuning

## Purpose

Phase131 targets the remaining MCMC mixing weakness in the Joint exQDESN exAL-RHS
confirmation layer. Phase130 showed that longer chains and 12 parallel chains materially
improved the two Phase129 weak cases, but did not fully repair the nonlinear reservoir-friendly
scenario at tau 0.25:

- student-t location-scale, tau 0.75: Rhat/ESS improved to review-acceptable levels;
- nonlinear reservoir-friendly, tau 0.25: gamma/sigma Rhat remained above the review
  threshold, despite ESS improving substantially.

The Phase130 nonlinear trace summaries show chain-separated gamma/sigma means at tau 0.25.
This pattern is consistent with a slow gamma-sigma ridge rather than a burn-in failure.
Phase131 therefore focuses on sampler tuning for that one localized posterior geometry.

## Design

Phase131 is implemented by:

- extending `app_joint_qvp_fit_exal_mcmc_tiny()` with a backward-compatible
  `gamma_slice_max_steps` argument;
- extending the existing gamma-width runner to optionally override the gamma slice-width
  multiplier at a single target tau;
- adding a Phase131 meta-runner that executes a small set of nonlinear tau-0.25 variants and
  writes an aggregate recommendation.

The default Phase131 variants are:

| Variant | Base width multiplier | Tau-0.25 width multiplier | Gamma slice max steps |
|---|---:|---:|---:|
| `baseline_w4_s100` | 4 | none | 100 |
| `target_w8_s100` | 4 | 8 | 100 |
| `target_w12_s100` | 4 | 12 | 100 |
| `target_w8_s300` | 4 | 8 | 300 |
| `target_w12_s300` | 4 | 12 | 300 |

Each variant is written as a complete child artifact under the Phase131 artifact directory. The
Phase131 parent artifact then records variant status, target diagnostics, and a conservative
recommendation.

## Default Command

```bash
Rscript application/scripts/136_run_joint_exqdesn_exal_phase131_nonlinear_sampler_tuning.R
```

Default output:

```text
application/cache/joint_qdesn_phase131_nonlinear_tau025_sampler_tuning_20260713
```

The default run is a targeted tuning packet, not a final article promotion packet. It uses
six chains per variant and 6000 iterations per chain to rank variants efficiently before any
longer confirmation run.

## Outputs

The parent Phase131 directory writes:

- `run_config.csv`;
- `variant_registry.csv`;
- `phase130_target_reference.csv`;
- `variant_summary.csv`;
- `phase131_recommendation.csv`;
- `provenance.csv`;
- `README.md`;
- `artifact_manifest.csv`;
- one complete child artifact directory per variant under `variants/`.

The child artifacts are produced by the existing gamma-width packet runner and therefore include
trace summaries, Rhat/ESS summaries, chain mean gaps, autocorrelation summaries, runtime summaries,
diagnostic PDFs, provenance, and manifests.

## Gates

Hard fail:

- missing or malformed child manifests;
- preparation or chain worker failures;
- missing or non-finite target tau gamma/sigma diagnostics.

Review:

- target gamma/sigma Rhat remains above 1.2;
- target ESS remains below 100;
- gamma lag-1 autocorrelation remains high, even if Rhat/ESS are acceptable;
- large chain-mean separation remains in gamma or sigma.

Pass:

- implementation gates pass;
- target gamma/sigma Rhat is at most 1.2;
- target gamma/sigma ESS is at least 100.

High autocorrelation is treated as review evidence, not a hard failure, because the goal is
article-quality MCMC confirmation rather than perfect independent sampling.

## Interpretation

If one variant clearly improves nonlinear tau-0.25 Rhat and chain-mean separation, the next
stage should rerun only that nonlinear case with a longer confirmation packet. If no slice-width
or stepping-budget variant materially improves the target cell, the next implementation step
should be a joint gamma-sigma update for each tau rather than more burn-in or blind thinning.

Phase131 does not mutate article tables or figures.
