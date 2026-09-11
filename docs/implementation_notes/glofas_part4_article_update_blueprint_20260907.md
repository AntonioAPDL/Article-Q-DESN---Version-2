# GloFAS Part 4 Article Update Blueprint

Date: 2026-09-07

Final closeout revision: 2026-09-11

## Final Closeout Status

The expensive scientific campaign is frozen. The original Part 4 DAG is
`18/18` complete with no failures, and the selected Joint AL continuation
completed ten total outer sweeps. It did **not** satisfy the strict outer
tolerance: its final maximum parameter change is `0.004153866`, versus the
predeclared `0.001` threshold. All inner quantile fits converged, however, and
all 14 reference/discrepancy RHS blocks passed the release audit, completed
five global-scale updates, and changed numerically after release.

The publication candidate is therefore classified as
`cap_stabilized_after_rhs_release`, never as strictly converged. This
classification is selection-eligible only under the explicit certificate in
`application/R/glofas_part4_publication_contract.R`. The article and
supplement must report the iteration cap and failed strict outer tolerance.
The source Joint exAL fit remains a nonconverged sensitivity result; its
optional continuation was operator-stopped and is not required for selection.

No additional Part 4 fit, sweep, forecast, or screening launch is required for
this closeout. The remaining work is deterministic packaging, verification,
integration, manuscript compilation, and publication.

## Purpose

This document defines the article-only integration step for the completed
GloFAS Part 4 latent-path ensemble-likelihood analysis. It is deliberately
separate from the scientific runtime. The Part 4 lane prepares versioned,
article-safe tables and figures; the Article Q-DESN integration lane applies
the manuscript edits, updates the current aliases atomically, compiles both
manuscripts, and publishes the article-only Overleaf snapshot.

The integration must not describe Part 4 as a post-fit forecast adapter. It is
one latent-path fit in which post-cutoff USGS values are unobserved variables
and the 51 issued GloFAS members contribute weighted likelihood rows.

## Authority Decision

The intended publication authority is the cap-stabilized Joint AL/RHS VB
Part 4 fit at outer sweep 10 on the seven-level grid

```text
0.05, 0.20, 0.35, 0.50, 0.65, 0.80, 0.95
```

This authority is scoped to the Part 4 issued-window experiment. FR09 remains
the stronger historical-fit benchmark and must remain preserved as versioned
evidence. The article must disclose that the Part 4 Joint AL model improves
the issued-window forecast scores substantially while its historical CRPS is
worse than FR09 on both each model's native grid and the common six-level
grid. It would be scientifically incorrect to present Part 4 as dominating
FR09 in both windows.

Normal Ridge has the lowest transformed-scale seven-quantile score among the
Part 4 diagnostic families, but its 90 percent interval severely undercovers
and it is not the quantile model targeted by the article. It remains a Normal
baseline. Joint AL is selected among the quantile models because it improves
on independent AL, attains near-nominal interval coverage, has no issued-grid
crossings, and directly implements the joint-quantile scientific target.

## Fixed Data And Evaluation Contract

| Item | Article statement |
| --- | --- |
| Historical cutoff and latent-path origin | `2022-12-25` |
| Requested horizon | 30 days, `2022-12-26` through `2023-01-24` |
| Issued/evaluable GloFAS horizon | 28 days, `2022-12-26` through `2023-01-22` |
| Issued ensemble size | 51 members at each retained horizon |
| Response scale | `log(USGS discharge + 1)` |
| Future USGS in fitting | Physically excluded as truth; represented as a latent missing path |
| Future USGS after fitting | Scoring-only sidecar |
| Future weather covariates | Realized PRISM/ERA5 PPT and soil; retrospective oracle diagnostic |
| CEFS/GEFS | Not used |
| Crossing correction | None |
| Separate forecast stage | None |
| Rolling origin | Not used |

The requested 30-day window and the 28 issued/evaluable days must both be
reported. The implementation does not pad or extrapolate GloFAS on days 29
and 30.

## Frozen Model Specification

| Component | DESN | Inputs | RHS `tau0` |
| --- | --- | --- | ---: |
| Reference | `D=1`, `n=3000`, `m=360`, `alpha=0.50`, `rho=0.90`, washout `500`, seed `20260512` | response lags `1:360`; realized PPT/soil lags `0:180`; no direct readout inputs | `1` |
| Discrepancy | `D=1`, `n=2500`, `m=360`, `alpha=0.80`, `rho=0.70`, washout `500`, seed `20261521` | discrepancy lags `1:360`; realized PPT/soil lags `0:180`; no direct readout inputs | `0.001` |

The Part 3 cross-input challenger was rejected because it worsened all primary
CRPS targets and increased reservoir saturation. It must not be described as
part of the selected Part 4 input contract.

## Required Main-Article Corrections

The existing GloFAS section in `main.tex` still describes the superseded FR09
persistence-adjustment workflow. Integration must rewrite that section rather
than only replacing its table and figure.

1. Replace the GEFS statement with the realized PRISM/ERA5 oracle-covariate
   statement. CEFS and GEFS were not used in this application.
2. Replace the persistence-anchored discrepancy description with the Part 4
   recursive latent-path ensemble-likelihood model.
3. State the historical equations on the transformed scale:

   ```text
   Y_t       ~ F_Y(q_t)
   G_retro_t ~ F_G(q_t + d_t)
   ```

   and the issued-member equation

   ```text
   G_ens_hj ~ F_G(q_(T+h) + d_(T+h)).
   ```

4. Explain that the unavailable future response path is inferred jointly and
   recursively supplies future response lags to the reference reservoir.
5. Explain that every issued member is retained but receives weight `1/51`
   within its horizon, so each horizon contributes total weight one.
