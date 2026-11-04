# Future-path inference: normalization, parameter uncertainty and qualification

This note specifies checks for the unchanged GloFAS target. The accompanying
examples use generated data and small probability models only. They do not
certify a replacement inference algorithm, change a model or article result,
or authorize an application run.

## 1. An exact no-new-information requirement

Let D denote the historical information and let psi collect all unknown
coefficients, scales, shape parameters and shrinkage quantities. Conditional
on psi, a causal future-reference law has density

\[
p(\boldsymbol y_F\mid\psi,D)
=\prod_{h=1}^H f\{y_{T+h}\mid
 x_{T+h}(y_{T+1:T+h-1},z),\psi,D\}.
\]

The features may be nonlinear and recurrent. The requirement is that the
hth conditional uses preceding responses, not its current or later response,
and that every conditional density is normalized. The supplied future
covariates are conditioned on, not estimated from protected future USGS.
Integrating first over the last response and then backward gives

\[
\int p(\boldsymbol y_F\mid\psi,D)\,d\boldsymbol y_F=1,
\qquad
\pi(\psi\mid D,G_F=\varnothing)=\pi(\psi\mid D).
\]

This identity also holds for normalized augmentations, integrating their
future local variables together with the responses. It does not depend on
Gaussian predictors, a conjugate parameter prior or a particular quantile.
Separate probability-level paths can each be integrated out under a joint
coefficient prior. Removing all future ensemble contributions must therefore
leave the exact historical parameter posterior unchanged.

With issued members present, parameter learning is legitimate. If their
ordinary-factor product is L_G(y_F,psi), define

\[
Z_G(\psi)=\int p(\boldsymbol y_F\mid\psi,D)
                  L_G(\boldsymbol y_F,\psi)\,d\boldsymbol y_F.
\]

Then the parameter posterior is proportional to pi(psi|D) Z_G(psi). Holding
the historical parameter posterior fixed without accounting for Z_G is not
automatically the same model. Conversely, the no-member identity is a
necessary reference check, not evidence that the actual issued members
should have no effect.

## 2. A joint future block is not necessarily sufficient

Write F for all future responses and augmentation variables. Without future
members, the exact joint target is pi(psi|D) p(F|psi,D). For any conditional
variational factor r(F|psi), the KL chain rule gives

\[
\operatorname{KL}\{q(\psi)r(F\mid\psi)\,\|\,
                  \pi(\psi\mid D)p(F\mid\psi,D)\}
=\operatorname{KL}\{q(\psi)\,\|\,\pi(\psi\mid D)\}
 +E_{q(\psi)}\operatorname{KL}\{r(F\mid\psi)\,\|\,p(F\mid\psi,D)\}.
\]

Choosing r=p cancels the future contribution, including its conditional
entropy, for every psi. In contrast, merely joining Y_F and v_F inside a
block r(F) independent of the coefficients and scales leaves a generally
parameter-dependent conditional KL. Optimizing that approximation can change
the parameter marginal even though no future data were observed. This is an
approximation consequence, not proof of an erroneous complete-data update.

An approximate conditional r(F|psi) does not automatically solve the problem:
its residual conditional KL can still depend on psi. With members present,
the exact conditional is proportional to p(F|psi,D)L_G(F,psi), with
normalizer Z_G(psi). A parameter update based on that conditional must account
for the normalization and conditional entropy; it is not obtained by simply
keeping the previous CAVI parameter formula.

## 3. Generated uncertain-parameter references

The implementation is
`scripts/diagnostics/glofas_future_information_reference.R`; its standalone
test is `application/tests/test_glofas_future_information_reference.R`.
Reference validity, iteration parity and exact-target accuracy are separate
fields. A successful software test deliberately retains approximation
failures.

### 3.1 Two uncertain coefficients and a variance parameter

For one or two future responses, use

\[
L\boldsymbol Y_F=X\boldsymbol\beta+\boldsymbol\varepsilon,
\qquad \boldsymbol\varepsilon\mid s\sim N(0,sI),\qquad
\boldsymbol\beta\sim N(m_0,V_0),\qquad s\sim\operatorname{IG}(a,b).
\]

