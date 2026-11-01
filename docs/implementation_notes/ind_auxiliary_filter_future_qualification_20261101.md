# Independent-study conditional filtering and future integration

## Scope and current decision

This additive stage continues the author's approved independent-study
specification in `configs/ind_conditional_filter_specification_20261101.json`.
The empirical training-parameter measure remains fixed. At a later observed
origin, inference updates latent states and auxiliary variables conditional
on each static parameter value, without reweighting the parameter population.
The native evolution rule is used consistently. No new parameter fit,
full reconstruction, article-result promotion or Overleaf publication is
authorized by the modules or their mathematical tests.

The preceding conditional forward replay matched both authenticated native
operators. It conditions on one training augmentation and therefore cannot
stand in for integration of that augmentation. The present modules implement
the next calculations, but their empirical accuracy and complete-inventory
cost must still be qualified. These are distinct milestones.

## Conditional auxiliary filter

For one fixed static parameter value, a particle carries a Gaussian state
mean and covariance, together with the auxiliary-history information that
determines subsequent covariance inflation. Given auxiliary values at time
t, the state is integrated analytically using the source-consistent rule

\[
 P_t=G_t C_{t-1}G_t^{\mathsf T},\qquad
 W_t=D\circ P_t,\qquad R_t=\operatorname{sym}(P_t+W_t).
\]

The conditional observation mean and variance are
\(f_t=F_t^{\mathsf T}G_tm_{t-1}+b_t\) and
\(Q_t=F_t^{\mathsf T}R_tF_t+V_t\). With a native auxiliary-prior
proposal, the incremental particle weight is the Normal predictive density
\(\phi(y_t;f_t,Q_t)\). It is not multiplied by another state-transition
density after Gaussian integration. General guided proposals are deliberately
unsupported until their exact importance ratio has been derived and tested.

`scripts/ind_conditional_auxiliary_filter.R` implements these operations for
one explicitly labelled parameter column. The native AL/exAL auxiliaries
are transformed from externally supplied open-unit innovations: exponential
with scale sigma and, for exAL, an independent standard half-Normal. The
module generates no random numbers itself. Its inputs must ultimately be
bound to a retained, authenticated numerical random stream; a matrix of
numbers in (0,1) does not by itself establish iid sampling.

Weights are normalized in log coordinates within the parameter value.
Effective sample size and systematic-resampling ancestry are retained.
Origin checkpoints contain the weighted distribution before resampling.
Later observations cannot alter an earlier checkpoint, and filtering is
performed once through history rather than repeated separately per origin.
The result is a finite-particle approximation, not an exact posterior and
not an update of the outer static-parameter weights.

The native replay records its historical nonpositive-Q fallback. This new
probability-law qualification instead rejects nonpositive Q: a numerical
floor must not silently certify an unchanged model. Covariances are
symmetrized and checked; no SVD floor, cap or material eigenvalue repair is
introduced.

## Future-state and covariance-control calculations

For a fixed origin Gaussian component and future auxiliary path, assume
future F and G are known. This assumption is appropriate only after the
design's construction and information set have been authenticated. A caller's
`known_deterministic` declaration is not that authentication. In particular,
this reduction does not apply to DESN predictors depending on unobserved
future responses.

Initialize the covariance-control sequence and the actual predictive-state
covariance at the origin as \(C_0=S_0=C_o\). For each horizon,

\[
\begin{aligned}
 P_h^C&=G_hC_{h-1}G_h^{\mathsf T},&
 R_h^C&=\operatorname{sym}(P_h^C+D\circ P_h^C),\\
 W_h^{\mathrm{eff}}&=R_h^C-\operatorname{sym}(P_h^C),&
 Q_h^C&=F_h^{\mathsf T}R_h^CF_h+V_h,\\
 C_h&=\operatorname{sym}\{R_h^C-R_h^CF_hF_h^{\mathsf T}R_h^C/Q_h^C\},\\
 M_h&=G_hM_{h-1},&
 S_h&=\operatorname{sym}(G_hS_{h-1}G_h^{\mathsf T})+W_h^{\mathrm{eff}}.
\end{aligned}
\]

