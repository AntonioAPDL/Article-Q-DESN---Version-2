# Forecasting and application exposition revision

## Scope and authority

This revision starts from freshly fetched main
`8b28ba51176c25624b638fac54fce2699b9af078`. It implements the bounded
current-method exposition work in the consolidated 31 October plan. It does
not change a fitted posterior, forecasting law, numerical result or scientific
authority. Clarification is distinct from the separately requested integrated
multistep-quantile analysis and GloFAS future-path law. The subsequent no-launch
instruction governs that scientific work.

Writing follows `Academic_Writing_Style_Profile_v0.2.md`: statistical objects
before computation, defined notation, compact display labels, substantive
transitions and no internal campaign terminology in manuscript prose.

## Implemented explanations

- The input definition now separates positive response lags from current and
  lagged exogenous covariates. Input, first-layer matrix and readout dimensions
  all use `d_u=m+q(m_z+1)`. The recurrent state retains information beyond the
  explicit input window.
- The main article gives an explicit draw-specific response recursion. A
  parameter draw stays fixed along its own generated history; future errors
  are fresh and predictors are updated after each response. MCMC and VB draw
  sources, Normal mean locations, and AL/exAL quantile locations are distinct.
- Predictive responses are separated from conditional locations evaluated
  along simulated histories. The current single-quantile metric construction,
  MQ grid-inverse-CDF law, primary averaged-feature scores and pathwise
  sensitivity retain their actual meanings. No new integration estimator is
  described as an executed article method.
- GloFAS starts from reference and product regressions, then introduces their
  two fixed DESNs. One main display collects locations, observation equations,
  coefficient priors, source priors and the actual Gaussian future-path prior.
  It refers to the earlier full product RHS hierarchy, not a different
  normalized conditional prior.
- Unknown future gauge values supply missing lags for both maps. The future
  discrepancy input uses the earlier ensemble center minus the candidate
  reference value; every member still contributes individually to the
  likelihood. The observed historical difference is not a third independent
  likelihood response.
- The issued ensemble updates coefficients and the latent path jointly.
  Reference and discrepancy coefficient blocks are coupled in the posterior.
  The current Gaussian path prior replaces future-reference quantile factors;
  the reported mean location is not relabeled a marginal predictive quantile.
- PriceFM is described as separately fitted univariate regional regressions,
  with one selected specification per region and fold-specific parameter fits.
  Historical own/neighbor inputs are distinguished from released future
  load/solar/wind forecasts. Current direct-horizon predictors and variational
  coefficient-mean forecasts are stated explicitly, including inverse response
  scaling to EUR/MWh. No unfinished recursive campaign is promoted.

The supplement retains exact derivations/settings and clarifies these same
quantities. It remains a standalone document: references to main-paper
equations are descriptive rather than unresolved external equation links.

## Captured-comment traceability

The original 115-row register
`docs/reproducibility/advisor_revision_resolution_20261029.csv` remains
unchanged. Its statuses are historical dispositions, not advisor acceptance.

| Relevant IDs | Exposition in this revision | Scientific closure |
| --- | --- | --- |
| M03, M10 | Lagged inputs, recurrent memory and uncertain future predictors | No model change |
| F01, E12 | Fitting endpoint, origin and retained parameter fit | Evaluation design unchanged |
| F02–F04, E18 | Response draws, conditional locations and reported uncertainty | No new forecast functional promoted |
| E28–E30, E35 | Actual response laws, oracle separation and MQ averaging | Existing results and disclosures retained |
| E36 | Genuine one-step input gap remains documented | Not closed |
| E37–E42 | Products, information set, regression-first model and two maps | Protected issued window and current target unchanged |
| E43–E47, C02 | Additive location, priors, individual members and latent-path law | Corrected numerical packet still required |
| E48, A03 | Historical-result notices and consistent authority retained | No result replacement |
| C06 | Existing approximation/timing qualification retained | Matched fit-only timings still unavailable |
| E51 and new author request | Narrowly reopened PriceFM exposition | No assertion of advisor approval or new scientific authority |