L is lower triangular with unit diagonal and a fixed autoregressive
coefficient; X has two columns. Here s is a **Normal variance**. The exact
parameter marginal remains its prior. For a product approximation
q(beta)q(Y_F)q(s), let k=E_q(1/s). Its stationary covariance satisfies

\[
V_\beta=(V_0^{-1}+kX^\top X)^{-1},\qquad
V_Y=k^{-1}L^{-1}L^{-\top},\qquad
bk+\tfrac12 k\operatorname{tr}(XV_\beta X^\top)=a.
\]

The parameter means remain m_0 in this generated linear example, but the
coefficient marginal is spuriously narrower. Allowing a full covariance
within q(Y_F) does not remove the missing dependence on beta and s. With a
fixed variance, the corresponding failure remains, with k=1/s.

The numerical reference independently integrates the Gamma precision
mixture after analytically retaining the Gaussian coefficient uncertainty.
It also integrates the one-/two-step transition densities directly in
response coordinates. The prototype's coordinate solution is compared with
the stationary matrix equations, not with an incorrect exact-posterior
answer. Its reported future quantiles are then compared with the exact
marginal CDF separately.

### 3.2 An uncertain intercept under AL

For one future response, take theta~N(m_0,V_0) and
Y|theta~AL_p(theta,sigma), with sigma fixed. In the Normal–Exponential
augmentation, define A_p=(1−2p)/{p(1−p)}, B_p=2/{p(1−p)} and
lambda=E_q(1/v). Under q(theta)q(Y)q(v),

\[
V_\theta=(V_0^{-1}+\lambda/(B_p\sigma))^{-1},\qquad
\lambda+\lambda^2 V_\theta/(B_p\sigma)=2/\sigma.
\]

The exact theta marginal is still N(m_0,V_0), whereas the product
approximation changes its variance. The exact response CDF is an AL–Normal
convolution, not a fixed-location AL CDF. Independent split quadrature
evaluates that convolution. This adds parameter uncertainty to the earlier
fixed-parameter AL counterexample; it is not a second claim that the
application's complete error has been explained.

### 3.3 An uncertain AL scale

Now keep the intercept fixed, let sigma~IG(a,b), and retain one or two causal
AL future transitions with common scale sigma. Here sigma is an **AL scale**,
not a Normal variance. The exact sigma marginal remains IG(a,b).

Under the generated factorization q(sigma)q(Y_F)prod_h q(v_h), its stationary
moments satisfy

\[
E_q(1/\sigma)=a/b,\qquad E_q(1/v_h)=2a/b,
\]

but the variational scale factor is

\[
q(\sigma)=\operatorname{IG}\left(a+\tfrac32H,
                         b\,\frac{a+\tfrac32H}{a}\right).
\]

Thus the mean inverse scale can remain exactly right while the scale
distribution changes. For a=3 and b=2, the exact mean scale is 1; the
mean-field means are 6/7 for H=1 and 4/5 for H=2. The augmentation's
a+3H/2 conditional shape is correct. Replacing it with a smaller shape to
force marginal invariance would not be a valid repair of the joint target.
The issue is the factorization and its missing dependence.

For one response with fixed location zero, exact scale mixing gives

\[
F(y)=\begin{cases}
p\{b/[b-(1-p)y]\}^{a},&y<0,\\
1-(1-p)\{b/(b+py)\}^{a},&y\ge0.
\end{cases}
\]

Gamma-precision quadrature independently checks this CDF. The normalized
augmented AL conditional is also evaluated through two independent
representations: Normal×Exponential factors, and standard Normal/unit
Exponential variables with the full parameter-dependent transformation
Jacobian. Conditional future factors cancel pointwise only when conditioned
on **all** coefficients and the scale, not simply when Y_F and v_F are
placed in one parameter-independent block.

