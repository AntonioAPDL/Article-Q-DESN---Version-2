# PriceFM Stage-R110 frozen Q-DESN replay

Date: 2026-09-21

The completed R110 direct-driver experiment passed every preregistered gate on
BG, EE, and BE. Its pooled outer-validation AQL was 10.97320, compared with
43.32617 for the prior Normal-RHS driver and 10.05687 for cached PriceFM.
This result authorizes only the bounded no-refit replay described here.

The replay preserves the frozen R103 region geometry, selected AL/exAL family,
seven independent quantile readouts, posterior coefficient draws, response
scaler, validation anchors, and Normal-RHS paths for graph neighbors. It
changes only the target region's future-price path: each of the 500 R110
direct-driver paths is fed through the same recursive state update as the
matching Q-DESN posterior path. No quantile or Normal model is refitted.

The implementation validates the R110 closeout and every final artifact hash,
checks exact validation-anchor and scaled-response equality against R103,
decodes R's column-major binary path storage without changing path identity,
and rejects nonfinite or non-validation inputs. Nine region-fold replays may
run concurrently, with all numerical libraries constrained to one thread per
process.

The closeout compares the replay with the validation-only R108 self-recursive
and R97 direct-reference surfaces. Passing requires 9/9 finite 500-path cases,
at least 20 percent pooled AQL improvement over R108 self recursion, pooled
AQL no more than 10 percent above the R97 direct reference, and no region-level
harm relative to R108 self recursion. Test data, model fitting, registry and
article mutation, joint models, and MCMC remain blocked. A pass authorizes only
training-only all-region direct-driver selection in a separately controlled
stage.

## Materialized result

All nine replay cases completed with 500 finite paths and no model fit, test
access, or mutation. Pooled validation AQL was 11.49989, compared with 36.04368
for R108 self recursion and 10.08757 for the R97 direct reference. The replay
therefore improved self recursion by 68.09 percent and harmed no focus region,
but remained 14.00 percent above the direct reference. It failed the fixed
10-percent proximity gate, so all-region direct-driver selection is not
authorized.

The regional replay AQLs were 6.25125 for BE, 12.21527 for BG, and 16.03315
for EE. Relative to the direct driver before Q-DESN propagation, the frozen
readout improved BE by 6.03 percent, worsened BG by 3.49 percent, and worsened
EE by 10.85 percent. The excess over the R97 direct reference is concentrated
after horizon 24 and reaches 27.03 percent for BG and 28.91 percent for EE over
horizons 73--96.

Reservoir support diagnostics do not identify a new state-instability failure:
the R110 replay and exact-target replay have nearly identical support and
saturation summaries. Together with the strong exact-target result, the
evidence instead identifies imperfect target paths and their propagation
through the frozen readout as the remaining mechanism. The next justified
stage is a no-refit comparison of raw R110 paths, the R110 analytic median, and
rank-coupled paths reconstructed from the saved analytic quantiles. Broad DESN
screening, all-region fitting, test scoring, registry changes, and article
changes remain blocked.
