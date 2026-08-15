# Publication-Readiness Audit, 2026-05-20

## Scope

This audit reviews `main.tex`, `qdesn-supplement.tex`, and `refs.bib` for a
controlled manuscript polish pass. It follows `Academic_Writing_Style_Profile_v0.2.md`
and `AGENTS_academic_writing_snippet.md`: preserve technical meaning, keep claims
modest, separate model specification from computation, and avoid generic prose.

## Stage 0 Baseline

| Item | State |
| --- | --- |
| Worktree | `/data/jaguir26/local/src/Article-Q-DESN` |
| Branch | `application-ensemble-likelihood-redesign` |
| Upstream | `origin/application-ensemble-likelihood-redesign` |
| Baseline HEAD | `3cf6d04a2a192a996578d127e1774bc16bfad4b0` |
| Dirty state before audit | clean |
| Stashes | none reported |
| Main manuscript | `main.tex`, 1351 lines |
| Supplement | `qdesn-supplement.tex`, 1947 lines |

## A. Manuscript Map

| Location | Title or object | Role | Stability | Placement |
| --- | --- | --- | --- | --- |
| `main.tex:83` | Abstract | States problem, model, computation, and deferred validation protocol | Stable, with result-dependent final sentence | Main text |
| `main.tex:108` | Introduction | Motivates quantile forecasting, DESN features, exAL, shrinkage, and contribution | Stable | Main text |
| `main.tex:213` | Related Work | Positions Bayesian quantile regression, DQLM/exDQLM, ESNs, UQ, quantile ESNs, shrinkage, and synthesis | Stable | Main text |
| `main.tex:310` | Notation and Preliminaries | Defines notation, DESN, and exAL before model specification | Stable | Main text |
| `main.tex:354` | Notation table | Compact reference for recurring symbols | Stable | Main text |
| `main.tex:519` | Model Specification | Defines fixed-design Q--DESN likelihood and priors | Stable | Main text |
| `main.tex:687` | Posterior Inference | States posterior target and separates MCMC from VB | Stable | Main text |
| `main.tex:732` | MCMC algorithm | Reader-facing sampler summary | Stable | Main text |
| `main.tex:807` | Variational Bayes algorithm | Reader-facing variational update summary | Stable | Main text |
| `main.tex:827` | Posterior Prediction and Quantile Synthesis | Forecasting plus optional post hoc synthesis | Stable, synthesis optional | Main text |
| `main.tex:921` | Model Diagnostics and Reservoir Specification | Practitioner-facing reservoir tuning and diagnostic workflow | Stable | Main text |
| `main.tex:1008` | Reservoir selection table | Summarizes tuning components and diagnostic risks | Stable | Main text |
| `main.tex:1068` | Simulation Design | Result-free design and comparison protocol | Result-dependent outputs deferred | Main text |
| `main.tex:1138` | DGP table | Defines simulation mechanisms | Stable | Main text |
| `main.tex:1212` | Application: GloFAS Streamflow Forecast Calibration | Application protocol, no performance claims | Result-dependent outputs deferred | Main text |
| `main.tex:1339` | Discussion | Intentionally deferred | Result-dependent | Main text placeholder |
| `qdesn-supplement.tex:76` | Scope and Relation to the Main Article | Explains supplement boundary | Stable | Supplement |
| `qdesn-supplement.tex:148` | Distributional Conventions | AL/exAL conventions and constants | Stable | Supplement |
| `qdesn-supplement.tex:197` | DESN Feature Map and Static Readout | Technical feature-map details | Stable | Supplement |
| `qdesn-supplement.tex:244` | Q--DESN Likelihoods, Priors, and Posterior Targets | Complete-data targets | Stable | Supplement |
| `qdesn-supplement.tex:416` | MCMC Full Conditionals | Derivations for sampler blocks | Stable | Supplement |
| `qdesn-supplement.tex:627` | Variational Bayes and Laplace--Delta Updates | Derivations for VB and LD blocks | Stable | Supplement |
| `qdesn-supplement.tex:861` | ELBO Decomposition | ELBO terms and approximation status | Stable | Supplement |
| `qdesn-supplement.tex:1073` | Posterior Prediction and Quantile Synthesis | Forecasting and synthesis details | Stable | Supplement |
| `qdesn-supplement.tex:1115` | GloFAS Discrepancy-Calibration Model | Application derivations | Stable, result-free | Supplement |

## B. Issue Register

