# PriceFM Stage-R43 contract-repaired exAL pooling qualification

Stage-R43 is the bounded repair justified by the Stage-R42 closeout. Its scope is exactly the six cases whose Stage-R34 validation winner used exAL: IT_CALA folds 2 and 3, IT_SARD fold 1, NO_3 folds 2 and 3, and NO_5 fold 3.

For every case, launch preparation restores the full spatial-neighbor dictionary and training-weight contract from the selected Stage-R33 config. It freezes the selected reservoir dimensions, hyperparameters, seed, feature policy, lag window, RHS prior, and median-only target. It retains the new Stage-R41 mechanism, `readout_interaction: none`, with shared and horizon-separate readouts and pooling weights 0, 0.25, 0.5, 0.75, and 1.

The runner now fits a normal RHS model on each inner training fold, initializes same-fold AL from that fit, initializes same-fold exAL from AL at the same quantile with zero gamma policy, and initializes each separate horizon block from its paired shared fit. `nested_warm_start_diagnostics.csv` records this provenance. No inner fit uses outer-validation or test rows.

Launch prep is fail-closed: all materialized config contracts, runner capability checks, six-case scope, test quarantine, explicit user authorization, and one-CPU-per-case allocation must pass. The prep script never invokes the launcher. Test, full-quantile, MCMC, registry, and article mutation remain blocked pending a fresh Stage-R44 closeout.

Materialized prep output:

`application/data_local/pricefm/authoritative/pricefm_stage_r43_contract_repaired_exal_pooling_launch_prep_20260807`
