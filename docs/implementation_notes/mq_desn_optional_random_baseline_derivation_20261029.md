# Optional random-baseline extension of MQ–DESN

Status: mathematical extension only; **not fitted in the reported simulation or applications**.
This note preserves optional algebra removed from the article supplement
during the advisor revision. It is not an article input, a new model authority,
or permission to fit or select an additional model.

Source: `qdesn-supplement.tex`, Section `sec:joint_qdesn_supp`, at
`483e6edbec72ec76e48f2259e943e674b76e5041`. The fitted first-slope hierarchy
has `Delta_1 = beta_1` for every grid size. Its complete prior, Gaussian
updates, latent/scale updates and covariance-aware variational second moments
remain in the supplement. The extension here replaces that first difference
by `Delta_1 = beta_1 - beta_base` and estimates an additional random baseline.
These are different models unless the baseline is fixed at zero.

## 1. Conditional prior and complete product factors

Use the supplement's notation: `r` slopes at each of `K` probability levels,
stacked slope vector `beta_st`, and block first-difference matrix `H`.
Let

\[
\Delta_1=\boldsymbol\beta_1-\boldsymbol\beta_{\rm base},\qquad
\Delta_k=\boldsymbol\beta_k-\boldsymbol\beta_{k-1},\quad k=2,\ldots,K.
\]

The optional baseline and all differences use separate Nishimura–Suchard
product regularized-horseshoe priors. Their normalized coefficient
conditionals have variances

\[
V_j^0=\left\{\zeta_0^{-2}+
((\tau^0)^2(\lambda_j^0)^2)^{-1}\right\}^{-1},\qquad
V_{k,j}^\Delta=\left\{\zeta_\Delta^{-2}+
((\tau_k^\Delta)^2(\lambda_{k,j}^\Delta)^2)^{-1}\right\}^{-1}.
\]

Thus `beta_base,j | scales ~ N(0,V_j^0)` and
`Delta_k,j | scales ~ N(0,V_k,j^Delta)`. The local/global inverse-gamma
auxiliary hierarchy is applied separately to the baseline and to each
difference block. As in `eq:supp_ns_full_prior`, the full product retains
the scale-dependent factors; these are not independent half-Cauchy scales
paired with only the normalized conditional variances.

Define

\[
\widetilde{\boldsymbol\beta}_{\rm base}
=(\boldsymbol\beta_{\rm base}^{\top},\boldsymbol0^{\top},\ldots,
\boldsymbol0^{\top})^{\top},\quad
D_\Delta=\operatorname{diag}(V_{k,j}^\Delta),\quad
D_0=\operatorname{diag}(V_j^0).
\]

Since `det(H)=1`, the conditional slope density is

\[
p(\boldsymbol\beta_{\rm st}\mid\boldsymbol\beta_{\rm base},D_\Delta)
\propto |D_\Delta|^{-1/2}
\exp\left\{-\tfrac12
(H\boldsymbol\beta_{\rm st}-\widetilde{\boldsymbol\beta}_{\rm base})^\top
D_\Delta^{-1}
(H\boldsymbol\beta_{\rm st}-\widetilde{\boldsymbol\beta}_{\rm base})
\right\}.
\]

The required product masses are

\[
C_\Delta(\Theta_\Delta)=\prod_{k,j}
\mathcal N\!\left(0\mid0,
(\tau_k^\Delta)^2(\lambda_{k,j}^\Delta)^2+\zeta_\Delta^2\right),\quad
C_0(\Theta_0)=\prod_j
\mathcal N\!\left(0\mid0,(\tau^0)^2(\lambda_j^0)^2+\zeta_0^2\right).
\]

Let `L_aug` denote the stacked Gaussian density evaluation together with
all level-specific exponential and half-Normal auxiliary densities, and
let `pi_lik` be the product of the scale and supported shape priors.
The complete optional target is

\[
\begin{aligned}
\pi_{\rm opt}&\propto L_{\rm aug}\,\pi_{\rm lik}\,
p(\boldsymbol\beta_0)\,
p(\boldsymbol\beta_{\rm base}\mid D_0)C_0(\Theta_0)p(\Theta_0)\\
&\qquad\times
p(\boldsymbol\beta_{\rm st}\mid\boldsymbol\beta_{\rm base},D_\Delta)
C_\Delta(\Theta_\Delta)p(\Theta_\Delta).
\end{aligned}
\]

