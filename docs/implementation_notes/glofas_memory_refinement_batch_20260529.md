# GloFAS Memory-Refinement Application Batch, 2026-05-29

This note documents the memory-refinement application grid centered on the
previous best engine-frozen GloFAS Q-DESN run:

`engine73c_07_flex8_d1n300_m360_a92_r95_w018_bt3em02_at3em02_skip_20260527_1722`

The reference run uses `D=1`, `n=300`, `m=360`, `alpha=0.92`, `rho=0.95`,
`pi_w=0.03`, `pi_in=1.00`, `win_scale_global=0.18`,
`win_scale_bias=0.18`, independent RHS priors with `tau0=0.03` for both
the shared-quantile and discrepancy blocks, and reservoir seed `20260512`.
Its median check loss is `0.5691`, compared with raw GloFAS `0.8754`.

## Prepared Grid

The grid deliberately stays near the winning design family. It does not broaden
to deeper or larger reservoirs because the latest evidence points to temporal
memory, not reservoir width/depth, as the strongest active lever.

| Block | Candidates | Purpose |
|---|---:|---|
| Memory expansion | 4 | Test `m=300,420,540,720` at `win=0.18` and `(tau0_beta,tau0_alpha)=(0.03,0.03)`. |
| Input scale | 3 | Test `win=0.14,0.22,0.26` at `m=360` and `(0.03,0.03)`. |
| Prior refinement | 4 | Test nearby RHS prior combinations at `m=360`, `win=0.18`. |
| Seed panel | 5 | Test seeds `20260527:20260531` for the current winning specification. |

Total prepared candidates: `16`.

## Generated Artifacts

Preparation command:

```bash
Rscript application/scripts/03_prepare_memory_refinement_batch_20260529.R
```

Launch manifest:

```text
application/config/glofas_engine73c_memory_refine16_20260529_launch_manifest.csv
```

Launch script, not run during preparation:

```bash
bash application/scripts/03_launch_memory_refinement_batch_20260529.sh
```

Default tmux session for launch:

```text
glofas_engine73c_memory_refine16_20260529
```

Default log directory:

```text
application/logs/glofas_engine73c_memory_refine16_20260529
```

## Engine Provenance

All prepared configs are pinned to the frozen application engine:

```text
/data/jaguir26/local/src/exdqlm__wt__article_app_engine_73c043f
branch: article/app-engine-73c043f
commit: 73c043f0436b508808366f312350fd44c2d06771
```

The preparation script verifies the branch, commit, and compiled shared object
before writing the manifest.

## Current Manuscript-Facing Selection

On 2026-05-31, the current manuscript-facing GloFAS application output registry
was updated to the best scored member of this grid:

```text
engine73c_memrefine16_11_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_20260529_1618
```

This selected run keeps the same reservoir family as the reference run but uses
`m=360`, `win_scale_global=0.18`, `win_scale_bias=0.18`,
`tau0_beta=0.10`, and `tau0_alpha=0.03`. Its mean median-check loss is
`0.5690012525`, compared with raw GloFAS `0.8753787276`, giving a `35.0%`
reduction over the 28 scored horizons.

The article-facing current-output aliases now point to:

```text
tables/glofas_application_current_outputs.tex
tables/glofas_application_current_score_summary.tex
tables/glofas_application_current_selection_manifest.csv
tables/glofas_application_promotion_manifest__engine73c_memrefine16_11_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_20260529_1618.csv
```

The promotion used the standard storage-light promotion scripts:

```bash
Rscript application/scripts/08_promote_application_outputs.R \
  --config application/config/glofas_latent_path_al_vb_dec25_memrefine16_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_main1000_engine73c.yaml \
  --run_id engine73c_memrefine16_11_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_20260529_1618 \
  --output_slug engine73c_memrefine16_11_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_20260529_1618 \
  --allow_required_failures true

Rscript application/scripts/09_select_application_outputs.R \
  --promotion_manifest tables/glofas_application_promotion_manifest__engine73c_memrefine16_11_d1n300_m360_a92_r95_w018_bt1em01_at3em02_skip_20260529_1618.csv
```

The explicit promotion override was required only because the frozen engine
worktree branch `article/app-engine-73c043f` has no configured upstream branch.
The engine worktree itself was clean, the engine SHA
`73c043f0436b508808366f312350fd44c2d06771` was recorded, and the engine source
policy, prediction contract, scoring, fit, and figure checks passed.

Heavy application-run objects were pruned after promotion: `.rds`, `.rda`, and
`.RData` files outside the selected run were removed from `application/runs/`.
The selected run retains its fit object, design object, and prediction-design
object for reproducibility.

## Launch Policy

Do not relaunch or extend this batch automatically. Future application
candidates should be prepared through tracked configs and promoted through the
same manifest-based registry.
