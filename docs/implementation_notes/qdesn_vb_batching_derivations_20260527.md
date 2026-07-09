# Q-DESN VB Batching Derivations and Validation Checklist

Date: 2026-05-27

Status: derivation note for implementation planning. This document does not
claim that stochastic, hybrid, variance-reduced, streaming, article-side
approximate, or multivariate batching has been implemented. It records the
mathematical contracts and verification checks that should be satisfied before
those modes are added to the package or article application.

Operational resume plan:
`docs/implementation_notes/qdesn_vb_batching_roadmap_20260527.md`.

## Purpose

The exact chunked VB implementation already provides a memory-oriented way to
evaluate the same full-data variational updates in row blocks. The next
batching modes are different: stochastic mini-batch, hybrid, and
variance-reduced updates approximate the full-data updates and therefore need
explicit mathematical contracts, runtime diagnostics, and tests before they are
allowed to run.

This note derives the main update expressions for:

- package static/readout AL LDVB,
- package static/readout exAL LDVB,
- univariate Q-DESN under AL and exAL through the fixed DESN design,
- the article GloFAS latent-path AL-VB application,
- the deferred article GloFAS exAL extension, and
- later stochastic, hybrid, variance-reduced, streaming, and multivariate
  extensions.

The goal is to make the later implementation conservative and reproducible:
exact chunking remains a full-data baseline, while every approximate method is
labeled and tested as approximate.

## References for Implementation Design

These references motivate the implementation contracts. They should be used as
background, not as permission to replace repo-specific update equations.

- Kozumi and Kobayashi (2011), Gibbs sampling methods for Bayesian quantile
  regression.
- Hoffman et al. (2013), stochastic variational inference.
- Robbins and Monro (1951), stochastic approximation.
- Broderick et al. (2013), streaming variational Bayes.
- Johnson and Zhang (2013), stochastic variance-reduced gradient.
- Defazio et al. (2014), SAGA.

The repo-specific equations below take precedence over generic algorithms when
there is a mismatch.

## Notation

After Q-DESN feature construction, the package readout problem is a static
Bayesian quantile regression problem with design rows \(x_i^\top\) and scalar
responses \(y_i\):

\[
y_i = x_i^\top \beta + \epsilon_i,\qquad i=1,\ldots,n .
\]

The fixed DESN feature matrix is denoted by \(X\). The variational
approximation contains:

\[
q(\beta)=N(m_\beta,V_\beta),
\]

local augmentation moments

\[
E_q(v_i)=\bar v_i,\qquad E_q(v_i^{-1})=\bar v_i^{-1},
\]

and, for the exAL representation, latent skewing moments

\[
E_q(s_i)=\bar s_i,\qquad E_q(s_i^2)=\overline{s_i^2}.
\]

The current residual and posterior quadratic term are

\[
r_i = y_i - x_i^\top m_\beta,\qquad
q_i = x_i^\top V_\beta x_i .
\]

The package code stores likelihood-dependent expectations in `xis`. For this
note, define

\[
\xi_1 = E_q\{(B\sigma)^{-1}\},
\]

\[
\xi_\lambda = E_q(\lambda/B),\qquad
\xi_{\lambda^2} = E_q(\lambda^2\sigma/B),
\]

\[
\xi_A = E_q\{A/(B\sigma)\},\qquad
\xi_{A^2} = E_q\{A^2/(B\sigma)\},
\]

\[
\xi_{\sigma^{-1}} = E_q(\sigma^{-1}),\qquad
\zeta_{\lambda A}=E_q(\lambda A/B).
\]

For AL, gamma is fixed through the code's AL reduction. The implementation
still uses the same sigma-only Laplace-Delta machinery as exAL; it should not be
replaced by a different inverse-gamma update unless that change is derived,
tested, and explicitly approved as a separate model change.

## Full-Data Beta Update

The package beta update is a Gaussian natural-parameter update. Define row
weights and row linear terms

\[
w_i = \xi_1 \bar v_i^{-1},
\]

\[
b_i = y_i w_i
      - \xi_\lambda \bar v_i^{-1}\bar s_i
      - \xi_A .
\]

The data contribution to the beta precision and linear term is

\[
S_\beta = \sum_{i=1}^n w_i x_i x_i^\top,
\]

\[
g_\beta = \sum_{i=1}^n x_i b_i .
\]