The augmented exAL contributions use the same level-specific `v,s` hierarchy
and scale–shape kernels as the supplement. AL omits its `s,gamma` factors.
The intercept prior is the product of specified Gaussian priors, restricted
to ordered support only when that restriction is chosen. The repeated
observations in the stacked likelihood are density-evaluation arguments,
not a nonsingular Gaussian sampling model for repeated copies of one datum.

## 2. Gaussian updates

Let `Z_st=I_K kron Z`, `Omega` be the diagonal augmented observation
covariance, and `r_beta=y_st-beta_0,st-d`. The slope block has

\[
K_\beta=Z_{\rm st}^\top\Omega^{-1}Z_{\rm st}
+H^\top D_\Delta^{-1}H,\quad
m_\beta=K_\beta^{-1}
\{Z_{\rm st}^\top\Omega^{-1}r_\beta+
H^\top D_\Delta^{-1}\widetilde{\boldsymbol\beta}_{\rm base}\},
\]

and `beta_st | ... ~ N(m_beta,K_beta^-1)`. The baseline is conditionally
independent by feature:

\[
K_{0,j}=(V_j^0)^{-1}+(V_{1,j}^\Delta)^{-1},\qquad
m_{0,j}=K_{0,j}^{-1}(V_{1,j}^\Delta)^{-1}\beta_{1,j},\qquad
\beta_{{\rm base},j}\mid\cdot\sim\mathcal N(m_{0,j},K_{0,j}^{-1}).
\]

Only the first difference contains the baseline. Fixing `beta_base=0`
eliminates this update and the baseline linear term, recovering the fitted
coefficient update without an additional random parameter.

## 3. Shrinkage and variational updates

Apply `eq:supp_rhs_mcmc` once to the optional baseline, replacing
`beta,lambda,tau,xi,tau0` by their baseline counterparts, and separately to
each `Delta_k` block. Each global-variance conditional has shape `(r+1)/2`.
For a random common difference slab,

\[
\zeta_\Delta^2\mid\cdot\sim
IG\left(a_{\zeta_\Delta}+Kr/2,
b_{\zeta_\Delta}+\tfrac12\sum_{k,j}\Delta_{k,j}^2\right).
\]

For a random baseline slab, replace `Kr` by `r` and the sum by
`sum_j beta_base,j^2`. Fixed slabs have no scale-update step.

A sampler for this optional model adds a Gaussian baseline draw and its RHS
scale updates to the actual first-slope sampler. Those steps are deliberately
absent from the reported fitted-model algorithm. The remaining latent,
intercept and scale–shape steps are unchanged in form, but must target this
different complete prior.

For a joint Gaussian variational slope/baseline factor, let
`Delta=H beta_st-B beta_base`, where `B` inserts the baseline into the first
block. The required second moments are the squared mean plus the diagonal
of the full transformed covariance, including slope–baseline covariance if
retained. Under a factorization that separates the two blocks, that cross
covariance is zero by assumption, not omitted without specifying the family.
The fitted model's covariance-aware `H Sigma H'` formula remains in
`eq:supp_joint_increment_moments`.

## 4. Optional transformed intercept gaps

The previous supplement also described the optional parameterization

\[
\beta_{0k}=\beta_{01}+\sum_{j=2}^k\exp(\eta_j),\qquad k\ge2.
\]

It is not needed for the reported Gaussian conditionals truncated between
ordered intercepts. If a density on positive gaps is transformed to `eta`,
the log-Jacobian is `sum_j eta_j`; a prior specified directly on `eta` is
instead a different prior and does not acquire that same Jacobian by fiat.
The resulting low-dimensional block can use Metropolis–Hastings, slice, or
a stated Laplace approximation. No claim is made that this alternative was
executed in any retained study.

## 5. Preservation and publication boundary

This note preserves the former optional baseline variance, conditional prior,
product masses, full posterior factorization, Gaussian baseline and slope
updates, RHS substitutions/slab update, and optional intercept-gap account.
The article supplement now derives the fitted `Delta_1=beta_1` hierarchy
directly, so readers need not remove unfitted terms to recover the target.
This file must remain outside `overleaf/article_files.txt`; no table, fit,
forecast, score or scientific claim changes because of this relocation.
