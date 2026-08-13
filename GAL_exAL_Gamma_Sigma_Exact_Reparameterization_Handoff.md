# Exact Posterior-Preserving Improvements for the GAL/exAL \((\sigma,\gamma)\) Block

**Codex theory and implementation handoff**  
**Date:** 2026-08-06  
**Scope:** quantile-fixed generalized asymmetric Laplace (GAL), called **exAL** in the Q-DESN code and manuscripts  
**Primary requirement:** preserve the original quantile-fixed GAL/exAL likelihood, prior, quantile anchor, posterior, and posterior predictive distribution

---

## Executive decision

The current scientific model should **not** be replaced by a different “more conjugate” error distribution. The implementation target remains the original three-parameter quantile-fixed GAL/exAL family of Yan, Zheng, and Kottas:

\[
Y_i\mid \mu_i,\sigma,\gamma
\sim \operatorname{exAL}_{p_0}(\mu_i,\sigma,\gamma),
\qquad
Q_{p_0}(Y_i\mid \mu_i,\sigma,\gamma)=\mu_i.
\]

The purpose of the proposed work is computational:

1. preserve the exact original GAL/exAL posterior;
2. change the latent coordinates so the scale–shape geometry is simpler;
3. integrate \(\sigma\) analytically out of the \(\gamma\) update;
4. sample \(\gamma\) from a one-dimensional collapsed density;
5. then draw \(\sigma\) exactly from its generalized inverse-Gaussian (GIG) conditional;
6. use the same algebra to replace the two-dimensional Laplace–Delta exAL block in variational Bayes with a one-dimensional structured quadrature update.

The **recommended production MCMC parameterization** is

\[
\boxed{u_i=B_\gamma v_i}
\]

combined with the exact block factorization

\[
\boxed{
\gamma\mid \text{rest except }\sigma
\quad\text{followed by}\quad
\sigma\mid\gamma,\text{rest}.
}
\]

The first draw uses a one-dimensional Bessel-collapsed density; the second is GIG. The recommended numerical coordinate for the first draw is the internal probability

\[
p_\gamma=p(\gamma,p_0)
\]

or its logit, with the induced prior Jacobian included exactly.

This is **not** a new likelihood and **not** a posterior approximation. For MCMC it is a change of latent variables plus exact marginalization and blocking. Therefore, after integrating out the auxiliary variables, the posterior of every scientific parameter and every posterior predictive quantity is identical to that under the original GAL/exAL model.

The earlier idea of freeing the parent-GAL parameters and recentering the resulting distribution is **not equivalent** to the current three-parameter quantile-fixed GAL/exAL model. It must not be implemented in the current exact-model branch. It is a possible future model-development project only.

---

# 1. Scientific purpose of the original GAL/exAL model

## 1.1 Why the model exists

The ordinary asymmetric Laplace (AL) likelihood is useful for Bayesian quantile regression because its location parameter is a chosen quantile and its Gaussian–exponential mixture supports tractable conditional updates. Its main modeling restriction is that, once the target quantile level \(p_0\) is fixed, the shape of the AL error distribution is essentially fixed as well: the mode is pinned to the target quantile and the left/right tail behavior is determined by \(p_0\).

The quantile-fixed GAL/exAL extends the AL while retaining the quantile anchor. For a fixed \(p_0\),

- \(\mu_i\) remains exactly the \(p_0\)-quantile;
- \(\sigma>0\) remains a scale parameter;
- \(\gamma\) changes the mode, skewness, and tail behavior;
- \(\gamma=0\) recovers the AL special case.

This is exactly why the current Q-DESN uses exAL rather than replacing it by a generic skew distribution: it gives a flexible likelihood while preserving the direct interpretation

\[
Q_{p_0}(Y_i\mid x_i)=\mu_i=x_i^\top\beta
\]

or the corresponding dynamic/readout location in a more general model.

## 1.2 Non-negotiable invariance contract

Any accepted computational modification must preserve all of the following:

1. **Same marginal likelihood**
   \[
   p(y_i\mid\mu_i,\sigma,\gamma)
   =
   f_{p_0}^{\mathrm{GAL}}(y_i\mid\mu_i,\sigma,\gamma).
   \]

2. **Same quantile anchor**
   \[
   \Pr(Y_i\leq \mu_i\mid\mu_i,\sigma,\gamma)=p_0.
   \]

3. **Same parameter support**
   \[
   \sigma>0,\qquad \gamma\in(L,U),
   \]
   with \(L\) and \(U\) determined by the original quantile-fixing construction.

4. **Same priors on scientific parameters**, unless a prior change is explicitly studied as a separate model.

5. **Same posterior**
   \[
   \pi(\beta,\sigma,\gamma,\text{shrinkage parameters}\mid y).
   \]

6. **Same posterior predictive distribution** after integrating all auxiliary variables.

A new latent variable is allowed. A one-to-one coordinate transformation is allowed. Exact integration of a nuisance parameter inside a Gibbs block is allowed. A different likelihood, a different prior induced accidentally by a transformation, or a different relationship among the GAL shape quantities is not allowed.

---

# 2. Original quantile-fixed GAL/exAL hierarchy

Fix the target quantile level \(p_0\in(0,1)\). Define

\[
g(\gamma)
=
2\Phi(-|\gamma|)\exp(\gamma^2/2),
\]

and

\[
p_\gamma
=
p(\gamma,p_0)
=
\mathbf 1\{\gamma<0\}
+
\frac{p_0-\mathbf 1\{\gamma<0\}}{g(\gamma)}.
\]

The admissible support is \((L,U)\), where

\[
g(L)=1-p_0,\qquad g(U)=p_0.
\]

Define the standard GAL functions

\[
A_\gamma
=
\frac{1-2p_\gamma}{p_\gamma(1-p_\gamma)},
\qquad
B_\gamma
=
\frac{2}{p_\gamma(1-p_\gamma)},
\]

\[
C_\gamma
=
\{\mathbf 1(\gamma>0)-p_\gamma\}^{-1},
\qquad
\lambda_\gamma
=
C_\gamma|\gamma|.
\]

The signed coefficient \(\lambda_\gamma\) is the coefficient multiplying the positive half-normal latent variable. It is negative when \(\gamma<0\), zero at \(\gamma=0\), and positive when \(\gamma>0\).

The article’s latent representation is

\[
Y_i
\mid \mu_i,\sigma,\gamma,z_i,s_i
\sim
N\!\left(
\mu_i+\sigma\lambda_\gamma s_i+\sigma A_\gamma z_i,\;
\sigma^2 B_\gamma z_i
\right),
\]

\[
z_i\sim\operatorname{Exp}(1),
\qquad
s_i\sim N^+(0,1).
\]

The current implementation uses

\[
v_i=\sigma z_i.
\]

Then

\[
\boxed{
Y_i
\mid \mu_i,\sigma,\gamma,v_i,s_i
\sim
N\!\left(
\mu_i+\sigma\lambda_\gamma s_i+A_\gamma v_i,\;
\sigma B_\gamma v_i
\right)
}
\]

and

\[
\boxed{
v_i\mid\sigma
\sim
\operatorname{Exp}(\text{mean}=\sigma),
\qquad
s_i\sim N^+(0,1).
}
\]

With a Gaussian readout prior, \(v_i\), \(s_i\), and the readout coefficients have standard conditional distributions. Under the independent inverse-gamma scale prior

