# GloFAS structural-screen closeout

Date: 2026-08-23

## Scope

This closeout applies to the p50 structural campaign
`glofas_p50_structural_memory_geometry_20260821`. It does not change the
authoritative FR09 application result, launch a seven-quantile fit, or alter
another scientific lane.

## Two-block row alignment

The reference/shared-quantile and discrepancy DESNs are separate reservoirs
with different inputs, seeds, feature maps, and regularized-horseshoe priors.
They must nevertheless represent the same ordered response dates when their
features are combined in one likelihood.

`app_feature_contract_common_history_alignment()` computes one common history
drop from the requested washout and the largest operative reservoir or direct
readout lag in either block. Both blocks are then constructed on that support.
The design stores a `row_alignment` table with each block requirement, the
requested drop, and the effective common drop. Existing equal-memory designs
retain the same design-hash inputs because this metadata is not added to
`app_hash_latent_path_design()`.

## Closeout modes

The strict finalizer remains the only scientific decision path:

```bash
Rscript application/scripts/glofas_constrained_median_screen_finalize.R \
  --output_root <runtime-root> \
  --mode strict \
  --cleanup false
```

Strict mode refuses any failed, running, or unknown candidate. Forensic mode is
an operational diagnostic only. It writes under `forensic_closeout/`, labels
the ranking partial, prohibits cleanup, and cannot authorize promotion:

```bash
Rscript application/scripts/glofas_constrained_median_screen_finalize.R \
  --output_root <runtime-root> \
  --mode forensic \
  --cleanup false
```

The orchestrator automatically attempts this forensic closeout after an error,
without converting failures into terminal scientific results.

Failed candidates can be selectively resumed with:

```bash
bash application/scripts/glofas_constrained_median_screen_resume.sh \
  <runtime-root> <runtime-manifest> <max-parallel> <core-list> \
  <max-load> <min-memory-gb> <min-disk-gb> true false
```

The scheduler's `--retry-failed` contract preserves all completed and
preflight-rejected markers and schedules only failed, non-running rows.

## Statistical closeout

After strict completion, run:

```bash
Rscript application/scripts/glofas_p50_structural_closeout_audit.R \
  --output_root <runtime-root>
```

The audit compares the final top candidates with FR09, the focused p50 anchor,
and the warm/cold controls using identical horizon keys. It reports paired
check-loss differences and a deterministic circular moving-block bootstrap.
A cold confirmation is warranted only when all frozen historical, technical,
and three-percent FR09 gates pass, the paired confidence interval excludes no
improvement, and the gain exceeds the observed warm/cold repeatability
envelope. P50 check loss is never reported as CRPS.

## Reservoir policy audit

The campaign's original preflight decisions remain frozen as
`reservoir_preflight_v1`. The policy audit reconstructs absolute effective rank,
reports rank relative to controls, and separates rank-only, saturation, dead
state, and conditioning causes:

```bash
Rscript application/scripts/glofas_reservoir_preflight_policy_audit.R \
  --output_root <runtime-root>
```

`low_effective_rank_action = "repair"` is available for a prospective v2
campaign. It does not reinterpret this campaign. Nonfinite states, saturation,
dead states, conditioning, spectral instability, and forgetting remain hard
gates. Chronological cheap validation should be enabled prospectively before a
v2 rule is used for launches.

## Retention

Strict cleanup protects, at minimum, the top two fitted candidates and all
control-role candidates. Explicit candidate IDs can be added with
`--protect_candidate_ids`. Protected heavy artifacts are SHA-256 inventoried
before any deletion. Nonprotected fit/design objects may be removed only after
strict completion; compact configs, manifests, scores, diagnostics, figures,
logs, hashes, and selection tables remain.

## Promotion gate

No p50 candidate is article-authoritative. A candidate must first pass cold p50
confirmation and seed robustness, then complete seven independent quantile
fits, genuine distributional CRPS scoring, tail/synthesis diagnostics, and a
separate article-integration review. Until those gates pass, FR09 remains the
article result and article files stay unchanged.
