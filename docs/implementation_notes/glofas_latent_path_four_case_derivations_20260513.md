# GloFAS Latent-Path Four-Case Derivation Note

Date: 2026-05-13

## Purpose

This note fixes the mathematical target before implementing the latent-path
GloFAS sampler or variational approximation. It gives one notation for the four
planned cases:

1. AL working likelihood with VB.
2. AL working likelihood with MCMC.
3. exAL working likelihood with VB.
4. exAL working likelihood with MCMC.

The regularized horseshoe is the default readout prior in all four cases. The
origin-state bridge remains a diagnostic baseline and is not the posterior
target described here.

## Shared Notation

Let \(T\) denote the forecast origin. Let \(H\) be the largest contiguous
issued GloFAS horizon available after applying the requested cutoff window. If
the config requests horizons \(1,\ldots,H_{\mathrm{req}}\) but the archived
issued ensemble contains only horizons \(1,\ldots,H\), the analysis uses
\(H\) and records \(H_{\mathrm{req}}\) separately.

The observed data are

```text
Y_1:T                         reference USGS history
G^ret_1:T                     retrospective GloFAS history
G^ens_{T+h,m}, h = 1:H        issued GloFAS ensemble members
```

The missing forecast-window reference path is

```text
Y_F = (Y_{T+1}, ..., Y_{T+H})'.
```

The available covariate path is denoted by \(C_{1:T+H}\). For \(t\le T\),
the Q-DESN states are computed from observed history. For \(t>T\), the state
is a deterministic function of the stored state at \(T\), strictly lagged
output values, the origin-available covariate path, and the proposed \(Y_F\).
The design row at \(T+h\) may depend on earlier components of \(Y_F\) through
output lags, but it may not use \(Y_{T+h}\) itself as an input. Write the
resulting readout feature blocks as

```text
x_t(Y_F, C)    reference-quantile feature block,
z_t(Y_F, C)    GloFAS-discrepancy feature block.
```

The first implementation may set \(z_t=x_t\), but the derivation permits
different feature blocks. With

```text
theta = (beta', alpha')',
```

define source-specific augmented rows

```text
h_t^Y(Y_F) = ( x_t(Y_F, C)', 0' )',
h_t^G(Y_F) = ( x_t(Y_F, C)', z_t(Y_F, C)' )'.
```

The readout locations are

```text
q^Y_t       = h_t^Y(Y_F)' theta = x_t(Y_F, C)' beta,
q^G_t       = h_t^G(Y_F)' theta = q^Y_t + z_t(Y_F, C)' alpha,
delta^G_t   = z_t(Y_F, C)' alpha.
```

Let \(\mathcal I_Y^H\) index historical reference rows, \(\mathcal I_Y^F\)
index latent future reference rows, \(\mathcal I_G^R\) index retrospective
GloFAS rows, and \(\mathcal I_G^E\) index issued ensemble rows. For a generic
row \(i\), let \(c_i\in\{Y,G\}\) be the source label, \(h_i(Y_F)\) the
augmented row, and

```text
mu_i(Y_F, theta) = h_i(Y_F)' theta.
```

The response attached to row \(i\) is \(Z_i(Y_F)\). It is observed for
historical USGS, retrospective GloFAS, and issued GloFAS rows. It equals the
corresponding component of \(Y_F\) for future reference rows.
Equivalently,

```text
Z_i(Y_F) = z_i^o + u_i' Y_F,
```

where \(u_i=0\) for observed rows and \(u_i\) is the appropriate canonical
basis vector for a future reference row.

The GloFAS scale parameter \(\sigma_G\) is shared by retrospective and issued
GloFAS rows. For exAL, the GloFAS asymmetry parameter \(\gamma_G\) is also
shared by retrospective and issued GloFAS rows.

## AL Complete-Data Target

Let

```text
A0 = (1 - 2 p0) / {p0(1 - p0)},
B0 = 2 / {p0(1 - p0)}.
```

For each row \(i\), introduce \(v_i>0\). Conditional on \(Y_F\), the AL
augmentation is