| File | Location | Type | Severity | Evidence | Proposed action | Risk | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `main.tex` | Abstract | Prose/computation | Recommended | "model-specific variational Bayes approximation based on Laplace and Delta-method approximations" | Tighten to "Laplace--Delta treatment of the non-conjugate scale-asymmetry block" | Low | Edit now |
| `main.tex` | Introduction roadmap | Result-dependent phrasing | Required | Roadmap says Discussion "summarizes limitations and future work" while discussion is intentionally deferred | Rephrase roadmap so it does not promise unavailable discussion content | Low | Edit now |
| `main.tex` | MCMC/VB algorithm captions | Caption style | Optional | Captions do not state that AL/ridge variants are obtained by omission | Add compact self-contained captions | Low | Edit now |
| `main.tex` | Forecasting section | Equation exposition/prose | Recommended | Forecasting paragraph repeats "working-likelihood" and can better distinguish teacher forcing from free-running paths | Tighten teacher-forcing/free-running language without changing equations | Low | Edit now |
| `main.tex` | Quantile synthesis | Main/supplement boundary | Recommended | Synthesis is optional and not used in current result design | Retain but sharpen optional/generic status and avoid implying empirical use | Low | Edit now |
| `main.tex` | Simulation design | Result-dependent text | Required | Numerical tables are deferred; protocol text is safe | Keep result-free; minor wording only | Low | Edit now |
| `main.tex` | Application | Prose/line length | Recommended | Some long sentences around draw-level prediction and GloFAS likelihood | Compact wording while preserving protocol and no-claims language | Low | Edit now |
| `qdesn-supplement.tex` | Abstract | Prose | Recommended | Long list separates CAVI and VB--LD as if they were distinct algorithms | Tighten: CAVI updates with the Laplace--Delta block | Low | Edit now |
| `qdesn-supplement.tex` | Roadmap table | Terminology | Recommended | "CAVI and Laplace--Delta approximations" | Align with main: "Variational Bayes and Laplace--Delta updates" | Low | Edit now |
| `qdesn-supplement.tex` | GloFAS supplement opening | Main/supplement boundary | Recommended | "planned streamflow application" can sound more tentative than main protocol | Keep result-free but align with "application model" phrasing | Low | Edit now |
| `main.tex`, `qdesn-supplement.tex` | Labels/equations | Technical stability | Required | Labels are stable and referenced | Preserve labels and equation numbering | Low | Do not change |
| `main.tex` | Discussion | Result-dependent | Required | Placeholder is intentional | Do not invent discussion text | Low | Defer |

## C. Claim-Evidence Ledger

| Claim | Location | Evidence/citation | Strength | Proposed wording |
| --- | --- | --- | --- | --- |
| Conditional quantiles are optimal under asymmetric piecewise-linear loss | Introduction | `KoenkerBassett1978`, `Koenker2005`, `Gneiting2011` | Supported | Keep |
| exAL is quantile-fixed GAL and AL is a special case | Introduction, exAL preliminaries | `yan2025new` | Supported | Keep and ensure GAL is defined once before shorthand |
| AL/exAL are working likelihoods, not necessarily data-generating laws | Introduction | `sriram2013theoretical`, `YangWangHe2016ALInference`, `JiLeeRabeHesketh2025ValidSE` | Supported | Keep |
| DESN features are fixed after construction and posterior uncertainty is conditional on the reservoir | Introduction, notation, model | ESN references and model definition | Supported by model setup | Keep |
| RHS gives adaptive shrinkage with closed-form scale updates under the product representation | Introduction, priors | `CarvalhoPolsonScott2010HS`, `PiironenVehtari2017RHS`, `NishimuraSuchard2023SSS`, `MakalicSchmidt2016SimpleSampler` | Supported | Keep |
| VB--LD approximates the same fixed-design posterior and is not a general VI claim | Introduction, inference | `barata2021_flex_quantile`, `wang2013nonconjugatevb` | Supported | Keep |
| Simulation numerical results are deferred until shared validation interfaces are final | Simulation | Project state, no final tables | Correct | Keep |
| GloFAS application makes no performance claims until audited outputs exist | Application | Project state | Correct | Keep |

## D. Notation Ledger