C is covariance bookkeeping conditional on the auxiliary history. Its update
does not assimilate an unobserved response's numerical value. S retains the
state uncertainty when those future responses have not been observed. In
particular,

\[
 S_h-R_h^C=G_h(S_{h-1}-C_{h-1})G_h^{\mathsf T}.
\]

Thus the first-horizon covariances coincide, but substituting R for S at
later horizons discards uncertainty. Conditional on this auxiliary path,

\[
 Y_{o+h}\sim N(F_h^{\mathsf T}M_h+b_h,
                 F_h^{\mathsf T}S_hF_h+V_h).
\]

`scripts/ind_conditional_future_marginals.R` computes these horizon marginals
without sampling future states or intermediate responses. It does not
return their complete joint trajectory law. For the scalar fixture
F=G=1, C0=1, D=1/4 and V1=V2=1, the correct second-horizon response variance
is 43/18; using the conditional R or repeatedly discounting S gives the
different values 61/36 and 41/16.

## Mixture weights and quantiles

The remaining origin and future-auxiliary integration must mix response
CDFs, not quantiles, means or variances. If origin component j has filtering
weight omega_j and contributes L_j native-prior auxiliary paths, each path
receives omega_j/L_j. Every positive-weight origin component must be
represented. No future-response likelihood enters those future weights.

The weighted Normal-mixture functions validate and normalize the supplied
weights, construct a finite quantile bracket, and retain the inversion
bracket and its tolerance. The path-weight helper preserves origin masses
when path counts differ. Deterministic inversion accuracy is not a bound on
particle-filter error or finite auxiliary integration error.

## Verification and finite authentic-data probe

Registered tests use synthetic data only. They compare filtering with an
independent bivariate Gaussian enumeration of every history in a finite
auxiliary-prior fixture, not merely another call to the same filter. They
also cover an exact Gaussian special case, source-native transformations,
prefix causality with resampling, log-weight stability, zero-mass and
endpoint resampling cases, support/dimension rejection and unchanged RNG.
Future tests compare independently assembled block-Gaussian covariances,
noncommuting time-varying dynamics, the scalar 43/18 identity, first-horizon
native replay, unequal mixture weights and numerical rejection cases.

A separate CLI, `scripts/qualify_ind_auxiliary_filter.R`, admits only a
SHA-pinned, finite training-data probe at a clean committed source. Its
predeclared native AL column, particle resolutions and two numerical seeds
are not model or seed selection. All outputs and unsuccessful attempts must
be retained. It does not forecast, score protected outcomes or assert
empirical accuracy from agreement at a few resolutions. Its column catalog
identifies scalar columns present in one authentic fit; it does not establish
the complete campaign's draw-selection policy or map old Gaussian metric
replicate labels to native posterior columns.

## Requirements before full reconstruction

1. Freeze the genuine original parameter columns, pairing, source versions,
   retention rules and weights for every required model. Do not reinterpret
   the historical 1:4000 metric-replicate labels as native parameter IDs.
2. Qualify the conditional training filter on representative retained AL and
   exAL evidence, including degeneracy and separately declared numerical
   error criteria. If the native-prior proposal is inadequate, retain the
   failure and derive a valid alternative rather than relaxing the criterion.
3. Authenticate future deterministic F/G and every observed-origin boundary;
   integrate future auxiliaries and invert the weighted CDF with a separate
   accuracy qualification. Preserve original parameter weights and every
   required draw/origin key.
4. Price the complete retained inventory using measured cost, realistic
   dependency/concurrency limits, finite output budgets and fresh host
   admission. A one-column probe is not a whole-project ETA.
5. Complete and verify the matched comparison before scoring, article
   regeneration or publication. No individual favorable cell is promotable.

The approved empirical parameter measure is an input to this modular
construction. Neither native forward parity nor these additive tests prove
that every historical local Gibbs update targeted one complete
auxiliary-history-dependent posterior. That separate question must not be
silently answered by a successful numerical operator test.