```text
v_i | sigma_{c_i} ~ Exp(rate = 1 / sigma_{c_i}),
Z_i(Y_F) | theta, sigma_{c_i}, v_i, Y_F
  ~ N(mu_i(Y_F, theta) + A0 v_i, sigma_{c_i} B0 v_i).
```

Let \(\Theta_{\mathrm{rhs}}\) collect the regularized-horseshoe auxiliary
scales for the non-intercept entries of \(\theta\). The AL posterior is

```text
p(theta, Theta_rhs, sigma_Y, sigma_G, v, Y_F | data)
  proportional to
  p(theta, Theta_rhs) p(sigma_Y) p(sigma_G)
  product_i [
    N{Z_i(Y_F) | mu_i(Y_F, theta) + A0 v_i,
      sigma_{c_i} B0 v_i}
    Exp(v_i | rate = 1 / sigma_{c_i})
  ],
```

where rows in \(\mathcal I_Y^F\) use the latent response value from \(Y_F\).
This is the common target for AL-VB and AL-MCMC.

## exAL Complete-Data Target

For exAL, source \(c\) has \((\sigma_c,\gamma_c)\). For each row introduce
\(v_i>0\) and \(s_i>0\). With \(A_\gamma\), \(B_\gamma\), and \(D_\gamma\)
defined as in the supplement,

```text
v_i | sigma_{c_i} ~ Exp(rate = 1 / sigma_{c_i}),
s_i               ~ positive-truncated N(0, 1),
Z_i(Y_F) | theta, sigma_{c_i}, gamma_{c_i}, v_i, s_i, Y_F
  ~ N(mu_i(Y_F, theta)
      + sigma_{c_i} D_{gamma_{c_i}} s_i
      + A_{gamma_{c_i}} v_i,
      sigma_{c_i} B_{gamma_{c_i}} v_i).
```

The exAL posterior is

```text
p(theta, Theta_rhs, {sigma_c, gamma_c}, v, s, Y_F | data)
  proportional to
  p(theta, Theta_rhs)
  product_c p(sigma_c) pi_gamma(gamma_c) 1{L < gamma_c < U}
  product_i [
    N{Z_i(Y_F) | mu_i(Y_F, theta)
      + sigma_{c_i} D_{gamma_{c_i}} s_i
      + A_{gamma_{c_i}} v_i,
      sigma_{c_i} B_{gamma_{c_i}} v_i}
    Exp(v_i | rate = 1 / sigma_{c_i})
    TN_+(s_i | 0, 1)
  ].
```

This is the common target for exAL-VB and exAL-MCMC. Setting \(\gamma_c=0\)
and removing \(s_i\) gives the AL target.

## Conditional Fixed-Design Blocks

Given a proposed \(Y_F\), the augmented design matrix \(H(Y_F)\) is fixed. The
coefficient update is therefore Gaussian in the MCMC cases and Gaussian in the
conditional VB coordinate update. Define a row-specific adjusted response and
precision weight:

For AL,

```text
Z_i^* = Z_i(Y_F) - A0 v_i,
w_i   = 1 / (sigma_{c_i} B0 v_i).
```

For exAL,

```text
Z_i^* = Z_i(Y_F)
        - sigma_{c_i} D_{gamma_{c_i}} s_i
        - A_{gamma_{c_i}} v_i,
w_i   = 1 / (sigma_{c_i} B_{gamma_{c_i}} v_i).
```

Let \(P_\theta\) be the conditional RHS prior precision, including weak
Gaussian priors for the intercepts. Then

```text
Sigma_theta = { H(Y_F)' Omega H(Y_F) + P_theta }^{-1},
m_theta     = Sigma_theta { H(Y_F)' Omega Z^* + P_theta b_theta },
theta | rest, Y_F ~ N(m_theta, Sigma_theta).
```

The RHS scale updates remain inverse-gamma conditional on \(\theta\). The
RHS hierarchy is not the source of any non-conjugate block.

## Future-Path Kernel

The nonstandard part of the latent-path model is the full conditional or
variational factor for \(Y_F\). Let \(\mathcal I_F=\mathcal I_Y^F\cup
\mathcal I_G^E\) denote rows whose response or feature row depends on the
future path. Historical rows do not change when \(Y_F\) changes.