\[
\sigma\sim\operatorname{IG}(a_\sigma,b_\sigma),
\qquad
\pi(\sigma)\propto
\sigma^{-(a_\sigma+1)}e^{-b_\sigma/\sigma},
\]

the conditional \(\sigma\mid\gamma,\ldots\) is GIG. The only nonstandard scalar is \(\gamma\).

---

# 3. Why the current \((\sigma,\gamma)\) block mixes poorly

The difficulty is not simply that \(\gamma\) lacks a named conditional distribution. The model creates genuine posterior ridges.

Write the standardized GAL error as

\[
E_\gamma
=
\lambda_\gamma S
+
A_\gamma Z
+
\sqrt{B_\gamma Z}\,\varepsilon,
\]

where

\[
S\sim N^+(0,1),
\quad
Z\sim\operatorname{Exp}(1),
\quad
\varepsilon\sim N(0,1).
\]

Then

\[
E(E_\gamma)
=
A_\gamma
+
\lambda_\gamma\sqrt{\frac{2}{\pi}},
\]

and

\[
V_\gamma
=
\operatorname{Var}(E_\gamma)
=
B_\gamma
+
A_\gamma^2
+
\lambda_\gamma^2\left(1-\frac{2}{\pi}\right).
\]

Therefore

\[
\operatorname{Var}(Y_i\mid\mu_i,\sigma,\gamma)
=
\sigma^2V_\gamma.
\]

The parameter \(\sigma\) is a location-scale multiplier, but it is not the marginal standard deviation. Changes in \(\gamma\) alter \(V_\gamma\), and the likelihood can often preserve a similar empirical spread by moving \(\sigma\) in the opposite direction. There is also dependence through the displacement product

\[
\sigma\lambda_\gamma.
\]

Consequently, a sampler that alternates

\[
\sigma\mid\gamma,\ldots
\quad\text{and}\quad
\gamma\mid\sigma,\ldots
\]

can move slowly along a strongly correlated posterior ridge even when both individual updates are mathematically correct.

A better proposal distribution can mitigate this problem, but it does not remove the conditional dependence. The central recommendation is therefore to integrate \(\sigma\) out of the \(\gamma\) update and then redraw \(\sigma\) conditionally. This converts a highly correlated two-step transition into an exact blocked transition.

---

# 4. Exact-equivalence classification

The distinction below is essential.

| Proposal | Same GAL/exAL likelihood? | Same prior/posterior for \((\beta,\sigma,\gamma)\)? | Exact MCMC target? | Recommended status |
|---|---:|---:|---:|---|
| Existing \(v_i=\sigma z_i\) augmentation | Yes | Yes | Yes | Validation baseline |
| Integrate \(\sigma\) out of the \(\gamma\) update in the existing \(v\)-augmentation | Yes | Yes | Yes | Implement first as minimal-change reference |
| Replace \(v_i\) by \(u_i=B_\gamma v_i\), with its exact Jacobian-induced density | Yes | Yes | Yes | Preferred production augmentation |
| Sample \(\gamma\) through \(p_\gamma\) or \(\operatorname{logit}(p_\gamma)\), including the exact Jacobian | Yes | Yes | Yes | Recommended numerical coordinate |
| Interweave \(\sigma\) with actual standard deviation \(\omega=\sigma\sqrt{V_\gamma}\), using the transformed target | Yes | Yes | Yes | Optional second-stage improvement |
| Integrate \(v_i\) out during a correctly ordered \(\gamma\) refresh | Yes | Yes | Yes | Optional partial-collapse refresh |
| Replace VB–LD by the structured Bessel/GIG \(q(\sigma,\gamma)\) factor | Yes | Same model target; VB remains approximate | Not MCMC | Recommended VB improvement |
| Put a uniform prior on \(p_\gamma\) when the original prior was uniform on \(\gamma\) | Yes | **No** | Targets a different posterior | Do not do silently |
| Free the parent-GAL \(p\) and skew displacement and recenter afterward | **No: larger/different family** | **No** | Exact for a different model | Future research only |
| Fix \(\gamma\), fix \(\sigma\), or replace exAL by AL for convenience | No, except as a separately declared submodel | No | Different target | Not an inference “fix” |

For the current project, only the first six MCMC entries and the structured VB entry satisfy the intended model-preservation requirement.

---

# 5. Preferred latent reparameterization: \(u_i=B_\gamma v_i\)

## 5.1 Definition

Define

\[
\boxed{
u_i=B_\gamma v_i.
}
\]

For every fixed \(\gamma\), this is a one-to-one transformation between \(v_i>0\) and \(u_i>0\):

\[
v_i=\frac{u_i}{B_\gamma},
\qquad
\left|\frac{\partial v_i}{\partial u_i}\right|
=
\frac{1}{B_\gamma}.
\]

Because

\[
v_i\mid\sigma
\sim
\operatorname{Exp}(\text{rate}=1/\sigma),
\]

the transformed latent density is

\[
p(u_i\mid\sigma,\gamma)
=
\frac{1}{\sigma B_\gamma}
\exp\!\left(-\frac{u_i}{\sigma B_\gamma}\right),
\qquad u_i>0.
\]

Equivalently,

\[
\boxed{
u_i\mid\sigma,\gamma
\sim
\operatorname{Exp}\!\left(
\text{rate}
=
\frac{1}{\sigma B_\gamma}
=
\frac{p_\gamma(1-p_\gamma)}{2\sigma}
\right).
}
\]

The observation model becomes

\[
A_\gamma v_i
=
\frac{A_\gamma}{B_\gamma}u_i.
\]

Define

\[
k_\gamma
=
\frac{A_\gamma}{B_\gamma}.
\]

Since

\[
\frac{A_\gamma}{B_\gamma}
=
\frac{1-2p_\gamma}{2},
\]

we obtain

\[
\boxed{
k_\gamma
=
\frac12-p_\gamma.
}
\]

The variance simplifies exactly:

\[
\sigma B_\gamma v_i
=
\sigma u_i.
\]

Therefore the transformed hierarchy is

\[
\boxed{
Y_i
\mid \mu_i,\sigma,\gamma,u_i,s_i
\sim
N\!\left(
\mu_i+\sigma\lambda_\gamma s_i+k_\gamma u_i,\;
\sigma u_i
\right)
}
\]

with

\[
\boxed{
u_i\mid\sigma,\gamma
\sim
\operatorname{Exp}\!\left(
\frac{p_\gamma(1-p_\gamma)}{2\sigma}
\right),
\qquad
s_i\sim N^+(0,1).
}
\]

## 5.2 Why this reparameterization is useful

The role of \(u_i=B_\gamma v_i\) is not cosmetic. It does three things.

### First: it removes \(B_\gamma\) from the Gaussian variance

The original conditional variance is

\[
\sigma B_\gamma v_i.
\]

The transformed variance is simply

\[
\sigma u_i.
\]

This reduces the direct entanglement of \(\gamma\) with every observation-specific precision.

### Second: it makes the AL drift linear in \(p_\gamma\)

The coefficient of \(u_i\) is

\[
k_\gamma=\frac12-p_\gamma,
\]

rather than the more nonlinear \(A_\gamma\).

### Third: it exposes the cancellation

\[
\boxed{
k_\gamma^2+p_\gamma(1-p_\gamma)=\frac14.
}
\]

Indeed,

\[
\left(\frac12-p\right)^2+p(1-p)
=
\frac14-p+p^2+p-p^2
=
\frac14.
\]

This identity causes the coefficient of \(u_i\) in its GIG update to become independent of \(\gamma\), and it greatly simplifies the collapsed \((\sigma,\gamma)\) block.

