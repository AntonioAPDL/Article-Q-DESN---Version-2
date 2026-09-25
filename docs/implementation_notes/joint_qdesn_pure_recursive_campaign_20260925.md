# JOINT pure-DESN recursive campaign

This lane implements a fresh, family-specific JOINT validation campaign. It
does not reinterpret or overwrite the previous shared-backbone authority.

## Frozen scientific contract

- Eight synthetic families are selected independently.
- One DESN geometry and one RHS `tau0` are shared by all four quantile rows
  within a family: independent/joint AL and independent/joint exAL.
- Selection uses only 350 observational training rows and 150 observational
  calibration rows. Protected outcomes cannot select any control.
- The screen covers depth, explicit layer widths, response lag depth, shared
  leakage and spectral radius, input scale, recurrent sparsity, input
  sparsity, and RHS `tau0`.
- Seven prior shared-backbone winners are translated into the pure full-state
  contract and retained as explicit historical anchors. The prior
  `regime_shift` winner was direct and is recorded as non-translatable.
- The readout is an intercept plus the complete state from every reservoir
  layer. Raw inputs are excluded.
- Candidate scoring is teacher forced between rolling origins and recursive
  for the 30 unknown horizons within each origin.
- Gaussian ridge advances 50 architectures per family to Gaussian RHS-VB.
- Nested quantile VB initializes the final article-fixture MCMC fits.
- AL uses the established latent-GIG Gibbs transition; exAL uses exact M0.
- Final posterior forecasts compare paired path propagation and mean-state
  propagation under the same fitted posterior evidence.

The production graph contains 6,144 ridge workers, 6,000 Gaussian RHS-VB
workers, 408 nested quantile-VB workers, 136 article-fixture VB components,
160 VB-initialized MCMC chains, 16 primary DGP-oracle shards, and 64 posterior
score cells. Optional oracle extensions run only if the frozen precision gate
requests them.

## Runtime and isolation

The production controller is
`application/scripts/launch_joint_qdesn_pure_recursive_campaign.sh`. It may
run only on Jerez from the synchronized dedicated branch. Every numerical
worker is single-threaded, and the controller is restricted to 15 distinct
physical cores (`2-16`), preserving an unrelated long-running job on CPU 1.
Generated fixtures, fits, posterior draws, and score
packets remain under ignored `application/cache/` roots.

The workflow is resumable only through verified stage outputs. It fails
closed on worker failures, nonfinite selector scores, incomplete dependency
graphs, source-hash failures, or protected-selection violations.

## Publication boundary

VB is screening and initialization evidence. MCMC is the final comparison
layer. No article or Overleaf file is modified by this lane. Promotion must be
performed later by the integration coordinator after the recursive score
packet and manifests are audited.
