# Reviewer Reading Audit

This audit records a fresh-reader pass over `main.tex` and
`qdesn-supplement.tex` after the previous style revisions. The pass applies the
repository academic style profile, especially the anti-AI-prose rule that
revisions should add statistical specificity rather than only fluency.

## Reader-facing strengths

- The article now has a clear primary scope: Q-DESN is a Bayesian quantile
  readout for fixed deep ESN features, not a generic probabilistic forecasting
  framework.
- The abstract and introduction state the working-likelihood interpretation of
  exAL and qualify posterior uncertainty under misspecification.
- The DESN feature construction is explicitly deterministic after reservoir
  generation and washout.
- The simulation section reports the single-root design limitation and separates
  oracle-path RMSE from realized check loss.
- The supplement gives orientation paragraphs before major derivation sections,
  which keeps it from reading as an algebra-only appendix.

## Issues found in this pass

- The main article used `q(\Theta,\vect z)` for the variational family even
  though `\vect z_t` denotes exogenous covariates. A new reader could interpret
  the variational factorization as involving covariates rather than auxiliary
  latent variables.
- The Q-DESN likelihood display used `y_t\mid(\cdot)`, which is concise but
  underspecified for a first read of the model.
- The simulation architecture sentence used `m=50` for random readout features,
  while `m` had already been defined as the number of response lags. This was a
  notation conflict.
- The supplement title still described Q-DESN as "Quantile Deep Echo State
  Network" rather than the refocused article title, weakening
  article-supplement consistency.
- Algorithm text referred to storing draws after "burn-in and thinning" as if
  thinning were required rather than optional.
- Some exAL descriptions mentioned skewness and tail-shape flexibility but did
  not mention the mode, although the cited GAL and exAL construction is used because
  it relaxes more than only skewness.

## Edits planned

- Rename the variational factorization from `q(\Theta,\vect z)` to
  `q(\Theta,\vect a)` and identify `\vect a=(\vect v,\vect s)`.
- Replace the likelihood conditioning placeholder with the explicit variables
  in the model display.
- Remove the `m=50` simulation notation conflict by spelling out the number of
  random readout features without assigning it to `m`.
- Align the supplement title and abstract with the Bayesian quantile-readout
  framing.
- Make thinning optional in MCMC algorithm descriptions.
- Add "mode" to the exAL flexibility statements where appropriate.

## Residual issues to keep visible

- The manuscript remains a working draft because the planned climate or
  environmental application is not yet implemented.
- The simulation currently uses one reproducible dynamic root per family and
  quantile level. The limitation is stated, but reviewers may ask for repeated
  roots and multiple reservoir seeds.
- VB--LD is appropriately presented as a practical approximation rather than a
  new general variational method. Its approximation error still needs empirical
  checking against MCMC in selected fits.