---

# 6. Proof that the \(u\)-augmentation is exactly equivalent

Let \(\vartheta\) collect all scientific parameters other than the auxiliary \(v_i\) or \(u_i\). In particular, \(\vartheta\) includes the readout coefficients, \(\sigma\), \(\gamma\), and any shrinkage parameters.

The original augmented joint density is

\[
p_v(y,v,s,\vartheta)
=
p(\vartheta)
\prod_i
p(y_i\mid v_i,s_i,\vartheta)
p(v_i\mid\sigma)
p(s_i).
\]

Apply the transformation

\[
v_i=\frac{u_i}{B_\gamma}.
\]

Then the transformed joint density is, by the change-of-variables formula,

\[
p_u(y,u,s,\vartheta)
=
p_v\!\left(
y,\frac{u}{B_\gamma},s,\vartheta
\right)
\prod_i\frac{1}{B_\gamma}.
\]

Substitution gives exactly the Normal–exponential hierarchy in Section 5. Therefore

\[
\int_{\mathbb R_+^n}
p_u(y,u,s,\vartheta)\,du
=
\int_{\mathbb R_+^n}
p_v(y,v,s,\vartheta)\,dv.
\]

After also integrating over \(s\),

\[
p_u(y,\vartheta)=p_v(y,\vartheta).
\]

It follows immediately that

\[
\boxed{
\pi_u(\vartheta\mid y)
=
\pi_v(\vartheta\mid y).
}
\]

The auxiliary posterior distributions differ because \(u_i\) and \(v_i\) are different coordinates, but they satisfy the deterministic relationship

\[
u_i=B_\gamma v_i.
\]

Every posterior summary of the scientific parameters is unchanged.

## 6.1 Posterior predictive equivalence

Under the original representation,

\[
Y_i^{\mathrm{rep}}
=
\mu_i
+
\sigma\lambda_\gamma S_i
+
\sigma A_\gamma Z_i
+
\sigma\sqrt{B_\gamma Z_i}\,\varepsilon_i,
\]

where

\[
Z_i\sim\operatorname{Exp}(1).
\]

Set

\[
U_i=\sigma B_\gamma Z_i.
\]

Then

\[
U_i\mid\sigma,\gamma
\sim
\operatorname{Exp}\left(\frac{1}{\sigma B_\gamma}\right),
\]

and

\[
\sigma A_\gamma Z_i
=
\frac{A_\gamma}{B_\gamma}U_i
=
k_\gamma U_i,
\]

\[
\sigma^2B_\gamma Z_i
=
\sigma U_i.
\]

Hence the same predictive draw is

\[
\boxed{
Y_i^{\mathrm{rep}}
=
\mu_i
+
\sigma\lambda_\gamma S_i
+
k_\gamma U_i
+
\sqrt{\sigma U_i}\,\varepsilon_i.
}
\]

The two predictive algorithms are exactly the same under a deterministic change of latent variable.

---

# 7. Standard full conditionals under the \(u\)-augmentation

Let

\[
q_i=y_i-\mu_i.
\]

Use the GIG convention

\[
f(x\mid\nu,\chi,\psi)
\propto
x^{\nu-1}
\exp\left[
-\frac12
\left(
\frac{\chi}{x}+\psi x
\right)
\right],
\qquad x>0.
\]

## 7.1 \(u_i\) conditional

Conditioning on \((\beta,\sigma,\gamma,s_i)\), the terms involving \(u_i\) are

\[
u_i^{-1/2}
\exp\left[
-\frac{(q_i-\sigma\lambda_\gamma s_i-k_\gamma u_i)^2}
{2\sigma u_i}
-\frac{p_\gamma(1-p_\gamma)}{2\sigma}u_i
\right].
\]

Using

\[
k_\gamma^2+p_\gamma(1-p_\gamma)=\frac14,
\]

the \(u_i\)-dependent kernel becomes

\[
u_i^{-1/2}
\exp\left[
-\frac12
\left\{
\frac{(q_i-\sigma\lambda_\gamma s_i)^2/\sigma}{u_i}
+
\frac{1}{4\sigma}u_i
\right\}
\right].
\]

Therefore

\[
\boxed{
u_i\mid\cdots
\sim
\operatorname{GIG}
\left(
\frac12,\;
\frac{(q_i-\sigma\lambda_\gamma s_i)^2}{\sigma},\;
\frac{1}{4\sigma}
\right).
}
\]

The second GIG coefficient is independent of \(\gamma\). This is one of the principal computational advantages of the transformation.

## 7.2 \(s_i\) conditional

The \(s_i\)-dependent kernel is Normal, truncated to \(s_i>0\):

\[
s_i\mid\cdots
\sim
N^+(m_{s_i},V_{s_i}),
\]

where

\[
\boxed{
V_{s_i}
=
\left(
1+\frac{\sigma\lambda_\gamma^2}{u_i}
\right)^{-1}
}
\]

and

\[
\boxed{
m_{s_i}
=
V_{s_i}
\frac{
\lambda_\gamma(q_i-k_\gamma u_i)
}{
u_i
}.
}
\]

The sign of \(\lambda_\gamma\) must be retained.

## 7.3 Readout coefficients

For a Gaussian readout prior

\[
\beta\sim N(m_0,V_0),
\]

define

\[
y_i^\star
=
y_i-\sigma\lambda_\gamma s_i-k_\gamma u_i,
\]

and

\[
W
=
\operatorname{diag}
\left(
\frac{1}{\sigma u_1},\ldots,\frac{1}{\sigma u_n}
\right).
\]

Then

\[
\boxed{
\beta\mid\cdots
\sim
N(m_\beta,V_\beta),
}
\]

\[
V_\beta
=
(V_0^{-1}+X^\top W X)^{-1},
\]

\[
m_\beta
=
V_\beta(V_0^{-1}m_0+X^\top W y^\star).
\]

For ridge or regularized-horseshoe Q-DESN, replace \(V_0^{-1}\) by the current conditional prior precision. The exAL reparameterization does not alter the shrinkage hierarchy.

---

# 8. Exact blocked update for \((\gamma,\sigma)\)

This is the main mixing improvement.

## 8.1 Joint conditional under the \(u\)-augmentation

Assume

\[
\sigma\sim\operatorname{IG}(a_\sigma,b_\sigma)
\]

independently of \(\gamma\) and of the readout prior. Define

\[
r_i(\gamma)
=
q_i-k_\gamma u_i.
\]

Let

\[
\nu
=
-\left(a_\sigma+\frac{3n}{2}\right).
\]

Define

\[
\boxed{
c_\gamma
=
2b_\sigma
+
\sum_{i=1}^n
\left[
\frac{r_i(\gamma)^2}{u_i}
+
p_\gamma(1-p_\gamma)u_i
\right],
}
\]

\[
\boxed{
d_\gamma
=
\lambda_\gamma^2
\sum_{i=1}^n
\frac{s_i^2}{u_i},
}
\]

and

\[
\boxed{
e_\gamma
=
\lambda_\gamma
\sum_{i=1}^n
\frac{s_i r_i(\gamma)}{u_i}.
}
\]

Then, up to factors constant in \((\sigma,\gamma)\),

\[
\boxed{
\begin{aligned}
\pi(\sigma,\gamma\mid\text{rest})
\propto{}&
\pi_\gamma(\gamma)
\left\{
\frac{p_\gamma(1-p_\gamma)}{2}
\right\}^{n}
e^{e_\gamma}\\
&\times
\sigma^{\nu-1}
\exp\left[
-\frac12
\left(
\frac{c_\gamma}{\sigma}
+
d_\gamma\sigma
\right)
\right].
\end{aligned}
}
\]