For AL, the log-kernel for \(Y_F\) is

```text
ell_F^AL(Y_F)
  = sum_{i in I_F} log N{
      Z_i(Y_F) | h_i(Y_F)' theta + A0 v_i,
      sigma_{c_i} B0 v_i
    },
```

up to terms not depending on \(Y_F\). For exAL,

```text
ell_F^exAL(Y_F)
  = sum_{i in I_F} log N{
      Z_i(Y_F) | h_i(Y_F)' theta
        + sigma_{c_i} D_{gamma_{c_i}} s_i
        + A_{gamma_{c_i}} v_i,
      sigma_{c_i} B_{gamma_{c_i}} v_i
    }.
```

These kernels are not Gaussian because \(h_i(Y_F)\) is generated by the
reservoir recursion and because future reference rows have
\(Z_i(Y_F)=Y_{T+h}\). Updating \(Y_F\) requires a block or componentwise
nonconjugate step. Only the \(H\) forecast-window state rows need to be
recomputed after a proposal; historical rows stay fixed.

## Future-Path Laplace--Delta Approximation

The VB implementation will use a Laplace--Delta approximation for the latent
future path. This is the same organizing principle used for the exAL scale and
asymmetry block, but the block is now \(Y_F\). For a current set of
variational factors \(q_{-F}\), define the expected future-path log target

```text
L_F(Y_F) = E_{-F}{ log p(data, Y_F, theta, Theta_rhs,
                         source parameters, mixture latents) }.
```

Terms not depending on \(Y_F\) may be dropped when finding the mode, but they
remain part of the ELBO bookkeeping. The Laplace factor is

```text
m_F = argmax_Y L_F(Y),
K_F = - Hessian_Y L_F(Y) evaluated at m_F,
q_F(Y_F) approximately N(m_F, V_F),  V_F = K_F^{-1}.
```

The covariance may be full, banded, diagonal, or low-rank plus diagonal, but
the choice must be recorded in the fit object. If the Hessian is regularized,
the ridge added to \(K_F\) must also be recorded. This is a deterministic
Laplace approximation, not a Monte Carlo approximation.

Delta-method expectations are then used for the nonlinear reservoir-dependent
moments that enter the remaining VB coordinates. The default implementation
should use a first-order Delta map for high-dimensional reservoir rows. For a
smooth vector function \(g(Y_F)\), with Jacobian \(J_g\) evaluated at \(m_F\),

```text
E_F{g(Y_F)}
  approximately g(m_F),

Cov_F{g(Y_F)}
  approximately J_g(m_F) V_F J_g(m_F)'.
```

Thus

```text
E_F{g(Y_F) g(Y_F)'}
  approximately g(m_F) g(m_F)'
              + J_g(m_F) V_F J_g(m_F)'.
```

Second-order mean corrections,
\(g_k(m_F)+0.5\operatorname{tr}\{\nabla^2g_k(m_F)V_F\}\), may be added later
for selected low-dimensional summaries. They should not be required for the
first high-dimensional reservoir implementation because they require a Hessian
for each feature component.

For the row function \(h_i(Y_F)\), write

```text
a_i  = E_F{ h_i(Y_F) },
S_i  = E_F{ h_i(Y_F) h_i(Y_F)' },
zbar_i = E_F{ Z_i(Y_F) } = z_i^o + u_i' m_F,
z2bar_i = E_F{ Z_i(Y_F)^2 }
        = zbar_i^2 + u_i' V_F u_i.
```

The cross moment \(b_i=E_F\{h_i(Y_F)Z_i(Y_F)\}\) is

```text
b_i approximately a_i zbar_i + J_i V_F u_i,
```

where \(J_i\) is the Jacobian of \(h_i(Y_F)\) at \(m_F\). This expression is
the first-order Delta approximation to the cross moment. For observed rows,
\(u_i=0\); for historical rows, both \(h_i\) and \(Z_i\) are fixed, so these
moments reduce to the usual fixed-design quantities.

The basic residual moments used below are

