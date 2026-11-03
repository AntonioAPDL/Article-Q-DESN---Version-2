# Mathematical source provenance

The fixed old protocol is continuation_execution_20261031_2022PDT/regional_preparation/PROTOCOLS.json, SHA256720f7ba5ffb886866f807a4a7ae63c8a99acc56bf194688144dc5a19df022118. The original R154 reference and tiny Decimal oracle were read as source only. The new package does not import or execute those old modules and does not treat their limited-domain result as a full target oracle.

The exact installed CRAN exdqlm1.1.1 manifest identifies source tarball SHA2563f3ed643ded7602fd62357d7f62024ca9071e0096214456650ed2de79722443e. Only source text was inspected from the compressed source archive; no installed R code or scientific payload was evaluated. Archive member exdqlm/R/static_beta_prior.R has SHA2566f89caf7b25513be16159f6f044ee7d5b268ce06daa4043131f007827e9c0d68. The independent prior implementation follows .static_rhs_ns_elbo_vb and the inverse-gamma entropy identity without accepting its computed scalar.

| Original term | New independent component |
|---|---|
| beta horseshoe normal contribution | beta_horseshoe |
| beta slab normal contribution | beta_slab |
| lambda conditional on nu | lambda_given_nu |
| nu half inverse-gamma prior | nu_prior |
| tau conditional on xi | tau_given_xi |
| xi prior with original tau0 | xi_prior |
| zeta prior with original a_zeta/b_zeta | zeta_prior |
| lambda/nu/tau/xi/zeta entropy | hyperparameter_entropy |
| original unshrunk intercept precision | intercept_prior |

The explicit objective follows the unchanged original imported-factor semantics of W191 application/R/525_project_fullstate_consumer.R:r525_explicit_factor_elbo. The prior is independently expanded above; beta entropy is counted once in Hbeta. Original q(v) chi/psi/E_v/E_inv_v/E_log_v are consumed as fixed factors and never reconditioned. Gamma/digamma formulas are restricted to positive integer or half-integer shapes; unsupported domains fail closed.

This source derivation does not constitute numerical qualification or a rigorous complete objective error budget. The unsupported special-function rounding, target construction and all-seven-measure/both-RHS-start closure remain explicit held fields in results.

Layout evidence: unchanged W191 r179_hb_bridge_or_pilot.R SHA2561f1d3e500ec8310f1d9724b61bdd72273b36feff53ba903d9a63b3d3a694b1f3 line128 reads original X.bin with matrix(...,byrow=TRUE). LT design.json SHA2561374df1a43d457fd8f1e10595a70370c570f538488918dee3ec2cd51cc9def86 records dimensions and target identity but has no storage-order declaration. The new design convention preserves that original consumer semantics exactly. P/covariance inputs are separately declared new owned column-major exports and require their own byte/layout provenance; no claim of an original saved P/covariance layout is made.