6. Report Joint AL/RHS VB as the selected model. exAL remains a comparator;
   the article must not say that the reported fit uses exAL.
7. Replace the old `0.15` level by `0.20`.
8. Remove claims of monotone rearrangement. No crossing fix was applied; the
   selected issued quantile grid had zero crossings.
9. Replace the old FR09 score table and forecast figure with the versioned
   Part 4 article-safe assets from the publication manifest.
10. Add the historical guardrail result: the issued-window improvement comes
    with materially worse historical CRPS than FR09. Keep the interpretation
    scoped to this single retrospective origin.

## Required Supplement Corrections

The supplement already contains the general latent-path AL/exAL derivations.
Integration should align its application-specific prose with the executed
fit:

- identify the selected analysis as Joint AL/RHS VB;
- state that the source-weighted AL augmentation is a complete-data
  fractional/power-likelihood construction and not an asserted exact
  fractional marginal AL posterior;
- describe joint quantiles as mean-field quantile-block coordinate updates
  linked by adjacent-quantile RHS priors;
- report the exact outer-plus-inner convergence rule and its observed outcome.
  The inherited 50-iteration RHS global-scale warmup is
  converted to five joint outer sweeps because every outer sweep runs at
  least 10 inner coefficient iterations. The retained original joint fits
  completed those five warmup sweeps with zero global-scale updates. The
  closeout continuation therefore preserves its fitted state. Joint AL
  releases the global scale at outer sweep 6 and cannot be selection-eligible
  until at least one later sweep updates the coefficients under the released
  scale. Five post-release updates were completed. The strict outer tolerance
  was still not met at sweep 10, so the fit is a finite-cap estimate rather
  than a strictly converged optimum. The publication certificate must verify
  a nonzero coefficient change
  in every reference and discrepancy RHS block relative to the immutable
  pre-release source fit. The optional Joint exAL continuation was
  operator-stopped because it was materially slower and is not required for
  the selected result. The completed source Joint exAL fit remains an
  explicitly nonconverged, non-authoritative sensitivity result;
- state the `1/51` per-member horizon weighting;
- state the future-truth firewall and the 28-day issued limit;
- avoid implying that MCMC was run for the selected Part 4 application;
- avoid any claim of post-hoc crossing correction.

General MCMC derivations may remain as methodology, but the prose must
distinguish them from the executed VB application.

## Article-Safe Assets

The final publication builder creates only versioned outputs under `tables/`
and `figures/glofas_application/`. Its publication manifest must contain no
`local_trackers/` path. Expected products are:

- full seven-family forecast scoreboard in CSV;
- main three-row forecast table in TeX;
- native-grid historical guardrail in CSV;
- common-six-grid FR09/Part 4 tradeoff in CSV and TeX;
- joint convergence certificate in CSV;
- Sweep 5-to-10 path/score stability table and convergence-trace PDF;
- RHS schedule-conversion, release, and post-release response certificate;
- selected reference/discrepancy specification in CSV;
- proposed current-output macro registry in TeX;
- Joint AL last-30-plus-issued-28 figure in PDF;
- grouped Normal, independent-quantile, and joint-quantile comparison PDF;
- SHA256 publication manifest with separate Git-safe and Overleaf-publication
  flags. The reproduction script is tracked in Git but is not copied to the
  article-only Overleaf snapshot.

Runtime objects, posterior draw payloads, design caches, logs, status markers,
and runtime-local reports remain excluded from Git and Overleaf.

## Atomic Integration Order

1. Create an integration branch from the latest fetched `origin/main`.
2. Apply the Part 4 lane's unique commits in order. Do not blind-merge the
   scientific worktree because it has an older and criss-crossed base history.
3. Resolve `application/R/joint_exqdesn_exact_structured_inference.R`,
   `application/tests/run_tests.R`, and `application/tests/README.md` against
   current main deliberately. Preserve current main's RHS global-scale
   guidance and test registrations while adding the Part 4 observation-weight
   support and focused test registrations.
4. Run the Part 4 focused tests and publication-package checker.
5. Verify every article-safe asset against the publication manifest.
6. Replace `tables/glofas_application_current_outputs.tex`,
   `tables/glofas_application_current_score_summary.csv`,
   `tables/glofas_application_current_score_summary.tex`, and
   `tables/glofas_application_current_selection_manifest.csv` atomically from
   the reviewed Part 4 versioned assets.
7. Rewrite the GloFAS main and supplement prose using the corrections above.
8. Run `git diff --check`, the combined R/Python tests, and both LaTeX builds.
9. Inspect the rendered GloFAS table and figure pages for clipping, stale
   captions, scale labels, and score consistency.
10. Commit and push authoritative main using command-line Git, then publish
    only article-safe files to the Overleaf snapshot.

## Required Claims Discipline

Allowed:

- Part 4 Joint AL improves the 28-day issued-window transformed-scale CRPS,
  check loss, and interval score relative to raw GloFAS.
- Joint AL improves transformed-scale CRPS relative to independent AL for
  this origin.
- The selected interval has near-nominal empirical coverage for this origin.
- The analysis is a retrospective oracle-covariate diagnostic.
- The selected Joint AL estimate completed ten outer sweeps, all inner and RHS
  gates passed, and the strict outer tolerance was not met.

Not allowed:

- claiming operational real-time validity;
- claiming a 30-day scored GloFAS forecast when only 28 issued days exist;
- claiming historical superiority over FR09;
- claiming exact marginal fractional-AL inference;
- claiming MCMC application results;
- claiming monotone rearrangement or a crossing fix;
- claiming strict Joint AL outer convergence;
- claiming that Normal Ridge is the selected quantile model merely because
  its transformed-scale point estimate is numerically lower.
