# PriceFM Stage-R42 exAL partial-pooling closeout

Stage-R42 is a read-only closeout of the six Stage-R41 exAL-anchor cases. It reapplies the frozen five-fold, validation-only, per-horizon-block selector: median inner-fold scaled AQL, one-standard-error preference toward the shared readout, and a 0.5% paired harm guard. Test artifacts are neither loaded nor selected on.

The closeout also hashes the realized R41 train/validation row ledgers, reservoir feature map, and training-weight summary against each case's Stage-R34-selected Stage-R33 source. It audits the corresponding full configs to separate preserved case specification from mechanism changes.

The realized audit found a stricter interpretation than the preliminary review. R41 preserves all six train/validation row ledgers, case-level reservoir controls, seeds, and realized training weights. However, all six generated configs dropped explicit selected spatial-neighbor details while being derived through R39/R41; defaults happened to reproduce three maps, while three reservoir input-map shapes changed. R41 also intentionally keeps `readout_interaction: none`, avoiding reuse of the excluded Stage-R4/R19 interaction family. Across all six cases, nested validation fit exAL cold: the outer runner understood the configured normal-to-AL-to-exAL warm chain, but the nested loop did not consume it.

Stage-R42 therefore authorizes only preparation of a bounded six-case Stage-R43 contract-repaired qualification after the runner path and focused tests pass. R43 must restore each selected R33 spatial information set, consume nested normal-to-AL-to-exAL initialization, and retain the interaction-free pooling design. Test inspection, full-quantile confirmation, MCMC, registry mutation, and article mutation remain blocked.

Materialized output:

`application/data_local/pricefm/authoritative/pricefm_stage_r42_exal_partial_pooling_closeout_20260807`