The term \(e_\gamma\) is independent of \(\sigma\), but it is generally not independent of \(\gamma\).

## 8.2 Exact \(\sigma\mid\gamma\) conditional

For fixed \(\gamma\),

\[
\boxed{
\sigma\mid\gamma,\text{rest}
\sim
\operatorname{GIG}
(\nu,c_\gamma,d_\gamma).
}
\]

At \(\gamma=0\),

\[
\lambda_\gamma=0,
\qquad
d_\gamma=0,
\qquad
e_\gamma=0,
\]

and the limit is inverse-gamma:

\[
\boxed{
\sigma\mid\gamma=0,\text{rest}
\sim
\operatorname{IG}
\left(
-\nu,\frac{c_0}{2}
\right).
}
\]

## 8.3 Exact collapsed \(\gamma\) conditional

The GIG integral is

\[
\int_0^\infty
\sigma^{\nu-1}
\exp\left[
-\frac12
\left(
\frac{c}{\sigma}+d\sigma
\right)
\right]d\sigma
=
2\left(\frac{c}{d}\right)^{\nu/2}
K_\nu(\sqrt{cd}),
\]

where \(K_\nu\) is the modified Bessel function of the second kind.

Therefore

\[
\boxed{
\begin{aligned}
\pi(\gamma\mid\text{rest excluding }\sigma)
\propto{}&
\pi_\gamma(\gamma)
\left\{
\frac{p_\gamma(1-p_\gamma)}{2}
\right\}^{n}
e^{e_\gamma}\\
&\times
2
\left(
\frac{c_\gamma}{d_\gamma}
\right)^{\nu/2}
K_\nu\!\left(\sqrt{c_\gamma d_\gamma}\right).
\end{aligned}
}
\]

This is a scalar density on the original bounded support \((L,U)\).

At \(d_\gamma=0\), use the continuous limit

\[
\boxed{
\int_0^\infty
\sigma^{\nu-1}e^{-c_\gamma/(2\sigma)}d\sigma
=
\Gamma(-\nu)
\left(\frac{c_\gamma}{2}\right)^\nu.
}
\]

The implementation should switch to this limit, or a controlled asymptotic expansion, when \(d_\gamma\) is numerically close to zero.

## 8.4 Why this is an exact Gibbs block

The full block conditional admits the factorization

\[
\pi(\gamma,\sigma\mid\text{rest})
=
\pi(\gamma\mid\text{rest excluding }\sigma)
\pi(\sigma\mid\gamma,\text{rest}).
\]

Therefore the sequence

1. draw \(\gamma\) from the collapsed scalar density;
2. draw \(\sigma\) from the GIG conditional;

is an exact joint update of \((\gamma,\sigma)\). It is not an approximation and does not require an MH correction if the scalar \(\gamma\) draw itself is exact, for example via slice sampling.

The posterior \(\sigma\)-\(\gamma\) correlation can remain large in the stored draws because that correlation belongs to the target distribution. What changes is the transition: the \(\gamma\) proposal no longer conditions on the current \(\sigma\), so the chain is not forced to crawl along the conditional ridge.

---

# 9. Additional simplification of \(c_\gamma\)

Expand

\[
\frac{(q_i-k_\gamma u_i)^2}{u_i}
=
\frac{q_i^2}{u_i}
-2k_\gamma q_i
+k_\gamma^2u_i.
\]

Using

\[
k_\gamma^2+p_\gamma(1-p_\gamma)=\frac14,
\]

we obtain

\[
\boxed{
c_\gamma
=
2b_\sigma
+
\sum_{i=1}^n
\left[
\frac{q_i^2}{u_i}
-(1-2p_\gamma)q_i
+\frac{u_i}{4}
\right].
}
\]

Also,

\[
\boxed{
e_\gamma
=
\lambda_\gamma
\left[
\sum_i\frac{s_iq_i}{u_i}
-
k_\gamma\sum_i s_i
\right],
}
\]

and

\[
\boxed{
d_\gamma
=
\lambda_\gamma^2
\sum_i\frac{s_i^2}{u_i}.
}
\]

Thus, after computing the following summaries once per outer MCMC iteration,

\[
S_{q^2/u}=\sum_i\frac{q_i^2}{u_i},
\quad
S_q=\sum_iq_i,
\quad
S_u=\sum_i u_i,
\]

\[
S_{sq/u}=\sum_i\frac{s_iq_i}{u_i},
\quad
S_s=\sum_i s_i,
\quad
S_{s^2/u}=\sum_i\frac{s_i^2}{u_i},
\]

each evaluation of the collapsed log density is \(O(1)\) in \(n\):

\[
c_\gamma
=
2b_\sigma
+
S_{q^2/u}
-
(1-2p_\gamma)S_q
+
\frac14S_u,
\]

\[
d_\gamma
=
\lambda_\gamma^2S_{s^2/u},
\]

\[
e_\gamma
=
\lambda_\gamma
(S_{sq/u}-k_\gamma S_s).
\]

This makes a robust scalar slice sampler or dense one-dimensional quadrature practical even for a long time series.

---

# 10. Minimal-change collapse in the current \(v\)-parameterization

Codex should implement this version first as a validation bridge because it leaves the rest of the current code unchanged.

Let

\[
r_i^{(v)}(\gamma)
=
q_i-A_\gamma v_i.
\]

Define

\[
\boxed{
c_\gamma^{(v)}
=
2b_\sigma
+
2\sum_i v_i
+
\sum_i
\frac{
\{r_i^{(v)}(\gamma)\}^2
}{
B_\gamma v_i
},
}
\]

\[
\boxed{
d_\gamma^{(v)}
=
\sum_i
\frac{
\lambda_\gamma^2s_i^2
}{
B_\gamma v_i
},
}
\]

\[
\boxed{
e_\gamma^{(v)}
=
\sum_i
\frac{
\lambda_\gamma s_i r_i^{(v)}(\gamma)
}{
B_\gamma v_i
}.
}
\]

Then

\[
\pi(\sigma,\gamma\mid\cdots)
\propto
\pi_\gamma(\gamma)
B_\gamma^{-n/2}
e^{e_\gamma^{(v)}}
\sigma^{\nu-1}
\exp\left[
-\frac12
\left(
\frac{c_\gamma^{(v)}}{\sigma}
+
d_\gamma^{(v)}\sigma
\right)
\right].
\]

Therefore

\[
\boxed{
\pi(\gamma\mid\cdots_{-\sigma})
\propto
\pi_\gamma(\gamma)
B_\gamma^{-n/2}
e^{e_\gamma^{(v)}}
2
\left(
\frac{c_\gamma^{(v)}}{d_\gamma^{(v)}}
\right)^{\nu/2}
K_\nu
\left(
\sqrt{
c_\gamma^{(v)}d_\gamma^{(v)}
}
\right).
}
\]

This gives the same core posterior as the existing sampler. The only algorithmic difference is that the \(\gamma\) update integrates out \(\sigma\).

---

# 11. Critical cross-term audit

Expanding the original Gaussian exponent gives

