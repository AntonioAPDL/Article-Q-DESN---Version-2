# PriceFM Stage-R50 frozen MCMC confirmation

Stage-R50 confirms only the sole Stage-R48 dual-reference winner: NO_3 fold 3. It does not reopen model selection.

The frozen mechanism contains seven exAL/RHS_NS quantiles, one shared readout, one horizon-1-24 readout, and a validation-selected prediction-pooling weight of 0.25. Four independent chains are assigned to every quantile/component pair, producing 56 jobs. Later horizons retain the shared prediction.

R47 used 116,640 unique training rows and exact integer-frequency replication to 583,200 shared-readout rows. The MCMC kernel has per-observation latent states and no frequency-weight API, so R50 preserves the replicated likelihood rather than substituting a cheaper changed model. The resulting computational burden is recorded in the prep summary.

The cleaned R47 artifacts retain rows, responses, feature-map matrices, and source hashes but not design CSVs or VB coefficient vectors. R50 therefore rebuilds the adapter deterministically, requires exact X/y/row/feature-map hash equality, and recovers prediction-equivalent minimum-norm beta starts from the frozen validation predictions. Rank deficiency means those starts are not claimed to be the original VB coefficient vector; multi-chain convergence is required to remove initialization dependence.

The closeout requires hard scalar convergence (`Rhat <= 1.05`, ESS at least 200), coefficient review gates, chain-level prediction stability, validation-direction transfer, quantile/horizon harm guards, and test AQL below both authoritative Q-DESN and cached PriceFM. It never mutates the registry or article automatically.