```text
e_i = E_q{ Z_i(Y_F) - h_i(Y_F)' theta }
    = zbar_i - a_i' m_theta,

R_i = E_q[ { Z_i(Y_F) - h_i(Y_F)' theta }^2 ]
    = z2bar_i - 2 b_i' m_theta
      + tr[ S_i { Sigma_theta + m_theta m_theta' } ].
```

These are the only future-path moments needed by the AL updates. The exAL
updates use the same \(e_i\) and \(R_i\), together with the source-specific
Laplace--Delta expectations for scale and asymmetry.

## Case 1: AL-VB

Use a variational family

```text
q(theta) q(Theta_rhs) q(sigma_Y) q(sigma_G)
  product_i q(v_i)
  q_F(Y_F).
```

The future-path factor \(q_F\) is the Gaussian Laplace factor defined above.
For AL, the expected log target used to update \(q_F\) is, up to constants
that do not depend on \(Y_F\),

```text
L_F^AL(Y_F)
  = -0.5 B0^{-1} sum_{i in I_F}
      E(sigma_{c_i}^{-1})
      [ E(v_i^{-1}) R_i(Y_F)
        - 2 A0 e_i(Y_F) ],
```

where

```text
e_i(Y_F) = Z_i(Y_F) - h_i(Y_F)' m_theta,
R_i(Y_F) = e_i(Y_F)^2 + h_i(Y_F)' Sigma_theta h_i(Y_F).
```

Terms that do not depend on \(Y_F\), including the \(A_0^2E(v_i)\) part of the
Gaussian likelihood and the exponential latent-prior terms, are handled in the
complete-data ELBO but are not part of the future-path mode or Hessian. After
the Laplace update, the Delta moments \(S_i,a_i,b_i,zbar_i,z2bar_i,e_i,R_i\)
are recomputed and used in the closed-form coordinates.

For the Gaussian coefficient factor, use the Laplace--Delta averaged
quantities

```text
S_i       = E_F{ h_i(Y_F) h_i(Y_F)' },
a_i       = E_F{ h_i(Y_F) },
b_i       = E_F{ h_i(Y_F) Z_i(Y_F) },
zbar_i    = E_F{ Z_i(Y_F) },
z2bar_i   = E_F{ Z_i(Y_F)^2 }.
```

For observed rows, these reduce to the usual fixed-design quantities. For
future reference rows, \(Z_i(Y_F)\) is the matching component of \(Y_F\).
Let

```text
R_i = E_q[ { Z_i(Y_F) - h_i(Y_F)' theta }^2 ]
    = z2bar_i
      - 2 b_i' m_theta
      + tr[ S_i {Sigma_theta + m_theta m_theta'} ].
```

The AL coefficient update is

```text
Sigma_theta =
  [ sum_i B0^{-1} E(sigma_{c_i}^{-1}) E(v_i^{-1}) S_i
    + E(P_theta) ]^{-1},

m_theta =
  Sigma_theta [
    sum_i B0^{-1} E(sigma_{c_i}^{-1})
      { E(v_i^{-1}) b_i - A0 a_i }
    + E(P_theta) b_theta
  ].
```

The AL mixture factors are

```text
q(v_i) = GIG(
  1/2,
  B0^{-1} E(sigma_{c_i}^{-1}) R_i,
  E(sigma_{c_i}^{-1}) { A0^2 / B0 + 2 }
).
```

For each source \(c\),

```text
q(sigma_c) = IG(a_c^*, b_c^*),
a_c^* = a_c + 3 n_c / 2,
b_c^* =
  b_c + sum_{i in I_c} E(v_i)
  + (1 / 2B0) sum_{i in I_c}
    [ E(v_i^{-1}) R_i
      - 2 A0 { zbar_i - a_i' m_theta }
      + A0^2 E(v_i) ].
```

The RHS factors are the inverse-gamma factors already used in the supplement,
with \(E(\theta_j^2)=m_{\theta,j}^2+(\Sigma_\theta)_{jj}\).

The AL-VB objective equals the expected AL complete-data log posterior plus
the entropy of all factors, including \(H\{q_F\}\). With
\(q_F\approx N(m_F,V_F)\),

```text
H{q_F} = 0.5 log |2 pi e V_F|.
```