\[
-\frac{
\{r_i^{(v)}-\sigma\lambda_\gamma s_i\}^2
}{
2\sigma B_\gamma v_i
}
=
-\frac{
\{r_i^{(v)}\}^2
}{
2\sigma B_\gamma v_i
}
+
\frac{
\lambda_\gamma s_i r_i^{(v)}
}{
B_\gamma v_i
}
-
\frac{
\sigma\lambda_\gamma^2s_i^2
}{
2B_\gamma v_i
}.
\]

The middle term is

\[
e_\gamma^{(v)}
=
\sum_i
\frac{
\lambda_\gamma s_i
\{y_i-\mu_i-A_\gamma v_i\}
}{
B_\gamma v_i
}.
\]

It is constant in \(\sigma\), so it may be omitted when deriving only

\[
\pi(\sigma\mid\gamma,\ldots).
\]

It may **not** be omitted from

- \(\pi(\gamma\mid\sigma,\ldots)\);
- the joint \((\sigma,\gamma)\) target;
- the Bessel-collapsed \(\gamma\) target;
- the variational \(q(\sigma,\gamma)\) factor;
- the ELBO.

Any current formula for the joint \((\sigma,\gamma)\) factor that contains only the GIG terms

\[
c_\gamma/\sigma+d_\gamma\sigma
\]

but lacks \(e_\gamma\) is incomplete as a function of \(\gamma\). This is a correctness issue, not merely a mixing improvement.

The same term in the \(u\)-parameterization is

\[
e_\gamma
=
\lambda_\gamma
\sum_i
\frac{
s_i(q_i-k_\gamma u_i)
}{
u_i
}.
\]

Codex should add explicit finite-difference and log-kernel decomposition tests for this term before changing the sampler.

---

# 12. Recommended numerical coordinate for \(\gamma\)

## 12.1 The map \(\gamma\mapsto p_\gamma\)

The internal \(p_\gamma\) is a monotone one-to-one function of \(\gamma\):

\[
\gamma\in(L,U)
\quad\longleftrightarrow\quad
p_\gamma\in(0,1).
\]

For \(\gamma>0\),

\[
p_\gamma=\frac{p_0}{g(\gamma)},
\]

which increases from \(p_0\) to \(1\).

For \(\gamma<0\),

\[
p_\gamma
=
1-\frac{1-p_0}{g(\gamma)},
\]

which increases from \(0\) to \(p_0\).

The original support for \(\gamma\) can be extremely asymmetric at extreme target quantiles. In contrast, \(p_\gamma\) always lies in \((0,1)\), and the key drift coefficient is simply

\[
k_\gamma=\frac12-p_\gamma.
\]

## 12.2 Logit coordinate

Define

\[
\eta
=
\operatorname{logit}(p_\gamma).
\]

This is an unconstrained scalar coordinate. It is useful for optimization, adaptive proposals, and slice sampling.

However, the original prior must be preserved. If the model specifies \(\pi_\gamma(\gamma)\), then the transformed target is

\[
\boxed{
\pi_\eta(\eta\mid\cdots)
\propto
\pi_\gamma(\gamma(\eta)\mid\cdots)
\left|
\frac{d\gamma}{d\eta}
\right|.
}
\]

Because

\[
\frac{dp}{d\eta}=p(1-p),
\]

\[
\left|
\frac{d\gamma}{d\eta}
\right|
=
\frac{p(1-p)}{dp/d\gamma}.
\]

The branch derivatives are

