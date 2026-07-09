# Q-DESN Hybrid AL VB Stage

Date: 2026-05-28

## Scope

This note records the Stage 4 package implementation of hybrid AL VB with
periodic full refresh. It is package-first and applies to the static/readout
and univariate Q-DESN AL paths only. Article GloFAS stochastic/hybrid controls
remain unavailable.

## Package Commits

- `685d2f5fcf789dd65495223f6b6f2dfa59a5cf22`: implements `chunking$mode =
  "hybrid"` for AL, keeps exAL approximate modes forbidden, and adds focused
  tests.
- `c51e9da4508f6fb89a73f8b78e08f9d80604e11a`: extends the TT500 source
  comparison harness to run AL hybrid and repeat checks.

## Contract

Hybrid AL reuses the existing stochastic mini-batch sampler and damped data
natural-stat machinery between full refreshes. On full-refresh iterations it
resets beta data natural statistics to the exact full-data statistics, refreshes
local moments, updates sigma through the existing AL fixed-gamma LD path, and
keeps RHS/RHS_NS updates global. It is approximate unless every iteration is a
full refresh.

Unsupported modes still fail early:

- stochastic or hybrid exAL;
- article GloFAS stochastic/hybrid batching;
- stochastic or hybrid warm starts.

## Tests

Package focused regression passed after the implementation:

- `test-exal-exact-chunking-stats.R`: 38 passes
- `test-exal-likelihood-family-al.R`: 35 passes
- `test-exal-inference-config.R`: 203 passes
- `test-qdesn-vb-likelihood-family.R`: 12 passes
- `test-exal-batching-controls.R`: 61 passes
- `test-exal-stochastic-al-vb.R`: 38 passes
- `test-exal-hybrid-al-vb.R`: 33 passes
- `test-qdesn-vb-batching-modes.R`: 28 passes
- `test-static-beta-prior-rhs.R`: 110 passes
- `test-qdesn-vb-simplification-ladder.R`: 33 passes
- `test-qdesn-vb-warm-start.R`: 39 passes

Total focused package assertions: 630.

## TT500 Source Gate

Command:

```sh
cd /data/jaguir26/local/src/exdqlm__wt__shared_fitforecast_v2_1p0p0
/usr/bin/time -v /data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/run_qdesn_vb_batching_comparison_source_tt500_median_20260528.R \
  --output-dir results/qdesn_vb_hybrid_al_tt500_gate_20260528 \
  --output-prefix qdesn_vb_hybrid_al_tt500_gate \
  --seed 20260528 --D 1 --n 20 --m 1 --washout 50 --chunk-size 64 \
  --max-iter 15 --stochastic-max-iter 30 --hybrid-max-iter 30 \
  --hybrid-full-every 5 --cores 1
```

Result: passed.

- Source rows: 500
- Effective post-washout rows: 450
- Exact AL max gate difference: `3.5313973967277e-11`
- Exact exAL max gate difference: `8.272991181002e-10`
- Hybrid AL fixed-seed repeat beta/fitted differences: `0`
- Hybrid AL finite state: `TRUE`
- Hybrid exAL forbidden mode failed early: `TRUE`
- Runtime: 34.93 seconds
- Peak RSS: 526708 KB

The source gate is economical and does not replace a larger comparison run.

## Article Impact

Article configs are repinned to package commit
`c51e9da4508f6fb89a73f8b78e08f9d80604e11a` for reproducibility. The repin does
not expose article stochastic or hybrid controls. Article-side batching remains
unchunked or exact chunked only.

## Article Tiny D1N5 Repin Gate

Output directory:

`application/logs/exact_chunked_vb_tiny_d1n5_pkgc51e9da_20260528/`

Result: passed.

- Same engine SHA: `TRUE`
- Engine SHA: `c51e9da4508f6fb89a73f8b78e08f9d80604e11a`
- Same design hash: `TRUE`
- Intended config differences only: `TRUE`
- Iterations: 3 and 3
- Max gate difference: `1.719513e-12`
- Tolerance: `1e-7`
- No-leakage audits checked: 3 per fit
- Unchunked max RSS: 139952 KB
- Exact chunked max RSS: 140136 KB
- Wall times: 18.59 seconds and 18.99 seconds

## Remaining Gates

- Keep exAL approximate batching gated until the exAL-specific derivation is
  implemented and tested.
- Keep rolling/posterior-as-prior, covariance approximations, subset targets,
  online promotion, variance-reduced SVI, divide-and-combine, coresets, and
  multivariate Q-DESN gated.