The likelihood contribution for row \(i\), evaluated with the
Laplace--Delta moments above, is

```text
-0.5 log(2 pi)
-0.5 { E(log sigma_{c_i}) + log B0 + E(log v_i) }
-0.5 B0^{-1} [
    E(sigma_{c_i}^{-1}) E(v_i^{-1}) R_i
    - 2 A0 E(sigma_{c_i}^{-1}) { zbar_i - a_i' m_theta }
    + A0^2 E(sigma_{c_i}^{-1}) E(v_i)
  ].
```

The monitored objective is a Laplace--Delta approximation to the ELBO. It is
deterministic given the current factors and derivative calculations, but it is
not the exact ELBO of the original nonlinear latent-path model.

## Case 2: AL-MCMC

The AL-MCMC sampler targets the AL complete-data posterior above. A valid
iteration is:

1. Given \(Y_F\), build only the forecast-window rows of \(H(Y_F)\).
2. Update \(v_i\) from the AL GIG full conditionals.
3. Update \(\theta\) from the Gaussian fixed-design block.
4. Update the RHS scales from their inverse-gamma full conditionals.
5. Update \(\sigma_Y\) and \(\sigma_G\) from the source-specific inverse-gamma
   full conditionals.
6. Update \(Y_F\) from \(\ell_F^{AL}(Y_F)\) by a documented nonconjugate
   method, such as componentwise slice, block slice, or Metropolis.

The source-specific \(\sigma_G\) update uses both retrospective and issued
GloFAS rows. If \(H=0\), the \(Y_F\) block disappears and the sampler reduces
to the fixed-design discrepancy sampler. If \(Y_F\) is held fixed at a supplied
path, the sampler reduces to the source-stacked fixed-design sampler with
additional forecast-window rows.

## Case 3: exAL-VB

Use the variational family

```text
q(theta) q(Theta_rhs)
  product_c q(sigma_c, gamma_c)
  product_i q(v_i) q(s_i)
  q_F(Y_F).
```

The factor \(q_F\) is again the Gaussian Laplace factor. For exAL, the
expected log target used to update the future path is, up to constants that do
not depend on \(Y_F\),

```text
L_F^exAL(Y_F)
  = -0.5 sum_{i in I_F} [
      M1_{c_i} E(v_i^{-1}) R_i(Y_F)
      - 2 M2_{c_i} E(s_i) E(v_i^{-1}) e_i(Y_F)
      - 2 M6_{c_i} e_i(Y_F)
    ].
```

The remaining exAL terms do not depend on \(Y_F\) and are handled in the
complete-data ELBO. Define \(S_i,a_i,b_i,zbar_i,z2bar_i,e_i,R_i\) as in the
AL-VB case, and define

```text
ebar_i = zbar_i - a_i' m_theta.
```

For each source \(c\), let the Laplace--Delta approximation supply smooth
expectations

```text
M1_c = E{ 1 / (sigma_c B_gamma_c) },
M2_c = E{ D_gamma_c / B_gamma_c },
M3_c = E{ sigma_c D_gamma_c^2 / B_gamma_c },
M4_c = E{ A_gamma_c D_gamma_c / B_gamma_c },
M5_c = E{ A_gamma_c^2 / (sigma_c B_gamma_c) + 2 / sigma_c },
M6_c = E{ A_gamma_c / (sigma_c B_gamma_c) }.
```

The coefficient factor is

```text
Sigma_theta =
  [ sum_i M1_{c_i} E(v_i^{-1}) S_i + E(P_theta) ]^{-1},

m_theta =
  Sigma_theta [
    sum_i {
      M1_{c_i} E(v_i^{-1}) b_i
      - M2_{c_i} E(s_i) E(v_i^{-1}) a_i
      - M6_{c_i} a_i
    }
    + E(P_theta) b_theta
  ].
```

The exAL latent factors are

