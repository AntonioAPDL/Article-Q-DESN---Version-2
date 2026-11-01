# Approved independent-study filtering specification

The author confirmed the corrected specification on 1 November 2026:
retain the training-parameter posterior, integrate latent-state uncertainty,
and apply the fitted dynamic-linear evolution rule consistently in filtering
and forecasting. This resolves the preceding scientific-direction question.
It does not waive numerical qualification or authorize substituting a
different package, refitting parameters, or publishing a pilot.

The machine-readable record is
`configs/ind_conditional_filter_specification_20261101.json`.
The current GloFAS campaign, MQ reconstruction, PriceFM, Phase182, manuscript
and Overleaf are outside this additive qualification lane.

## Statistical target

Let T denote the training endpoint, eta the static parameters and
eta^(1),...,eta^(B) their original retained draws, with their recorded weights.
For equal-weight draws, write

\[
Q_T(d\eta)=B^{-1}\sum_{b=1}^B\delta_{\eta^{(b)}}(d\eta).
\]

At an observed forecast origin o, retain that measure and update only the
conditional filtering law:

\[
Q_o(d\eta,d\xi_o)=Q_T(d\eta)\,
  \Pi_o^\eta(d\xi_o\mid Y_{1:o}).
\]

Here xi contains the state and any auxiliary/covariance information required
by the declared evolution law. Subsequent observations must not reweight
the eta draws. Within each eta, filtering weights must normalize separately.
This is an explicitly specified modular forecasting comparison, not full
sequential updating of the parameter posterior. The retained empirical
measure is an input to reconstruction; authenticating its provenance does
not by itself prove exactness of every historical MCMC update.

The historical dynamic-linear metric generator drew Gaussian location
replicates from a plug-in forecast summary. Its sequential draw labels do
not authenticate original sigma/auxiliary/state posterior columns. The
corrected workflow must catalog the genuine native posterior columns and
their weights; it must not reinterpret those metric labels as a parameter
draw map. A qualification can predeclare native column 1 without selecting
on an outcome, but the complete reconstruction needs a separately frozen
native draw inventory and resource price.

## Source-consistent covariance rule

For the preceding conditional covariance C, the fitted forward operator uses

\[
P_t=G_tCG_t^{\mathsf T},\qquad
W_t=D\circ P_t,\qquad R_t=P_t+W_t.
\]

The circle denotes elementwise multiplication. The historical forecast
helper instead adds D circle C; it must not silently define the corrected
operator. Unit discount gives D=0. For noncommuting G and C the difference
is substantive, so synthetic tests must include that case.

Small-file runtime records identify C++ fast inference for all 54 retained
dynamic-linear cases: 27 source-version 1.0.0 and 27 source-version 1.1.1.
Their frozen `src/mcmc_ffbs.cpp` files have identical SHA-256
`f6ccf41466ece60a3a63737bb434309e8bea59f5b254a086793e5cca0aba6065`.
The reference policy symmetrizes updated covariances and floors an invalid
or nonpositive scalar forecast variance at 1e-12. Do not blend it with the
R implementation's distinct covariance regularizers or relabel a newly
compiled reference as an authenticated historical binary.

## First implementation: an explicitly conditional qualification

The additive replay module reconstructs the Gaussian forward operator given
one paired training augmentation and static parameter value. It records
every time-indexed filtered mean/covariance, predictive mean/variance,
discount innovation and numerical-floor event. It does not sample a state,
generate a forecast, estimate a new parameter, or call an installed package's
different-version forecasting helper.

This first calculation is conditional on the retained auxiliary variables.
It must never be admitted as the parameters-only filtering artifact. For AL,
the observation offset and variance are A_p v_t and B_p sigma v_t. For exAL,
use the native probability transformation and paired half-normal variable;
do not replace them by posterior means or use a Gaussian standard deviation
as the AL scale. A Gaussian observation fixture is a numerical special case,
not permission to treat a Normal-DGP comparator as a Normal likelihood.

The required first-stage evidence is full time-indexed parity against the
authentic source operator, analytic Gaussian fixtures, unit discount,
noncommuting G/C, support/dimension rejection and observed-prefix invariance.
Compiled-source parity and original-binary parity must be distinguished.

## Conditional integration: derivation and remaining gates

For a fixed eta, a proposed Rao–Blackwellized filter carries auxiliary
history and its conditional Gaussian state moments. If W_t is a predictable
function of that preceding history, integrating the state gives the
incremental predictive Normal density. With auxiliary prior r and proposal q,

\[
\widetilde w_t^j=w_{t-1}^j
 \frac{r_\eta(a_t^j)}{q_t(a_t^j)}
 \phi(Y_t;f_t^j,Q_t^j).
\]

The ratio is one for a prior proposal. Do not multiply another state-transition
density after Gaussian integration. Analytical integration of conditionally
tractable states is the relevant principle in
[Doucet et al., UAI 2000](https://arxiv.org/abs/1301.3853) and
[Andrieu, de Freitas and Doucet, 2001](https://proceedings.neurips.cc/paper/2001/file/6f4920ea25403ec77bee9efce43ea25e-Paper.pdf).
Its predictable-discount specialization here is a derivation to qualify,
not a claim that those papers validate this application or its old fits.

Training auxiliary uncertainty must be integrated at each eta. One original
paired augmentation cannot stand in for that integral. In addition, a
path-dependent W can make earlier auxiliaries affect later transition
factors. Native forward parity alone therefore does not certify historical
local auxiliary/scale updates as exact updates of that complete joint model.
Retain this distinction rather than inferring a need for refitting without
a separate target audit.

Before production, specify the all-horizon covariance history. Propagating
without observation updates and updating a covariance using each simulated
future auxiliary are different extensions; they cannot be interchanged
inside a nominally common forecast operator. The approved direction is fixed,
but this derivation and its executable checks must precede a dispatch contract.
The existing fixed-per-draw/horizon innovation adapter is not automatically
adequate for a path-dependent covariance law.

For efficiency, filter each eta once through the authenticated observed
history and retain immutable checkpoints at every required origin. Do not
repeat the training filter separately for each origin or use later outcomes
to smooth earlier checkpoints. Test prefix invariance explicitly. Qualify
filtering error, future-CDF integration error and resource cost separately;
an iid future-trajectory bound does not bound particle-filter error.

No full reconstruction is admitted until these gates pass. No article values
or claims are changed by recording this decision or qualifying a forward
operator.
