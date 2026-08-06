# PriceFM Stage-R40 partial-pooling closeout

R40 closes the completed 11-case R39 qualification without inspecting test
data. For each case and 24-hour horizon block it computes five-fold median AQL,
the standard error of fold AQL, and the one-standard-error set. It selects the
smallest separate-readout weight in that set, after excluding nonconverged
separate blocks, and applies the preregistered 0.5% worst-fold harm guard.

The frozen block weights are applied to outer-validation predictions and
compared with the paired shared R36 readout and authoritative R34 validation
anchor. Full-quantile confirmation requires convergence, harm safety, and
strict improvement over both references. Test, registry, article, and MCMC
actions remain blocked.