## Invariance and guard design

All existing scientific CSVs, figures, aliases, model/inference source files,
runtime payloads and frozen results must remain byte-identical. The current
GloFAS scientific checkout at
`60daab261d52eec0ae24060babe186d618303e2b` is not modified or relaunched.

The previous statistical-language guard prohibited all changes to provisional
PriceFM prose. The new author instruction reopens only the two identified
main/supplement text segments. A new SHA-256-pinned contract authorizes their
exact revised text; it does not authorize numerical/source/alias changes.
Absent that contract, the original unchanged-text restriction remains active.
Negative tests must reject stale/unpinned contracts and unauthorized text.

The new exposition regression is registered in the complete application test
harness without removing any existing registration. Existing brittle sentence
checks may change only to preserve the same statistical distinction under
the clearer wording; mutation rejection remains required.

## Verification and publication gates

Use pinned R 4.6.0 for the reader, statistical-language, new exposition and
source/projection checks. Run the combined registered harness and
`git diff --check`; retain actual logs and counts in the ignored continuation
record rather than infer a full-suite pass from focused checks.

Compile identified and anonymous main/supplement proofs with
`bash scripts/build_technometrics_review.sh`. Inspect the new input, recursion,
GloFAS and regional forecast displays and their semantic references. The
revision adds essential explanation; it is not a new compression claim.

Integrate the clean frozen source branch with `--no-ff` in a fresh coordinator
worktree, validate the combined tree and publish main through the guarded
command-line Git workflow. If an article review copy is authorized, preserve
all pending GloFAS notices and use the explicit `--review-draft` publisher.
No unfinished numerical results may be promoted by publishing revised prose.

## Remaining scientific work is not hidden implementation

After this exposition revision was prepared, the author requested integrated
simulation-forecast reconstruction and a GloFAS same-family future transition.
The author then explicitly prohibited launch and requested a three-host plan
for Hummingbird, Jerez and Muscat. These later scientific tasks are not
implemented or promoted by the current-method manuscript revision.

Their launch authorization remains closed. They require frozen forecast
functionals, target/source contracts, numerical accuracy and resource gates,
and any necessary manifest-verified transfers. The current PriceFM comparison
still requires its scientific lane's completed handoff before replacement.
No new production forecast reconstruction, posterior fit, Slurm allocation or
runtime transfer was launched here; ordinary software fixtures are separate.

## Pre-integration verification receipt

Under pinned R 4.6.0, the registered `application/tests/run_tests.R` completed
successfully with Python 3.11 and the existing isolated test dependencies.
Its existing discrepancy-fit-adapter skip remains explicit because that
optional engine is unavailable; this is not a claim that every external or
historical runtime test was executed. One plotting-range warning was nonfatal.

Focused checks passed: exposition 24 checks and 22 mutation rejections,
statistical language 81 and 38, reader revision 78 and 7, metadata refresh
13 mutation rejections, existing reporting authority 7 mutation rejections,
and current independent article authority 23 checks. All seven changed R
files parsed and `git diff --check` passed.

The full harness first exposed missing Python YAML support, then stale live
manuscript hashes in the independent-study article receipt. Both failed-run
logs are retained. The corrected run passed after selecting the existing test
environment and refreshing only the two current document digests with
explicit provenance. All 17 other source digests, 21 output digests, historical
receipts and numerical assets remain unchanged. The new metadata refresher
defaults to read-only checking and rejects broader changes.

The exact-source identified manuscripts compiled to 39 main and 101 supplement
pages; anonymous proofs compiled to 37 and 100 pages. Final logs were clean.
The new input, recursive forecast, GloFAS and regional forecast displays were
visually inspected. Successful proofs do not remove the pending scientific
gates or establish submission readiness.
