# Phase161 split-RHS decision and gamma audit

Phase161 is a no-new-sampling decision layer over the independently replicated Phase160 results. It verifies the Phase160 manifest, summarizes chain-level gamma and sigma behavior, compares both candidates with Phase157b and with the current article rows, and freezes the promotion decision.

The decision rule is deliberately stricter than improvement over the immediately preceding experiment: an article replacement must also improve the current article-facing result. The nonlinear-reservoir candidate did not reproduce its Phase159 screening gain. The Student-t candidate improved over Phase157b, but its forecast MAE remained above the current article Joint exQDESN row. Consequently neither candidate is promoted.

Run with:

```bash
Rscript application/scripts/207_audit_joint_exqdesn_phase161_decision_gamma.R
```

The output contains source verification, the frozen decisions, current article comparators, posterior and chain parameter summaries, gamma-sigma correlations, provenance, and a SHA-256 manifest. This audit does not establish that exAL must outperform AL: the additional shape parameter changes the working likelihood and posterior target, while gamma-zero is only an AL-like reference under the documented latent-variable reduction.