\[
\frac{dp}{d\gamma}
=
-\frac{p_0g'(\gamma)}{g(\gamma)^2},
\qquad \gamma>0,
\]

and

\[
\frac{dp}{d\gamma}
=
\frac{(1-p_0)g'(\gamma)}{g(\gamma)^2},
\qquad \gamma<0.
\]

Both are positive on the admissible support.

A uniform prior on \(\gamma\) does not become a uniform prior on \(p_\gamma\). Replacing one by the other would change the posterior and must be treated as a separate prior-sensitivity model.

## 12.3 Default scalar sampler

The recommended exact default is:

- evaluate the collapsed log density in \(\eta=\operatorname{logit}(p_\gamma)\);
- include the induced Jacobian;
- update \(\eta\) with one-dimensional slice sampling;
- map back to \(\gamma\).

This retains the exact posterior while avoiding the highly asymmetric raw \(\gamma\) interval.

A convergence-controlled adaptive quadrature/inverse-CDF draw can be implemented as a validation method and potentially as a production option. It can produce nearly independent conditional draws, but its numerical tolerance and tail truncation must be documented. Slice sampling remains the simplest exact MCMC default.

---

# 13. Optional exact interweaving parameterizations

These are secondary improvements. They should be implemented only after the collapsed block is validated.

## 13.1 Actual-standard-deviation scale

Define

\[
\omega
=
\sigma\sqrt{V_\gamma},
\]

where

\[
V_\gamma
=
B_\gamma+A_\gamma^2
+
\lambda_\gamma^2
\left(1-\frac{2}{\pi}\right).
\]

Then \(\omega\) is the marginal standard deviation of the GAL/exAL error.

The inverse transformation is

\[
\sigma=\frac{\omega}{\sqrt{V_\gamma}}.
\]

The exact transformed density must contain the Jacobian

\[
\left|
\frac{\partial\sigma}{\partial\omega}
\right|
=
\frac{1}{\sqrt{V_\gamma}}.
\]

Thus

\[
\pi(\omega,\gamma,\ldots\mid y)
=
\pi\left(
\sigma=\frac{\omega}{\sqrt{V_\gamma}},
\gamma,\ldots\mid y
\right)
\frac{1}{\sqrt{V_\gamma}}.
\]

A correct MH, slice, or interweaving refresh in \((\omega,\gamma)\) targets the same posterior. Its role is to align the scale coordinate with the actual marginal dispersion and reduce posterior correlation. It is not needed to establish the GIG collapse and should not replace the original \(\sigma\) coordinate for the exact GIG draw.

A practical interweaving scheme is:

1. update \((\gamma,\sigma)\) with the collapsed-GIG block;
2. transform to \((\gamma,\omega)\);
3. perform one exact \(\gamma\) refresh conditional on \(\omega\);
4. transform back to \(\sigma\).

This may improve robustness in difficult cases, but its benefit must be measured after the main collapse is in place.

## 13.2 Integrating \(v_i\) out during a \(\gamma\) refresh

Conditional on \(s_i\), integrating the exponential latent \(z_i\) or \(v_i\) returns an AL density:

\[
Y_i\mid s_i,\beta,\sigma,\gamma
\sim
\operatorname{AL}_{p_\gamma}
\left(
\mu_i+\sigma\lambda_\gamma s_i,\sigma
\right).
\]

Therefore

\[
\begin{aligned}
\log\pi(\gamma\mid\sigma,s,\beta,y)
={}&
\log\pi_\gamma(\gamma)
+
n\log\{p_\gamma(1-p_\gamma)\}
-n\log\sigma\\
&-
\frac{1}{\sigma}
\sum_i
\rho_{p_\gamma}
\left(
y_i-\mu_i-\sigma\lambda_\gamma s_i
\right)
+\text{constant}.
\end{aligned}
\]

This is an exact \(v\)-collapsed refresh. To preserve the full joint target, the update order must be valid:

1. update \(\gamma\) with \(v\) integrated out;
2. redraw all \(v_i\) or \(u_i\) under the new \(\gamma\);
3. only then perform later steps that condition on those latents.

This refresh can reduce overconditioning on the observation-specific exponential latents. It does not by itself remove the \(\sigma\)-\(\gamma\) ridge, so it is optional relative to the main scale collapse.

---

# 14. Recommended production MCMC algorithm

The following is the preferred algorithm for a single exAL block. It applies to static exAL regression, Q-DESN conditional on fixed reservoir features, and more general models after replacing \(\mu_i\) by the current conditional location.

## Algorithm: \(u\)-augmented, \(\sigma\)-collapsed exAL MCMC

**State:**

\[
(\beta,\text{shrinkage parameters},\sigma,\gamma,u_{1:n},s_{1:n}).
\]

### Step 1: evaluate GAL functions

From the current \(\gamma\), compute stably

\[
p_\gamma,\quad
A_\gamma,\quad
B_\gamma,\quad
\lambda_\gamma,\quad
k_\gamma=\frac12-p_\gamma.
\]

### Step 2: update \(u_i\)

For each \(i\),

\[
u_i
\sim
\operatorname{GIG}
\left(
\frac12,\;
\frac{(q_i-\sigma\lambda_\gamma s_i)^2}{\sigma},\;
\frac{1}{4\sigma}
\right).
\]

### Step 3: update \(s_i\)

For each \(i\),

\[
s_i\sim N^+(m_{s_i},V_{s_i}),
\]

with \(m_{s_i}\) and \(V_{s_i}\) from Section 7.2.

### Step 4: update the readout

Update \(\beta\) from its Gaussian conditional using

\[
y_i^\star
=
y_i-\sigma\lambda_\gamma s_i-k_\gamma u_i,
\qquad
\operatorname{Var}(y_i^\star\mid\beta,\ldots)=\sigma u_i.
\]

### Step 5: update ridge/RHS scales

Use the current closed-form updates. The exAL transformation does not change this block.

### Step 6: compute collapsed sufficient summaries

Compute

\[
S_{q^2/u},\;
S_q,\;
S_u,\;
S_{sq/u},\;
S_s,\;
S_{s^2/u}.
\]

### Step 7: update \(\gamma\), integrating out \(\sigma\)

Evaluate the Bessel-collapsed log target using the summaries. Prefer the \(\eta=\operatorname{logit}(p_\gamma)\) coordinate with the exact Jacobian. Use one-dimensional slice sampling.

### Step 8: update \(\sigma\) exactly

At the newly drawn \(\gamma\), compute \(c_\gamma,d_\gamma,e_\gamma\) and draw

\[
\sigma\sim\operatorname{GIG}(\nu,c_\gamma,d_\gamma).
\]

Use the inverse-gamma limit when \(d_\gamma\) is close to zero.

### Step 9: monitor

Store and diagnose at least

\[
\gamma,\quad
p_\gamma,\quad
\sigma,\quad
\omega=\sigma\sqrt{V_\gamma},\quad
\sigma\lambda_\gamma,
\]

along with readout summaries, ESS, and posterior predictive diagnostics.

## Why this is the recommended implementation

- It preserves the exact model and posterior.
- It removes the current \(\sigma\) value from the \(\gamma\) transition.
- It keeps \(\sigma\) in an exact GIG family.
- It simplifies all observation variances to \(\sigma u_i\).
- It reduces each collapsed \(\gamma\)-density evaluation to \(O(1)\) after sufficient-statistic computation.
- It integrates cleanly with the existing Gaussian readout and RHS updates.
- It can be validated against the existing \(v\)-sampler without changing the scientific model.

---

# 15. Structured variational Bayes replacement for the exAL block

MCMC remains the gold-standard posterior reference. Variational Bayes remains an approximation to the same posterior. The proposed improvement is to make the \((\sigma,\gamma)\) coordinate update exact within the selected variational factorization, rather than applying a two-dimensional Gaussian Laplace approximation to it.

## 15.1 Variational family

Under the \(u\)-augmentation, use

\[
q(\beta,\sigma,\gamma,u,s,\ldots)
=
q_\beta(\beta)
q_{\sigma,\gamma}(\sigma,\gamma)
\prod_i q_{u_i}(u_i)
\prod_i q_{s_i}(s_i)
\times
q_{\text{shrinkage}}.
\]

The scientific likelihood and prior are unchanged.

## 15.2 Exact coordinate form for \(q_{\sigma,\gamma}\)

Let

\[
\bar q_i
=
E_q[y_i-\mu_i],
\]

\[
\overline{q_i^2}
=
E_q[(y_i-\mu_i)^2].
\]

For a Gaussian readout,

\[
\bar q_i
=
y_i-x_i^\top m_\beta,
\]

\[
\overline{q_i^2}
=
(y_i-x_i^\top m_\beta)^2
+
x_i^\top V_\beta x_i.
\]

Let

\[
m_{u_i}=E(u_i),
\qquad
m_{u_i}^{(-1)}=E(u_i^{-1}),
\]

\[
m_{s_i}=E(s_i),
\qquad
m_{s_i}^{(2)}=E(s_i^2).
\]

Define

\[
\boxed{
\bar c_\gamma
=
2b_\sigma
+
\sum_i
\left[
\overline{q_i^2}\,m_{u_i}^{(-1)}
-
(1-2p_\gamma)\bar q_i
+
\frac14m_{u_i}
\right],
}
\]

\[
\boxed{
\bar d_\gamma
=
\lambda_\gamma^2
\sum_i
m_{s_i}^{(2)}
m_{u_i}^{(-1)},
}
\]

and

\[
\boxed{
\bar e_\gamma
=
\lambda_\gamma
\sum_i
m_{s_i}
\left[
\bar q_i m_{u_i}^{(-1)}
-k_\gamma
\right].
}
\]

Then the exact CAVI coordinate factor has kernel

\[
\boxed{
\begin{aligned}
q_{\sigma,\gamma}^\star(\sigma,\gamma)
\propto{}&
\pi_\gamma(\gamma)
\left\{
\frac{p_\gamma(1-p_\gamma)}{2}
\right\}^{n}
e^{\bar e_\gamma}\\
&\times
\sigma^{\nu-1}
\exp\left[
-\frac12
\left(
\frac{\bar c_\gamma}{\sigma}
+
\bar d_\gamma\sigma
\right)
\right].
\end{aligned}
}
\]

Therefore

\[
\boxed{
q^\star(\sigma\mid\gamma)
=
\operatorname{GIG}
(\nu,\bar c_\gamma,\bar d_\gamma)
}
\]

and

\[
\boxed{
\begin{aligned}
q^\star(\gamma)
\propto{}&
\pi_\gamma(\gamma)
\left\{
\frac{p_\gamma(1-p_\gamma)}{2}
\right\}^{n}
e^{\bar e_\gamma}\\
&\times
2
\left(
\frac{\bar c_\gamma}{\bar d_\gamma}
\right)^{\nu/2}
K_\nu
\left(
\sqrt{\bar c_\gamma\bar d_\gamma}
\right).
\end{aligned}
}
\]

The scalar \(q^\star(\gamma)\) can be normalized by adaptive quadrature. This avoids approximating it as Gaussian.

## 15.3 Exact conditional moments

For \(r\in\mathbb R\),

\[
E(\sigma^r\mid\gamma)
=
\left(
\frac{\bar c_\gamma}{\bar d_\gamma}
\right)^{r/2}
\frac{
K_{\nu+r}
\left(
\sqrt{\bar c_\gamma\bar d_\gamma}
\right)
}{
K_\nu
\left(
\sqrt{\bar c_\gamma\bar d_\gamma}
\right)
}.
\]

Thus every required moment can be reduced to one-dimensional integration over \(\gamma\):

\[
E_q\{h(\sigma,\gamma)\}
=
\int
q^\star(\gamma)
E\{h(\sigma,\gamma)\mid\gamma\}
\,d\gamma.
\]

This can supply

\[
E(\sigma),\quad
E(\sigma^{-1}),\quad
E\{\lambda_\gamma\},\quad
E\{\sigma\lambda_\gamma^2\},\quad
E\{1/(\sigma B_\gamma)\},
\]

and all other moments needed by the conjugate factors.

## 15.4 Interpretation

This is still variational Bayes and therefore does not equal the full posterior. However:

- it approximates the same original GAL/exAL posterior;
- it introduces no new likelihood or prior;
- the \((\sigma,\gamma)\) coordinate update is exact within the chosen mean-field/block factorization, up to numerical quadrature;
- it retains non-Gaussian shape and dependence within \(q_{\sigma,\gamma}\);
- it removes the Delta-method approximation for exAL moments;
- it should be validated against the new exact MCMC sampler.

This structured factor should replace, or at least become the preferred alternative to, the current two-dimensional Laplace–Delta exAL block.

---

# 16. What “fully conjugate” can and cannot mean here

The original quantile-fixed GAL/exAL model ties together two parent-GAL shape mechanisms through the nonlinear quantile-fixing map involving

\[
g(\gamma)
=
2\Phi(-|\gamma|)e^{\gamma^2/2}.
\]

Consequently, the \(\gamma\) conditional is a curved, nonstandard one-dimensional density. The proposed \(u\)-augmentation and scale collapse do not turn \(\gamma\) into a Normal, Gamma, Beta, or GIG random variable.

What they achieve is the strongest currently justified exact simplification:

- all local latents remain in named families;
- the readout remains Gaussian;
- \(\sigma\mid\gamma\) is GIG;
- \(\gamma\) is one-dimensional after \(\sigma\) is integrated out;
- the principal \(\sigma\)-\(\gamma\) ridge is removed from the transition;
- the scalar target can be sampled robustly without a joint random walk.

A custom “conjugate” prior for \(\gamma\) could be written formally by placing prior mass in the same sufficient-statistic functions appearing in its complete-data kernel. Its normalizing constant would still involve a nonstandard integral over \((L,U)\), so it would not produce a standard direct sampler. It would not solve the computational problem.

The earlier parent-GAL proposal that makes the internal AL probability and skew displacement independent can produce more named full conditionals, but it changes the model family and posterior. It is not an exact reparameterization of the quantile-fixed three-parameter GAL/exAL and is excluded from the present implementation.

---

# 17. Applicability to the current model family

## 17.1 Static exAL regression

Set

\[
\mu_i=x_i^\top\beta.
\]

All formulas apply directly.

## 17.2 Q-DESN

Conditional on the fixed reservoir feature matrix,

\[
\mu_t=x_t^\top\beta.
\]

The exAL block is a fixed-design regression block. The reservoir construction and regularized-horseshoe hierarchy do not change.

## 17.3 Joint or multivariate Q-DESN with separate exAL margins

For series-specific parameters \((\sigma_j,\gamma_j)\), apply the block independently to all observations assigned to series \(j\). If a common \((\sigma,\gamma)\) is shared across several rows or sources, aggregate their sufficient statistics in the same formulas.

## 17.4 Dynamic quantile models

Conditional on the current latent state path, replace \(\mu_i\) by the current dynamic location. The exAL likelihood algebra is unchanged. Whether the full state update remains Gaussian depends on the surrounding state-space specification, but the \((u,s,\sigma,\gamma)\) block remains valid.

## 17.5 Censored/Tobit models

After augmenting censored responses with their latent continuous values, apply the same exAL updates to the augmented responses, exactly as the original GAL article applies its hierarchy after the censoring augmentation.

---

# 18. Numerical implementation requirements

## 18.1 Stable evaluation of \(g(\gamma)\)

Compute

\[
\log g(\gamma)
=
\log 2
+
\log\Phi(-|\gamma|)
+
\frac{\gamma^2}{2}
\]

using a stable log-CDF routine. Direct evaluation of

\[
2\Phi(-|\gamma|)e^{\gamma^2/2}
\]

can underflow or overflow near the support boundaries.

## 18.2 Stable \(p_\gamma\), \(A_\gamma\), \(B_\gamma\), and \(\lambda_\gamma\)

Use branch-specific formulas and stable `log1p` operations near \(p=0\) or \(p=1\). Avoid subtracting nearly equal floating-point numbers when computing \(1-p\).

## 18.3 Stable Bessel expression

Evaluate

\[
\log K_\nu(x)
\]

with a scaled Bessel routine when possible. Use

\[
K_{-\nu}(x)=K_\nu(x).
\]

The collapsed log integral is

\[
\log 2
+
\frac{\nu}{2}
(\log c-\log d)
+
\log K_\nu(\sqrt{cd}).
\]

Use the inverse-gamma limit near \(d=0\).

## 18.4 Boundary handling

Never evaluate exactly at \(p=0\) or \(p=1\), equivalently \(\gamma=L\) or \(\gamma=U\). Slice brackets and numerical transforms should respect open support.

## 18.5 GIG convention

The codebase must use one documented parameterization:

\[
f(x\mid\nu,\chi,\psi)
\propto
x^{\nu-1}
e^{-\frac12(\chi/x+\psi x)}.
\]

Unit tests must verify the argument order passed to every library routine.

---

# 19. Required correctness tests

## 19.1 Change-of-variable identity

For random valid values of all quantities, set

\[
u_i=B_\gamma v_i.
\]

Check numerically that

\[
\log p_u(y,u,s,\vartheta)
=
\log p_v(y,v,s,\vartheta)
-
n\log B_\gamma
\]

up to floating-point error, because

\[
\prod_i\left|\frac{dv_i}{du_i}\right|
=
B_\gamma^{-n}.
\]

## 19.2 Marginal GAL density identity

For a location-only toy model, numerically integrate the \(u,s\) hierarchy and compare it with

- the original \(v,s\) hierarchy;
- the published closed-form GAL density;
- Monte Carlo density estimates.

## 19.3 GIG kernel identity

For fixed \(\gamma\), verify that

\[
\log\pi(\sigma\mid\gamma,\ldots)
-
\left[
(\nu-1)\log\sigma
-\frac12(c_\gamma/\sigma+d_\gamma\sigma)
\right]
\]

is constant in \(\sigma\).

## 19.4 Cross-term identity

Verify that

\[
\log\pi(\sigma,\gamma\mid\ldots)
-
\left[
\log\pi_\gamma(\gamma)
+n\log\{p_\gamma(1-p_\gamma)/2\}
+e_\gamma
+(\nu-1)\log\sigma
-\frac12(c_\gamma/\sigma+d_\gamma\sigma)
\right]
\]

is constant in both \(\sigma\) and \(\gamma\).

This test should fail if \(e_\gamma\) is omitted.

## 19.5 Bessel-collapse identity

For selected \(\gamma\) values, compare

\[
\int_0^\infty
\pi(\sigma,\gamma\mid\ldots)\,d\sigma
\]

computed by direct high-accuracy quadrature with the Bessel formula.

## 19.6 Continuity at \(\gamma=0\)

Check that

- \(\lambda_\gamma\to0\);
- \(d_\gamma\to0\);
- \(e_\gamma\to0\);
- the Bessel expression approaches the inverse-gamma limit;
- the likelihood approaches the AL likelihood at \(p_0\).

## 19.7 Posterior invariance

On small toy data, compare long runs of

1. the existing \(v\)-sampler;
2. the existing-\(v\) sampler with collapsed \((\gamma,\sigma)\);
3. the \(u\)-augmented collapsed sampler.

Posterior means, quantiles, and predictive distributions must agree within Monte Carlo error.

## 19.8 Mixing comparison

Report

- bulk and tail ESS;
- ESS per second;
- lag autocorrelations;
- rank-normalized \(\widehat R\);
- posterior correlation of \((\gamma,\sigma)\);
- posterior correlation of \((\gamma,\omega)\);
- slice evaluations per effective draw.

A high posterior correlation after collapsing is not a failure. The relevant question is whether the chain explores that correlated target efficiently.

## 19.9 Extreme-quantile stress tests

At minimum test

\[
p_0\in\{0.05,0.5,0.95\}
\]

with \(\gamma\) near zero and near each support boundary.

## 19.10 VB validation

Compare

1. exact MCMC;
2. current VB–LD;
3. structured Bessel/GIG VB.

Assess readout means and variances, \((\sigma,\gamma)\) marginals, predictive quantiles, ELBO behavior, and runtime.

---

# 20. Implementation roadmap

## Phase 0: correctness audit

1. Centralize the functions
   \[
   g,\ p_\gamma,\ A_\gamma,\ B_\gamma,\ C_\gamma,\ \lambda_\gamma,\ k_\gamma.
   \]
2. Add branch and boundary tests.
3. Audit every \(\gamma\) target for the cross-term \(e_\gamma\).
4. Document the GIG convention.
5. Establish toy reference values from direct numerical integration.

## Phase 1: minimal-change exact scale collapse

Keep the current \(v_i\) augmentation and implement

\[
\gamma\mid\cdots_{-\sigma}
\]

with the \(v\)-based Bessel formula, followed by

\[
\sigma\mid\gamma,\cdots
\sim\operatorname{GIG}.
\]

This isolates the effect of collapsing \(\sigma\) without changing local latent coordinates.

## Phase 2: preferred \(u_i=B_\gamma v_i\) augmentation

Implement the \(u\)-based

- GIG latent update;
- truncated-Normal \(s_i\) update;
- Gaussian readout update;
- collapsed \(\gamma\) target;
- GIG \(\sigma\) draw;
- posterior predictive simulation.

Validate posterior equivalence against Phase 1.

## Phase 3: \(p_\gamma\)/logit coordinate

Add the exact induced Jacobian and use the logit-\(p_\gamma\) coordinate for the collapsed scalar update. Compare raw-\(\gamma\) and logit-\(p\) slice efficiency.

## Phase 4: structured VB

Replace the two-dimensional exAL Laplace–Delta factor by

\[
q(\gamma)q(\sigma\mid\gamma)
\]

with one-dimensional quadrature and exact GIG moments. Keep MCMC as the gold-standard reference.

## Phase 5: optional interweaving

Only if residual mixing problems remain, add

- the actual-standard-deviation \(\omega\) refresh;
- the \(v\)-collapsed \(\gamma\) refresh.

Each must have a separate invariance test.

---

# 21. Acceptance criteria for the new default

The \(u\)-augmented collapsed sampler may become the default only when all of the following hold:

1. posterior summaries agree with the existing sampler within Monte Carlo error;
2. posterior predictive draws agree;
3. direct quadrature confirms the collapsed scalar target on toy cases;
4. continuity at \(\gamma=0\) is numerically stable;
5. extreme-quantile support boundaries are handled correctly;
6. the cross-term audit passes;
7. ESS per second for \(\gamma\) and \(\sigma\) improves materially or is at least no worse;
8. no change is made to the scientific likelihood, priors, quantile anchor, reservoir design, or shrinkage hierarchy;
9. structured VB is validated against the new MCMC reference before it is used as a default approximation.

---

# 22. Compact directive for Codex

Implement an exact posterior-preserving improvement of the current quantile-fixed GAL/exAL scale–shape block.

1. Preserve the original \(p_0\)-anchored GAL/exAL likelihood and the original priors on \(\sigma\) and \(\gamma\).
2. First add a minimal-change \(\sigma\)-collapsed \(\gamma\) update under the existing \(v_i=\sigma z_i\) augmentation.
3. Include the \(\gamma\)-dependent cross-term
   \[
   e_\gamma^{(v)}
   =
   \sum_i
   \lambda_\gamma s_i
   (y_i-\mu_i-A_\gamma v_i)/(B_\gamma v_i).
   \]
4. Then add the preferred exact latent transformation
   \[
   u_i=B_\gamma v_i,
   \]
   including its Jacobian-induced exponential density.
5. Use
   \[
   k_\gamma=A_\gamma/B_\gamma=1/2-p_\gamma
   \]
   and
   \[
   k_\gamma^2+p_\gamma(1-p_\gamma)=1/4
   \]
   to simplify the local and global updates.
6. Update \(\gamma\) from the exact one-dimensional Bessel-collapsed density obtained by integrating out \(\sigma\), preferably in the \(\operatorname{logit}(p_\gamma)\) coordinate with the exact Jacobian.
7. Draw \(\sigma\) from its exact GIG conditional at the newly sampled \(\gamma\).
8. Preserve all existing Gaussian readout and ridge/RHS updates.
9. Add density-equivalence, GIG-kernel, Bessel-integral, cross-term, \(\gamma=0\), posterior-invariance, and extreme-quantile tests.
10. After MCMC validation, implement the structured variational factor
    \[
    q(\gamma)q(\sigma\mid\gamma)
    \]
    using one-dimensional quadrature and exact GIG moments.
11. Do not implement the free parent-GAL/recentering model in this branch: it is not equivalent to the current quantile-fixed GAL/exAL posterior.

---

# 23. Final conceptual summary

The proposed solution is a sequence of exact computational transformations:

\[
\text{original GAL/exAL}
\]

\[
\Downarrow\quad
u_i=B_\gamma v_i
\quad\text{(one-to-one latent reparameterization)}
\]

\[
\text{same GAL/exAL likelihood and posterior}
\]

\[
\Downarrow\quad
\int \pi(\sigma,\gamma\mid\cdots)\,d\sigma
\quad\text{(exact marginalization)}
\]

\[
\text{one-dimensional collapsed }\gamma\text{ target}
\]

\[
\Downarrow\quad
\gamma\text{ draw},\ 
\sigma\mid\gamma\sim\operatorname{GIG}
\]

\[
\boxed{
\text{same full posterior, better block geometry, no joint random walk required}.
}
\]

The reparameterization \(u_i=B_\gamma v_i\) simplifies the conditional Gaussian model. The scale collapse removes the dominant \(\sigma\)-\(\gamma\) dependence from the transition. The \(p_\gamma\) coordinate regularizes the support. None of these changes alters the flexible quantile-fixed GAL/exAL family or its interpretation.

---

# Source basis

- Yan, Y., Zheng, X., and Kottas, A. *A New Family of Error Distributions for Bayesian Quantile Regression*. The article defines the quantile-fixed GAL family, its \(z_i,s_i\) mixture, the \(v_i=\sigma z_i\) augmentation, GIG scale update, and nonstandard \(\gamma\) update.
- Current Q-DESN article and theory notes. These use the same quantile-fixed GAL under the name exAL, with fixed DESN features, Gaussian readout updates, ridge or regularized-horseshoe priors, MCMC as the posterior reference, and a Laplace–Delta approximation for the existing nonconjugate \((\sigma,\gamma)\) variational block.