Let \(\Lambda_\beta\) denote the current prior precision for beta. Under the
regular normal prior this is fixed. Under RHS shrinkage it is updated globally
from the current beta posterior moments, not from row batches. The beta update is

\[
V_\beta = (S_\beta + \Lambda_\beta)^{-1},
\]

\[
m_\beta = V_\beta g_\beta .
\]

### Implementation Mapping

Current exact helper names in the package:

- `.exal_beta_data_stats()` computes the data-only \(S_\beta\) and \(g_\beta\).
- `.exal_beta_data_stats_chunks()` sums those data stats over deterministic
  row chunks.
- `.exal_beta_solve_from_data_stats()` adds the prior precision and solves the
  Gaussian update.
- `.exal_beta_natural_stats()` is retained as a compatibility wrapper.

### Verification Checks

For every future batching change, these checks are mandatory:

1. With chunking disabled, \(S_\beta\), \(g_\beta\), \(m_\beta\), and
   \(V_\beta\) match the pre-chunking implementation within numerical tolerance.
2. With exact chunking and any deterministic partition \(\{C_k\}\),

   \[
   S_\beta = \sum_k S_{\beta,C_k},\qquad
   g_\beta = \sum_k g_{\beta,C_k}.
   \]

3. RHS prior updates remain global. A row batch may approximate the data
   natural statistics, but it must not directly update local RHS states as if
   they were data-row quantities.
4. The solve path still uses the existing positive-definite safeguards.

## Local \(q(v_i)\) Update

Given the current beta posterior, the local AL/exAL scale augmentation update is

\[
q(v_i)=\operatorname{GIG}(1/2,\chi_i,\psi),
\]

where

\[
\psi = \xi_{A^2}+2\xi_{\sigma^{-1}},
\]

and

\[
\chi_i =
\xi_1(r_i^2+q_i)
-2\xi_\lambda r_i\bar s_i
+\xi_{\lambda^2}\overline{s_i^2}.
\]

Equivalently, matching the implementation's rowwise expansion,

\[
\chi_i =
\xi_1\{(y_i-x_i^\top m_\beta)^2+x_i^\top V_\beta x_i\}
-2\xi_\lambda y_i\bar s_i
+\xi_{\lambda^2}\overline{s_i^2}
+2\xi_\lambda (x_i^\top m_\beta)\bar s_i .
\]

The moment updates for the \(\lambda=1/2\) GIG case are

\[
E_q(v_i^{-1})=\sqrt{\psi/\chi_i},
\]

\[
E_q(v_i)=\sqrt{\chi_i/\psi}
          \left(1+\frac{1}{\sqrt{\chi_i\psi}}\right).
\]

### Verification Checks

1. \(\chi_i>0\) and \(\psi>0\) after safeguards.
2. All \(E_q(v_i)\) and \(E_q(v_i^{-1})\) are finite and positive.
3. Exact chunking changes only the order in which rows are updated, not the
   formula.
4. Stochastic modes must define what happens to rows not in the current batch:
   they should retain their previous local moments until refreshed, with
   explicit initialization before the first stochastic iteration.

## Local \(q(s_i)\) Update for the exAL-Style Engine

The exAL skewing variable has a positive truncated normal variational factor:

\[
q(s_i)=N^+(\mu_i,\tau_i^2),\qquad s_i>0.
\]

The variance and mean parameters are

\[
\tau_i^2 =
\left(1+\xi_{\lambda^2}E_q(v_i^{-1})\right)^{-1},
\]

\[
\mu_i =
\tau_i^2
\left\{
\xi_\lambda E_q(v_i^{-1})(y_i-x_i^\top m_\beta)
- \zeta_{\lambda A}
\right\}.
\]

For \(a_i=\mu_i/\tau_i\), the truncated-normal moments are

\[
E_q(s_i)=\mu_i+\tau_i\frac{\phi(a_i)}{\Phi(a_i)},
\]

\[
E_q(s_i^2)=\tau_i^2+\mu_i^2
          +\tau_i\mu_i\frac{\phi(a_i)}{\Phi(a_i)} .
\]

### AL Reduction

In the AL reduction, gamma is fixed and the same code path can reduce the
skewing contribution to the AL form. The current package engine still carries
the `qs` objects through this shared path, even when `likelihood_family = "al"`.
The implementation must continue to use the package's AL reduction consistently.
If a stochastic AL implementation updates only \(v_i\)-like local quantities, it
must first confirm which `qs` terms are fixed, omitted, or reduced by the
current code.

