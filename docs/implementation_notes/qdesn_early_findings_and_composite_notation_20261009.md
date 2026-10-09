# Early findings placeholders and composite-posterior notation

Baseline: `fe45170be4b354c79035b89415f9b6eed15f8d86`.

This editorial revision replaces empirical conclusions preceding the results
with visible, neutral author placeholders. The abstract retains the methods
and purposes of the simulation, GloFAS, and PriceFM comparisons. The
introduction already states questions and methodological motivations rather
than current empirical findings. The supplementary scoring discussion now
defers the GloFAS ordering outcome to the application results.

The composite posterior is written in generalized-Bayes proportional form:
`pi_c(theta | y, X) ∝ exp{-ell_c(theta; y, X)} pi(theta)`, where
`ell_c = -log L_c` is the negative composite log-likelihood and the learning
rate remains one. This is exactly the previous likelihood-times-prior target,
with its normalizing constant suppressed. Every parameter-dependent density
normalizer remains within the loss; the exAL loss is not replaced by check
loss. The condition that the posterior normalizing constant be finite is
retained in the text.

No empirical result, prior, initialization, forecast, score, table, figure,
or scientific authority is changed. The main manuscript from the Simulation
Studies section onward and the supplement from its Supplementary Simulation
and Application Tables section onward must remain byte-identical to the
baseline. Placeholders are author-review markers and must be resolved before
journal submission; they do not imply that future results will improve.

Validation comprises the existing manuscript and scientific-projection
checks, the bounded supplementary mathematics test, dependency-inventory
verification, identified and anonymous manuscript builds, and a clean
article-only snapshot build. The regenerated dependency inventory records
the new manuscript hashes and shifted dependency locations. Publication
follows the existing guarded command-line Git integration and one-way Overleaf
snapshot workflow.

Source verification passed the 29-check supplementary mathematics test,
bibliography/initialization test, final-manuscript checker, 210-check joint
projection audit, 366-check independent v14 audit, R98 PriceFM projection
audit, and 104-file dependency inventory. The final-manuscript checker also
runs the GloFAS projection check. Both results-section suffix comparisons
passed. Identified main/supplement proofs remain 36/84 pages; anonymous proofs
remain 34/83 pages, with clean final logs. The abstract now contains 130 words.
These are bounded editorial and scientific-invariance checks, not a claim
that a full scientific fitting or repository-wide runtime suite was rerun.
