# Joint QDESN Phase182 Dense-Grid Crossing Refit

Phase182 is a diagnostic stress refit for the joint-versus-independent
multi-quantile validation study. Phase180/181 established the current
seven-level article evidence under case-specific DESN and regularized
horseshoe controls. That grid is useful for forecast scoring, but it is too
coarse to demonstrate the crossing-reduction behavior that motivates the joint
readout. Phase182 therefore refits the same 32 scenario-model cells on the
nineteen-level grid `0.05, 0.10, ..., 0.95`.

The phase is deliberately narrow. It does not retune DESN controls, change
`tau0`, reuse current-grid posterior draws, interpolate quantiles, or modify
article assets. The only scientific change is the reported quantile grid.

## Source Authority

The phase reads, but does not modify, the current source cache under
`/data/jaguir26/local/src/Article-Q-DESN---Version-2/application/cache`.
The immediate scientific authority is:

- `joint_qdesn_phase181_score_stability_extension_packet_20260826`
- `joint_qdesn_phase181_score_stability_extension_freeze_20260826`
- `joint_qdesn_phase180_balanced_dgp_score_freeze_20260824`
- `joint_qdesn_simulation_dgp_fixtures_20260706`

Phase181 is accepted as the current source because its implementation hard
gates passed, it retained 32 cells, contract crossings were zero, and it
confirmed that case-specific controls were preserved. The Phase180 freeze is
used to verify that the DESN and `tau0` controls were not retuned during the
Phase181 Monte Carlo extension.

## Models

Every scenario is refit under the four article model classes:

- Joint QDESN RHS under AL
- Independent QDESN RHS under AL
- Joint exQDESN RHS under exAL
- Independent exQDESN RHS under exAL

The exAL models use the current exact-M0 sampler
`M0_v_collapsed_support_logit`. AL models use the existing latent-scale Gibbs
sampler. All workers retain compact compressed posterior checkpoints rather
than serialized R workspaces.

## Dense Fixture

The dense fixture is regenerated from the frozen DGP registry after replacing
only the `tau_grid` field. The observed response path, design matrix, split
metadata, forecast origins, and DGP seeds are verified against the current-grid
fixture. The dense true quantile grid must be finite and monotone.

## Contract

The frozen contract is:

`application/config/joint_qdesn_phase182_dense_grid_crossing_contract_v1.csv`

Key rules:

- 8 scenarios and 4 model classes produce 32 cells.
- All 32 cells are rerun; current-grid posterior draws are not reused.
- Each cell uses 8 chains, for 256 workers.
- The default worker concurrency is 20 one-core workers.
- The score is the DGP-integrated finite-grid quantile score with trapezoidal
  weights over the interval from 0.05 to 0.95.
- Contract quantiles must be noncrossing; raw crossings remain diagnostics.
- Article assets are not modified by preparation, workers, or finalization.

## Outputs

Preparation writes:

- `joint_qdesn_phase182_dense_grid_crossing_freeze_20260831`
- `joint_qdesn_phase182_dense_grid_fixtures_20260831`
- `joint_qdesn_phase182_dense_grid_fixture_shards_20260831`

Sampling writes:

- `joint_qdesn_phase182_dense_grid_crossing_chains_20260831`
- `joint_qdesn_phase182_dense_grid_crossing_20260831_orchestration`

Finalization writes:

- `joint_qdesn_phase182_dense_grid_crossing_packet_20260831`

The final packet includes posterior score summaries, DGP-score by tau,
current-grid versus dense-grid comparisons, canonical raw and contract crossing
summaries, pair-level dense crossing detail, parameter diagnostics, runtime
summaries, manifests, and provenance.

## Launch

Use a dedicated JOINT branch and keep the worktree clean before launch. The
launcher defaults to the worktree-local ignored cache while reading source
artifacts from the authoritative cache root:

```bash
JOINT_QDESN_PHASE182_MAX_PARALLEL=20 \
application/scripts/295_launch_joint_qdesn_phase182_dense_grid_crossing.sh
```

If a specific CPU lease is required:

```bash
JOINT_QDESN_PHASE182_CPU_LIST=0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19 \
JOINT_QDESN_PHASE182_MAX_PARALLEL=20 \
application/scripts/295_launch_joint_qdesn_phase182_dense_grid_crossing.sh
```

Health checks:

```bash
Rscript application/scripts/293_check_joint_qdesn_phase182_dense_grid_crossing.R --write
```

Finalization is run automatically by the launcher after all workers complete,
or manually with:

```bash
Rscript application/scripts/294_finalize_joint_qdesn_phase182_dense_grid_crossing.R --score-cores 8
```

## Promotion Rule

Phase182 is not automatically article-authoritative. It is promotable only after
all 256 workers complete, manifests verify, finite scores are available for all
32 cells, contract crossings remain zero, and the dense-grid raw-crossing
patterns support the crossing/coherence claim without overstating mixing or
posterior predictive-density evidence.
