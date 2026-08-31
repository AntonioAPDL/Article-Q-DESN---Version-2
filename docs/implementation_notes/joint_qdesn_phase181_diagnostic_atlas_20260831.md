# Joint QDESN Phase181 diagnostic atlas

## Purpose

This stage adapts the strongest diagnostics from the independent-validation
review packets to the final JOINT Phase181 evidence. It creates one ignored,
hash-pinned review PDF. It does not refit a model, change a selected
specification, mutate Phase181, or publish an article asset.

The independent work established two useful but distinct patterns. Its v13
packet used process-isolated 300-dpi rendering, pinned source hashes, repeated
render checks, and strict PDF gates. Its granular atlas exposed lead-, origin-,
and path-level behavior, but some profile ribbons represented ranges across
three chains rather than posterior credible intervals. The JOINT atlas combines
the first packet's provenance and rendering discipline with the second packet's
granularity. Every score interval uses the frozen 8,000 Phase181 score draws,
and every displayed path band is an equal-tailed posterior interval reconstructed
from 1,000 selected draws in each of eight chains after applying the Phase181
monotone quantile-grid contract.

## Frozen authority

- Scientific branch tip: `6655408c3f3829075dc166affe802f4d1b6930df`.
- Corrected Phase181 packet manifest:
  `a96200a0dfdb0ad3506f99e737cce75b5f71d68c662a2ee1484376d44ebef624`.
- Superseded pre-repair packet manifest, provenance only:
  `e392c717c060636ec8ebadb51842b7abfe3fb531b99de3659cee8875d26d0292`.
- Selected-source registry:
  `6b7848462679367664b6a8387921e3949d0da9bd3b35898f1b61708526620463`.
- Article-fixture manifest:
  `d7e2af433985ff09277494c7cfdca6d1036bcb0ee8d0293af1774044fddc41e7`.

The corrected packet differs from the superseded packet only in the frozen
joint-minus-independent score-draw pairing seeds. The marginal score
distributions, selected model sources, quantile paths, crossings, and oracle
recovery diagnostics did not change.

## PDF structure

The PDF has exactly 40 pages:

1. Protocol, estimand, and provenance.
2. Posterior DGP-integrated finite-grid score intervals.
3. Posterior expected-regret intervals.
4. Joint-minus-independent score contrasts.
5. DGP-integrated versus realized finite-grid scores.
6. Fit/forecast oracle MAE and RMSE diagnostics.
7. Raw crossings and monotone adjustment.
8. Score-functional and scalar-parameter diagnostics.
9. Four pages for each of the eight mechanisms: quantile-level score
   decomposition, origin-by-lead expected regret, forecast paths, and fit-window
   recovery/coherence.

Forecast origins are interpreted as sequential conditional evaluations. The
readout coefficients remain fixed, while realized lagged responses become
available between origins. The 33 adjacent 30-step blocks are not open-loop
recursive forecast fans.

## Interpretation

The primary score is the DGP-integrated expected finite-grid quantile score,
computed as twice the trapezoidally weighted expected check loss on
`0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`. Oracle MAE/RMSE assess recovery of
known conditional quantile paths. Raw crossings and monotone adjustments assess
pre-contract coherence. They are not substitutes for the forecast score.

All 16 equal-tailed 95% joint-minus-independent score intervals include zero.
The atlas must therefore use descriptive language and cannot turn numerical
winners into definitive superiority claims.

## Reproduction

```bash
Rscript application/tests/test_joint_qdesn_phase181_diagnostic_atlas.R

JOINT_QDESN_PHASE181_SOURCE_ROOT=/data/jaguir26/local/src/Article-Q-DESN---Version-2 \
JOINT_QDESN_PHASE181_ATLAS_EXTRACT_CORES=2 \
JOINT_QDESN_PHASE181_ATLAS_RENDER_WORKERS=4 \
bash application/scripts/290_run_joint_qdesn_phase181_diagnostic_atlas.sh --force
```

The ignored output is
`local_trackers/joint_qdesn_phase181_diagnostic_atlas_20260831`. It contains the
single combined PDF, all 40 source pages, compact plot ledgers, a contact sheet,
source and artifact manifests, provenance, and visual-QA results.

## Gates

Preparation fails closed unless all packet, fixture, registry, worker, score,
contrast, finiteness, and contract-crossing checks pass. Finalization requires
40 one-page source PDFs, one 300-dpi image per page, stable repeated rendering,
source-to-combined raster equivalence, nonblank pages, clear margins, and a
40-page combined PDF. The final checker re-verifies every output hash and all
path-interval cardinality and ordering constraints.