### Verification Checks

1. Truncated-normal moments are finite for large positive and large negative
   \(a_i\).
2. exAL exact chunking matches unchunked exAL.
3. Approximate exAL batching must fail early until a separate exAL contract is
   written and tested.

## Sigma/Gamma Laplace-Delta Update

The package engine updates sigma and gamma through the existing
Laplace-Delta machinery. Let

\[
t_i = y_i - x_i^\top m_\beta .
\]

The sufficient statistics used by the sigma/gamma update are

\[
S_1 =
\sum_i E_q(v_i^{-1})\{t_i^2+x_i^\top V_\beta x_i\},
\]

\[
S_2 = \sum_i t_i,\qquad
S_3 = \sum_i E_q(v_i),
\]

\[
S_4 =
\sum_i E_q(s_i)E_q(v_i^{-1})t_i,
\]

\[
S_5 =
\sum_i E_q(s_i^2)E_q(v_i^{-1}),\qquad
S_6 = \sum_i E_q(s_i).
\]

These are data sums and therefore are exactly chunk-additive:

\[
S_j = \sum_k S_{j,C_k},\qquad j=1,\ldots,6.
\]

For current likelihood parameters, the code evaluates a log kernel of the form

\[
\ell(\eta,\log\sigma)
=
-\frac{1}{2B\sigma}\{S_1-2AS_2+A^2S_3\}
-\frac{S_3+b_\sigma}{\sigma}
\frac{\lambda}{B}(S_4-AS_6)
-\frac{\lambda^2\sigma}{2B}S_5
+ \ell_{\mathrm{Jac/prior}} ,
\]

where \(A\), \(B\), and \(\lambda\) are functions of the quantile and gamma
parameterization used in the package, and \(\ell_{\mathrm{Jac/prior}}\) denotes
the remaining log-determinant, Jacobian, and prior terms in the implementation.

### AL Constraint

For `likelihood_family = "al"`, gamma is fixed. The sigma update still enters
through this sigma-only LD route. Approximate AL batching should therefore
either:

1. keep sigma on periodic full refreshes, which is the conservative first
   choice, or
2. maintain damped stochastic estimates of the \(S_1,\ldots,S_6\) statistics,
   with clear diagnostics and finite-state safeguards.

### Verification Checks

1. The exact chunked \(S_1,\ldots,S_6\) match unchunked values within tolerance.
2. In AL mode, approximate updates never unfix gamma.
3. Sigma remains positive and finite after every update.
4. Any stochastic sigma trace is labeled as noisy or approximate, not as an
   exact full-data ELBO update.

## Exact Chunked Full-Data VB

Exact chunking is not a statistical approximation. It changes the evaluation
order of additive row quantities:

\[
S_\beta = \sum_k\sum_{i\in C_k} w_i x_i x_i^\top,
\]

\[
g_\beta = \sum_k\sum_{i\in C_k} x_i b_i,
\]

\[
S_j = \sum_k\sum_{i\in C_k} s_{j,i},\qquad j=1,\ldots,6.
\]

The local moments are still stored for all rows, and the global update uses the
same full-data information. Numerical differences should be attributable only
to floating-point summation order and downstream numerical tolerances.

### Exact Chunking Acceptance Criteria

Exact chunking is acceptable only when:

1. unchunked defaults are unchanged;
2. exact chunked AL matches unchunked AL;
3. exact chunked exAL matches unchunked exAL;
4. Q-DESN AL and exAL routing pass controls correctly;
5. article GloFAS fixed-row chunking preserves fitted-state summaries;
6. future grouped moments and no-leakage checks remain unchanged.

## Stochastic Mini-Batch AL VB Contract

This is the first scientifically plausible approximate batching target. It
should be implemented only for package static/readout AL before any exAL,
article-side, or multivariate approximation is attempted.

### Target

The stochastic algorithm approximates the same full-data AL LDVB fixed point as
the unchunked and exact chunked package AL engine. Unlike exact chunking, it
does not use all rows at every iteration.

### Batch Sampling

Let \(B_t\subset\{1,\ldots,n\}\) be a mini-batch of size \(b_t\). The first
implementation should support a reproducible random or shuffled batch order with
an explicit seed. Sequential mini-batches can be supported for debugging, but
randomized batches are the default for stochastic approximation.