| Symbol | First use | Meaning | Status | Consistency issue |
| --- | --- | --- | --- | --- |
| \(y_t\), \(y_{t+h}\) | `main.tex:118`, table | Scalar response and future response | Scalar lower-case | None |
| \(\mathcal F_t\) | `main.tex:119` | Forecast-origin information | Sigma-field | None |
| \(Q_{t,h}(p_0)\), \(Q_p(y\mid\cdot)\) | `main.tex:124`, `main.tex:325` | Conditional quantile functional | Function notation | None |
| \(\vect u_t\) | `main.tex:341`, `main.tex:373` | Input vector of lags and covariates | Vector | None |
| \(\vect h_{t,d}\), \(\tilde{\vect h}_{t,d}\) | `main.tex:342` | Reservoir and reduced state | Vectors | None |
| \(\mat X\), \(\vect x_t\) | `main.tex:346` | Fixed readout design | Matrix/vector | None |
| \(\vect\beta\) | `main.tex:348` | Readout coefficients | Vector | None |
| \(\sigma,\gamma\) | `main.tex:350` | exAL scale and asymmetry | Scalars | None |
| \(\lambda(\gamma)\) | `main.tex:505` | exAL positive-shift coefficient | Scalar function | Supplement uses \(D_\gamma\); already explained |
| \(q^{\mathrm{ref}}\), \(q^{\mathrm{glo}}\) | `main.tex:1254` | Application quantile readout locations | Scalar paths | None |
| \(\RHS\), `rhs_ns` | `main.tex:600`, supplement | Readout prior and product representation | Prior notation/code name | Keep `rhs_ns` in supplement only |

## E. Main-vs-Supplement Boundary Audit

| Material | Main text status | Supplement status | Placement judgment | Action |
| --- | --- | --- | --- | --- |
| DESN recursion | Core recursion in main | Detailed static readout derivation in supplement | Correct | Keep |
| exAL definition | Core distribution and augmentation in main | Distributional constants and computational conventions in supplement | Correct | Keep |
| Complete-data posteriors | Mentioned in main | Full kernels in supplement | Correct | Keep |
| MCMC and VB algorithms | Reader-facing summaries in main | Full conditionals and factors in supplement | Correct | Keep |
| ELBO | Not expanded in main | Full decomposition in supplement | Correct | Keep |
| Quantile synthesis | Concept in main | Additional implementation detail in supplement | Correct because optional and generic | Keep, sharpen optional status |
| GloFAS latent-path application | Protocol in main | Derivations in supplement | Correct | Keep |

## F. Result-Dependent Text Audit

| Location | Current status | Decision |
| --- | --- | --- |
| `main.tex:100-102` | Abstract says simulation protocol will evaluate metrics once validation tables are finalized | Safe |
| `main.tex:1083-1087` | Simulation numerical tables deferred | Safe |
| `main.tex:1207-1210` | Simulation remains protocol statement until schema guards pass | Safe |
| `main.tex:1326-1336` | Application evaluation is planned and no performance claims are made | Safe |
| `main.tex:1339-1343` | Discussion intentionally deferred | Defer |

## Stage 2 Revision Plan

Safe to edit now:

1. Tighten abstract computation sentence.
2. Correct roadmap wording around the deferred discussion.
3. Improve algorithm captions and a few forecasting/application sentences.
4. Align supplement abstract and roadmap terminology with main text.
5. Preserve all section labels, equation labels, and citation keys.

Defer until final results:

1. Discussion content.
2. Simulation result interpretation and any table values.
3. Application performance claims and final comparison text.

Do not change:

1. Core model equations.
2. MCMC/VB derivations and full conditionals.
3. Existing labels unless compilation reveals a true problem.
4. The main section order, which already follows a conventional Bayesian methods arc.

No unresolved ambiguity blocks conservative edits.

## Stage 3 Implementation Notes

Implemented edits were limited to low-risk items from the audit:

1. The abstract now describes the VB approximation as a Laplace--Delta treatment
   of the non-conjugate scale-asymmetry block.
2. The introduction roadmap no longer promises a completed discussion before
   finalized simulation and application results exist.
3. The MCMC and VB algorithm captions now state how AL/ridge variants relate to
   the displayed exAL/RHS algorithms.
4. The posterior-prediction section now distinguishes teacher-forced historical
   reservoir construction from draw-specific multi-step forecasting.
5. The quantile-synthesis section now states that synthesis is optional and
   generic, not a fitted component of the Q--DESN likelihood.
6. The application section now more compactly states the latent forecast-window
   design, draw-level prediction object, shared GloFAS likelihood parameters,
   and deferred performance-claim status.
7. The supplement abstract and roadmap now use conventional variational Bayes
   terminology and describe the Laplace--Delta block as part of the VB treatment.

No equations, labels, citation keys, or result-dependent empirical claims were
changed.