```text
q(v_i) = GIG(1/2, chi_i, psi_i),
chi_i =
  M1_{c_i} R_i
  - 2 M2_{c_i} E(s_i) ebar_i
  + M3_{c_i} E(s_i^2),
psi_i = M5_{c_i},

q(s_i) = TN_+(m_{s,i}, V_{s,i}),
V_{s,i} = [1 + M3_{c_i} E(v_i^{-1})]^{-1},
m_{s,i} =
  V_{s,i} [
    M2_{c_i} ebar_i E(v_i^{-1}) - M4_{c_i}
  ].
```

For each source, the Laplace--Delta target for
\((\sigma_c,\gamma_c)\) is

```text
ell_c^LD(eta_c)
  = E_{-(sigma_c,gamma_c)}
      [ log p(Z^c(Y_F) | theta, sigma_c, gamma_c, v^c, s^c, H(Y_F))
        + log p(v^c | sigma_c)
        + log p(sigma_c) + log pi_gamma(gamma_c) ]
    + log |J_T(eta_c)|.
```

The expectation includes \(q_F\), so forecast-window design and response
moments must be evaluated by the same Laplace--Delta approximation used in the
\(q_F\) step. The exAL-VB objective is the exAL complete-data ELBO with
\(H\{q_F\}\), evaluated analytically for fixed-design terms and by
Laplace--Delta for future-path terms.

## Case 4: exAL-MCMC

The exAL-MCMC sampler targets the exAL complete-data posterior. A valid
iteration is:

1. Given \(Y_F\), build only the forecast-window rows of \(H(Y_F)\).
2. Update \(v_i\) from the exAL GIG full conditionals.
3. Update \(s_i\) from the positive-truncated Normal full conditionals.
4. Update \(\theta\) from the Gaussian fixed-design block.
5. Update the RHS scales from their inverse-gamma full conditionals.
6. Update each source-specific \((\sigma_c,\gamma_c)\) block using the
   transformed log-kernel from the supplement.
7. Update \(Y_F\) from \(\ell_F^{exAL}(Y_F)\) by a documented nonconjugate
   method.

The GloFAS block for \((\sigma_G,\gamma_G)\) uses both retrospective and issued
GloFAS rows by default. Holding \(\gamma_c=0\) and dropping \(s_i\) recovers
the AL-MCMC case.

## Cross-Case Validation Checks

The four derivations should satisfy these reductions before code is written.

1. **No future horizon.** If \(H=0\), \(Y_F\) and \(q_F\) disappear and the
   fixed-design GloFAS discrepancy derivation in the supplement is recovered.
2. **Fixed future path.** If \(Y_F\) is fixed at a supplied path, all four
   cases reduce to source-stacked fixed-design Q-DESN updates with extra
   forecast-window rows.
3. **Reference-only model.** If GloFAS rows and \(\alpha\) are removed, the
   model reduces to the ordinary Q-DESN readout.
4. **AL as exAL reduction.** If \(\gamma_c=0\) and \(s_i\) is omitted, the
   exAL formulas reduce to the AL formulas with \(A_0,B_0\).
5. **RHS conjugacy.** The RHS product representation contributes only
   inverse-gamma shrinkage-scale updates conditional on \(\theta\). It is not
   responsible for the nonconjugate future-path block or the exAL scale and
   asymmetry block.
6. **GloFAS parameter sharing.** The \(\sigma_G\) update, and the
   \((\sigma_G,\gamma_G)\) update for exAL, must use both retrospective and
   issued GloFAS rows unless a future diagnostic explicitly splits these
   sources.
7. **No leakage.** Held-out USGS values may appear only as validation oracles.
   In fitting, post-cutoff reference values enter only through \(Y_F\).
   Forecast-window reservoir rows must use strictly lagged components of
   \(Y_F\); a row for \(T+h\) must not use \(Y_{T+h}\) as an input feature.
8. **VB objective labeling.** The monitored quantity is a Laplace--Delta ELBO
   approximation. It should not be labeled the exact ELBO of the original
   nonlinear latent-path model.

## Implementation Consequence

The first code target should be AL-VB with the shared notation above. The
implementation must include the future path, output-lag recursion, and
forecast-window covariates in the same design map. AL-MCMC is then a reference
posterior simulation check for the same target. exAL-VB and exAL-MCMC should be
added only after the AL target passes synthetic path-recovery checks.