An epoch is one pass through \(n\) rows when sampling without replacement, or
\(\lceil n/b\rceil\) stochastic steps when sampling with replacement. The mode
must record which convention it uses.

### Scaled Data Natural Statistics

For a batch \(B_t\), define the row-sampled estimates

\[
\widehat S_{\beta,t}
=
\frac{n}{b_t}\sum_{i\in B_t} w_i x_i x_i^\top,
\]

\[
\widehat g_{\beta,t}
=
\frac{n}{b_t}\sum_{i\in B_t} x_i b_i.
\]

Maintain damped data natural statistics

\[
\widetilde S_{\beta,t}
=
(1-\rho_t)\widetilde S_{\beta,t-1}
+\rho_t\widehat S_{\beta,t},
\]

\[
\widetilde g_{\beta,t}
=
(1-\rho_t)\widetilde g_{\beta,t-1}
+\rho_t\widehat g_{\beta,t}.
\]

The beta update is then

\[
V_{\beta,t}
=
(\widetilde S_{\beta,t}+\Lambda_{\beta,t})^{-1},
\]

\[
m_{\beta,t}=V_{\beta,t}\widetilde g_{\beta,t}.
\]

If the row contributions are evaluated at a common current state for all sampled
rows, these are unbiased estimates of the corresponding full-data row sums.
When the algorithm stores stale local moments for rows outside the current
batch, the resulting update is still a controlled stochastic approximation, but
it is not literally the exact current-state CAVI statistic. The implementation
and diagnostics must make this distinction explicit.

Only data terms are scaled by \(n/b_t\). The prior precision is not scaled. RHS
shrinkage states are not row-batched.

### Learning Rate

Use a Robbins-Monro schedule such as

\[
\rho_t=\max\{\rho_{\min},(t_0+t)^{-\kappa}\},
\]

with recommended constraints

\[
t_0>0,\qquad 0.5<\kappa\le 1,\qquad 0\le\rho_{\min}<1.
\]

The implementation must reject invalid values. Tests should verify
monotonicity, lower-bound behavior, and reproducibility.

### Local Variables

The first stochastic AL implementation should keep local arrays for all rows.
At iteration \(t\), only rows in \(B_t\) are refreshed:

\[
q(v_i) \leftarrow q_t(v_i),\qquad i\in B_t.
\]

Rows not in \(B_t\) retain their previous local moments. Before stochastic
iterations begin, all rows need a deterministic initialization. The safest
choices are:

1. one full-data initialization pass, or
2. initial moments from the current unchunked initialization helpers.

The chosen initialization must be recorded in the control object and tested.
Tests should include both the deterministic initialization contract and a check
that periodic full-local refreshes restore the exact full-data local state when
the refresh cadence requires it.

### Sigma Update Options

The conservative first implementation should prefer periodic full sigma
refreshes rather than fully stochastic sigma updates. For refresh cadence \(K\),
every \(K\) steps compute full-data \(S_1,\ldots,S_6\), update sigma through the
existing LD machinery, and refresh `xis`.

If pure stochastic sigma is later implemented, use scaled statistics

\[
\widehat S_{j,t}
=
\frac{n}{b_t}\sum_{i\in B_t} s_{j,i},
\qquad j=1,\ldots,6,
\]

and damping

\[
\widetilde S_{j,t}
=
(1-\rho_t)\widetilde S_{j,t-1}
+\rho_t\widehat S_{j,t}.
\]

This should be treated as a second stage because sigma/gamma LD updates are
nonlinear in these statistics.

### RHS Shrinkage

RHS shrinkage is global. In stochastic AL, update RHS from the current
\(q(\beta)\) only:

\[
E_q(\beta_j^2)=m_{\beta,j}^2+V_{\beta,jj}.
\]

Reasonable first policies are:

- update RHS only on full refresh iterations;
- update RHS every \(K_{\mathrm{rhs}}\) stochastic steps using current
  \(q(\beta)\);
- keep RHS fixed during stochastic warmup, then refresh periodically.

The implementation must not update RHS from a row batch. This is both a
statistical and software-contract requirement.

### Objective and Diagnostics

The stochastic objective is noisy. It must not be labeled as the exact ELBO
unless it is computed on the full data. Diagnostics should distinguish:

- stochastic surrogate objective,
- periodic full-data objective,
- finite-state checks,
- maximum parameter changes,
- batch id and seed if trace storage is enabled,
- sigma refresh iterations,
- RHS refresh iterations.

### Stop Conditions

The stochastic AL implementation must stop and report failure if:

1. beta solve fails after existing numerical safeguards;
2. any \(q(v_i)\) moment is non-finite or non-positive;
3. sigma is non-finite or non-positive;
4. RHS states become non-finite;
5. exact chunking or unchunked regression tests fail;
6. exAL stochastic mode is accidentally allowed.

## Hybrid AL SVI With Full Refresh

Hybrid AL is the recommended next step after stochastic AL. It uses stochastic
updates between periodic full-data refreshes.

At stochastic step \(t\), update mini-batch local variables and damped beta
statistics as in stochastic AL. Every \(K\) steps, perform a full refresh:

\[
\widetilde S_{\beta,t}=S_{\beta,\mathrm{full}},
\qquad
\widetilde g_{\beta,t}=g_{\beta,\mathrm{full}},
\]

then solve the full beta update, refresh all \(q(v_i)\), update sigma with
full-data \(S_1,\ldots,S_6\), refresh `xis`, update RHS globally, and optionally
compute the exact full-data objective.

Hybrid is often safer than pure stochastic sigma updates because it periodically
reanchors all local and global quantities to the full-data target.

### Hybrid Acceptance Criteria

1. Full refresh with \(K=1\) should match exact full-data behavior within
   tolerance, subject to any intentional damping choices.
2. Larger \(K\) should remain finite and stable on synthetic AL tests.
3. Periodic full objectives should improve or remain diagnostically plausible;
   monotone improvement should not be required for noisy intermediate steps.
4. RHS updates should occur only during full refreshes in the first version.

## Variance-Reduced AL SVI

Variance-reduced SVI should be deferred until stochastic and hybrid AL are
stable. At a reference state \(\theta_0\), compute full-data reference
statistics

\[
S_{\beta,0}=S_\beta(\theta_0),\qquad
g_{\beta,0}=g_\beta(\theta_0).
\]

For mini-batch \(B_t\), form

\[
\widehat S_{\beta,t}^{VR}
=
S_{\beta,0}
+\frac{n}{b_t}\sum_{i\in B_t}
\{S_{\beta,i}(\theta_t)-S_{\beta,i}(\theta_0)\},
\]

\[
\widehat g_{\beta,t}^{VR}
=
g_{\beta,0}
+\frac{n}{b_t}\sum_{i\in B_t}
\{g_{\beta,i}(\theta_t)-g_{\beta,i}(\theta_0)\}.
\]

The same idea can be applied to sigma statistics, but that should be deferred
because the LD sigma update is nonlinear and more sensitive.

### Variance-Reduced Acceptance Criteria

1. Reference statistics must be computed by exact full-data or exact chunked
   helpers.
2. The mini-batch correction must use identical row formulas at \(\theta_t\)
   and \(\theta_0\).
3. The implementation must define when the reference state is refreshed.
4. Tests must show lower Monte Carlo variability than ordinary stochastic AL on
   controlled synthetic data before this mode is promoted.

## Streaming / Posterior-As-Prior VB

Streaming VB is not the same as stochastic mini-batching. For data blocks
\(D_1,\ldots,D_K\), it uses the posterior approximation from previous blocks as
the prior for the next block:

\[
q_k(\beta)\approx p(\beta\mid D_1,\ldots,D_k),
\]

\[
p_{k+1}(\beta)\leftarrow q_k(\beta).
\]

This is order-dependent and is not an unbiased approximation to a single
full-data CAVI update. It may be useful for online forecasting or memory-limited
data arrival, but it should be documented and tested as a different inferential
workflow.

### Streaming Acceptance Criteria

1. The ordering of data blocks is explicit and reproducible.
2. The prior carry-forward is mathematically documented.
3. Results are not compared to exact chunking as if they target the same fixed
   full-data iteration.
4. Validation includes sensitivity to block order and block size.

## Q-DESN Specialization

Q-DESN feature construction is deterministic conditional on reservoir settings,
lags, inputs, and scaling choices. Let

\[
X_{\mathrm{DESN}}
=
f_{\mathrm{DESN}}(y,\mathrm{covariates};\Theta_{\mathrm{reservoir}}).
\]

After \(X_{\mathrm{DESN}}\) is built, the package readout inference is exactly
the static AL or exAL LDVB problem above:

\[
y_i=x_{\mathrm{DESN},i}^\top\beta+\epsilon_i.
\]

Therefore:

- exact chunking for Q-DESN is exact chunking of static readout rows;
- stochastic Q-DESN AL is stochastic static AL after fixed feature
  construction;
- approximate Q-DESN exAL remains deferred until approximate static exAL is
  derived and validated.

### Q-DESN Checks

1. DESN feature hashes should match between unchunked, exact chunked, and
   stochastic readout comparisons.
2. Q-DESN routing must forward `likelihood_family`, `al_fixed_gamma`, and
   chunking controls.
3. Stochastic AL Q-DESN examples should use fixed seeds for reservoir draws and
   mini-batch order.
4. No batching mode should rebuild DESN features differently unless explicitly
   designed as a separate experiment.

## Article GloFAS Latent-Path AL-VB

The article latent-path application is not a plain static readout fit. It has
historical observed rows, latent future reference paths, source-specific scales,
block RHS shrinkage, and grouped future moment calculations.

A schematic historical row is

\[
z_i = h_i^\top\theta+\epsilon_i,
\qquad c_i\in\{Y,G\},
\]

where \(c_i\) denotes the source or component. Under AL with source-specific
scales, the row weight for a historical row has the form

\[
w_i =
E_q\{(B\sigma_{c_i})^{-1}\}E_q(v_i^{-1}).
\]

The historical contribution to the theta update is

\[
S_{\theta,\mathcal H}
=
\sum_{i\in\mathcal H} w_i h_i h_i^\top,
\]

\[
g_{\theta,\mathcal H}
=
\sum_{i\in\mathcal H} h_i b_i,
\]

with row linear term \(b_i\) defined by the AL reduction and the
source-specific scale moments.

The full theta update also includes prior/RHS terms and future latent-path
moment contributions:

\[
V_\theta =
\left(
S_{\theta,\mathcal H}
+S_{\theta,\mathcal F}
+\Lambda_\theta
\right)^{-1},
\]

\[
m_\theta =
V_\theta
\left(
g_{\theta,\mathcal H}
+g_{\theta,\mathcal F}
+g_{\theta,0}
\right).
\]

Here \(S_{\theta,\mathcal F}\) and \(g_{\theta,\mathcal F}\) denote the grouped
future moment contributions, and \(g_{\theta,0}\) denotes the prior linear term.
For a zero-mean Gaussian/RHS coefficient prior, \(g_{\theta,0}=0\). These future
terms are not ordinary observed rows and should not be approximated by the
package row-batching logic.

### Source-Specific Sigma Updates

For each source \(c\), sigma statistics should be accumulated over rows with
\(c_i=c\):

\[
S_{1,c}
=
\sum_{i:c_i=c}
E_q(v_i^{-1})\{r_i^2+h_i^\top V_\theta h_i\},
\]

with analogous source-specific sums for the remaining AL/exAL statistics used
by the article-side fitter. Exact chunking may split historical rows and add
these source-specific sums by chunk. It must not mix source labels or pool sigma
updates unless the model explicitly says so.

### Future Latent-Path Rows

Future latent-path terms are grouped and streamed by design. They enforce the
no-leakage contract for unobserved future USGS quantities. For the current
article implementation:

- exact chunking may apply only to fixed historical rows;
- grouped future moments remain exact and full;
- latent future updates remain unchanged;
- posterior draw identity checks remain unchanged.

### Article Approximate Batching Is Deferred

Article-side stochastic or hybrid batching should wait until package static AL
is stable. A future article contract must define:

1. whether mini-batches sample only historical rows;
2. whether future grouped moments are kept full at every step or periodically
   refreshed;
3. how source-specific sigma updates are refreshed;
4. how latent future paths are updated without leakage;
5. how block RHS updates are scheduled.

## Deferred Article GloFAS exAL Extension

An exAL version of the article application would require additional design
choices beyond the current AL implementation:

- source-specific or shared gamma parameters;
- source-specific or shared sigma/gamma LD updates;
- local \(q(s_i)\) moments for historical rows;
- possible future-row \(s_i\) analogues if the future moment block is extended;
- clear prior choices for every new scale/skewness parameter.

This extension should not be implemented by simply turning on package exAL
logic inside the article fitter. The article model has latent future paths and
source-specific structure that need a dedicated derivation.

