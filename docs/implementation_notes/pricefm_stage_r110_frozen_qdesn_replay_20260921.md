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
