# PriceFM R133: decoupled direct multi-horizon driver

R133 is a bounded successor to R130-R132. It asks whether the future endogenous
price path required by the recursive Q-DESN receiver can be improved by a
small direct 96-step model learned entirely inside the training period.

The frozen stochastic Normal RHS model first generates its complete S500 path
without modification. A ridge-regularized direct map then changes the path's
lead-specific location and, for prespecified candidates, dispersion. Because
this happens after baseline generation, the correction cannot recursively
alter its own predictors. The corrected path is used only as the future price
input to the unchanged independent AL-VB receiver.

Selection is forward-only: split 2 is predicted from split 1, and split 3 from
splits 1-2. R130/R131/R132 held-out outcomes, oracle paths and official test
scores are excluded from fitting and selection. The strict improvement and
splitwise no-harm gate defaults to identity when transfer is not demonstrated.

The stage uses HR and DK_1, the exact R128 architectures and tau0 values, the
exact R129B receiver fits, and the exact R130 origin/task geometry. It performs
no DESN, Normal or quantile refitting, no MCMC, no registry or article update,
and no all-region launch. Generated evidence remains under ignored
`application/data_local/pricefm`; the detailed execution tracker is ignored at
`local_trackers/pricefm_stage_r133_direct_multihorizon_driver_master_plan_20261011.md`.

The release suite executes the R133, R132 and R131 regressions and separately
pins the exact R127 closeout head and consumed source/artifact hashes. The
optional R127 full-fold tests require scikit-learn, which this frozen Jerez
environment does not provide and R133 does not execute.