## Multivariate Q-DESN Batching

The proposed multivariate Q-DESN has shared DESN features and multiple location
components. A simplified schematic is

\[
y_t = \mu_t + \epsilon_t,
\]

\[
\mu_t =
R\alpha_t
+D_t,
\]

where \(R\) is a mixing or dependence structure, \(\alpha_t\) may contain a
shared location component, and \(D_t\) contains output-specific discrepancy
components.

For a shared-feature design, one may write

\[
\alpha_t = x_t^\top\beta_0,
\]

\[
D_{j,t}=x_{j,t}^\top\beta_j,\qquad j=1,\ldots,J.
\]

A natural prior structure is:

\[
\beta_0 \sim \mathrm{RHS}_0,
\]

\[
\beta_j \sim \mathrm{RHS}_j,\qquad j=1,\ldots,J,
\]

with intercepts kept under ordinary normal priors. This matches the intended
separation between shared location and output-specific discrepancy shrinkage.

### Multivariate Batching Status

Multivariate Q-DESN batching is design-only for now. Before implementation, the
model needs:

1. a finalized multivariate exAL likelihood;
2. a precise shared-feature and output-specific feature design;
3. blockwise beta updates and RHS updates;
4. scale and dependence parameter updates;
5. tests showing reduction to the univariate Q-DESN when \(J=1\);
6. tests showing reduction to the current application model when \(R=I\) and
   the latent future-path structure is specialized appropriately.

## Global Verification Passes

Every implementation stage should pass the following audit before being
committed.

### Mathematical Pass

1. Identify the target distribution or variational fixed point.
2. State whether the method is exact full-data, approximate stochastic,
   streaming/posterior-as-prior, or model-changing.
3. Write the row-level contributions before writing code.
4. Specify which quantities are additive and which are nonlinear.
5. Define all scaling factors and prove which estimators are unbiased, if
   applicable.
6. State which priors are global and cannot be row-scaled.

### Numerical Pass

1. Check positive-definiteness of beta precision.
2. Check finite and positive local moments.
3. Check finite and positive sigma states.
4. Check finite RHS states.
5. Check stable behavior for small, medium, and ill-conditioned synthetic
   designs.
6. Preserve existing jitter or fallback solve behavior.

### Software-Contract Pass

1. Defaults remain unchanged.
2. Exact chunking remains full-data equivalent.
3. Approximate modes fail early unless implemented and tested.
4. Control normalization rejects invalid settings.
5. Q-DESN wrappers forward controls exactly once.
6. Article configs do not expose approximate modes before article-side contracts
   exist.
7. Long-running scripts do not overwrite existing artifacts unless an output
   tag or cache namespace is explicit.

### Statistical Diagnostics Pass

1. Compare approximate runs to full-data AL on easy synthetic data.
2. Report fitted-state distances, not just prediction summaries.
3. Use multiple seeds for stochastic modes.
4. Track runtime and memory separately from statistical accuracy.
5. Label stochastic objectives as noisy unless computed on the full data.
6. For article runs, preserve no-leakage and posterior identity checks.

### Documentation Pass

1. Add a tracked note for each new mode.
2. State the method status: implemented, experimental, or deferred.
3. Include commands, seeds, controls, and test results.
4. Record limitations and stop gates.
5. Avoid claiming performance improvement without paired runtime and memory
   evidence.

## Recommended Implementation Sequence

The safe order is:

1. keep exact chunked VB as the baseline;
2. implement package static AL stochastic mini-batch VB;
3. route package Q-DESN AL through the stochastic static AL path;
4. add package-level AL example comparisons;
5. implement package hybrid AL with periodic full refresh;
6. consider variance-reduced AL;
7. derive and implement approximate exAL only after AL approximate modes are
   stable;
8. derive article GloFAS approximate AL only after package AL approximate modes
   are stable;
9. defer article exAL and multivariate Q-DESN batching until their likelihood
   and prior structures are finalized.

## Implementation Prompt Addendum

Future Codex prompts should point to this document before requesting approximate
batching code. The prompt should require Codex to:

1. verify that the intended mode has a derivation in this file;
2. update this file if implementation choices deviate from the derivation;
3. add tests for every equation-level contract used in code;
4. keep exact chunking regression tests green;
5. label approximate outputs as approximate; and
6. stop if an exAL, article-side, or multivariate mode lacks a complete
   derivation.