## 4. Coupled moments needed for coefficient, scale and RHS updates

For one AL augmented row, let z be the response, x its feature vector and
b the regression coefficients. Given the latent path, x is known, even
when it is a nonlinear function of earlier responses. The complete-data
Gaussian coefficient terms are

\[
Q_b=Q_{\rm prior}+\sum_i\frac{x_ix_i^\top}{B_p\sigma_i v_i},\qquad
h_b=h_{\rm prior}+\sum_i\frac{x_i(z_i-A_pv_i)}{B_p\sigma_i v_i}.
\]

When a variational coordinate permits averaging over other factors,
the required statistics include E[x_ix_i^T/(sigma_i v_i)] and
E[x_i z_i/(sigma_i v_i)], not products of marginal expectations unless the
stated factorization actually supplies that independence. If coefficients
are themselves coupled to the future block, these expressions describe
complete-data conditionals; they are not automatically the update of an
independent Gaussian q(b).

The complete-data AL source-scale conditional has shape a+3n/2 and rate

\[
b+\sum_i\left[v_i+
       \frac{(z_i-x_i^\top b-A_pv_i)^2}{2B_pv_i}\right].
\]

An independent variational scale coordinate uses the expectation of that
rate. Its expansion involves E[(z−x^T b)^2/v], E[z−x^T b] and E[v]. A future
block coupled to the coefficients, scale or local variables requires the
corresponding joint moments. The Normal variance conditional instead uses
a+n/2 and the expected squared residual; the two parameterizations must not
be interchanged.

Under exAL augmentation, replace the mean by
x^T b+A(gamma)v+sigma lambda(gamma)s. The coefficient statistics additionally
require joint moments involving x s lambda(gamma)/{B(gamma)v}; scale/shape
updates require their corresponding joint expectations and support mapping.
An AL fix does not qualify those exAL operations automatically.

RHS updates require unconditional coefficient second moments, or adjacent
coefficient-difference second moments in the multiquantile model. For a
structured coefficient factor conditional on F,

\[
E(bb^\top)=E_F\{\operatorname{Var}(b\mid F)\}
                    +E_F\{E(b\mid F)E(b\mid F)^\top\}.
\]

Dropping the second term's variation or the cross-level covariance changes
the shrinkage calculation. Retain the existing prior hierarchy and its
correct global conditional shape; no change to its hyperparameters is
implied by these diagnostics.

## 5. Route to qualify, and deadline decision

The cheapest immediate candidate is a **fixed-parameter reference**: retain
the genuine nonlinear feature map and all ordinary member factors, evaluate
the normalized future-path target, and compare exact small cases or
appropriately diagnosed conditional sampling with the current approximation.
This can identify approximation error without a refit. It is not a
replacement full-posterior forecast because it conditions away parameter
uncertainty.

A full-posterior candidate must preserve both future conditioning and
parameter uncertainty. A blocked sampler can retain Gaussian coefficient
full conditionals and the specified RHS hierarchy while updating the
nonlinear future path against its complete target; it still needs a valid
path transition, invariance tests, mixing/precision assessment and timing.
A conditional structured variational candidate needs a complete ELBO and
all coupled-moment/normalization derivatives. Neither is a drop-in use of
the existing independent Gaussian coefficient CAVI update.

Before a production pilot, require: the no-member parameter-invariance
reference, a small uncertain-parameter case with members, actual nonlinear
feature/target identity, relevant AL/exAL and MQ qualification, and a measured
deadline-feasible schedule. A merely joint future block that passes a
fixed-parameter test is not sufficient. No new GloFAS fit should start until
those gates pass. If they cannot pass before the submission deadline, retain
the audited adverse packet and report the unresolved inference question;
do not seek a favorable result by changing the prior or selecting a seed.

## Verification record

The numerical values and pass/fail counts are supplied by the generated test
receipt, not by an application fit. All software/reference passes must be
reported alongside the intentionally retained approximation-accuracy
failures. No original observations, retained model objects or protected
scoring values are used by this note's implementation.
