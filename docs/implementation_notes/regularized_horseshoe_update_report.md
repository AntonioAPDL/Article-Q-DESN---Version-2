# Regularized Horseshoe Implementation Update Report

## A) Repo status
- Repo path: repository root.
- Branch: `main`
- Git status at report time:
  - modified: `main.tex`
  - modified: `refs.bib`
- Key RHS-relevant files audited: `main.tex`, `refs.bib`
- Reference anchor used for RHS claims: an external local checkout of
  `RHS---Implementations` available during the original audit, specifically
  its manuscript and validation report.

## B) What was changed and why
1. Updated article-level default prior framework from legacy `c^2` narrative to `rhs_ns` notation and construction.
   - Replaced slab notation by `\zeta^2` and made NS-style joint construction the default in the prior section.
   - Added explicit statement that PV is retained only as contextual legacy note.
2. Updated inference narrative and algorithms to match implementation-ready `rhs_ns` block structure.
   - MCMC algorithm now uses augmented global-local scale updates (`\lambda_j^2,\nu_j,\tau^2,\xi`) and optional `\zeta^2` update.
   - VB summary now separates closed-form conjugate updates from Laplace treatment of only `(\sigma,\gamma)`.
3. Updated appendix conditionals to remove legacy non-conjugate `(\vect\lambda,\tau,c^2)` kernel as the default.
   - Replaced by `rhs_ns`-aligned augmented updates plus optional conjugate `\zeta^2` block.
4. Notation table aligned to `rhs_ns` (`(\lambda_j,\tau,\zeta^2)`).
5. Removed unresolved inline draft comments and old conflicting prior text.

## C) Derivation / claim validation summary
- Validated against repo (3) anchor that:
  - conditional regularized Gaussian law for `\beta_j\mid\lambda_j,\tau,\zeta` is shared object;
  - NS/PV are conditionally related but not joint-prior equivalent;
  - NS-style construction preserves the ordinary global-local full-conditional block given `\beta`;
  - random `\zeta^2` with IG prior is conjugate under pseudo-data/product representation.
- Article updates were constrained to these validated claims; no unsupported equivalence claim was introduced.

## D) Citation / bibliography updates
- Added and wired citations for new RHS_NS-default exposition:
  - `PiironenVehtari2017RHS`
  - `NishimuraSuchard2023SSS`
  - `MakalicSchmidt2016SimpleSampler`
  - `Fan2025RHS`
- Added `bhattacharya-khare-pal` entry for completeness in RHS discussion context.
- Kept bibliography style consistent with existing project setup (`natbib` + `apalike` + `refs.bib`).
- Confirmed no duplicate key collisions after update.

## E) Compile / check status
Commands run in repo:
1. `pdflatex -interaction=nonstopmode -halt-on-error main.tex`
2. `bibtex main`
3. `pdflatex -interaction=nonstopmode -halt-on-error main.tex` (twice after bibtex)

Results:
- Final compile: success.
- Bib pass: success.
- Resolved environment issue: removed unavailable package `siunitx` from preamble.
- Remaining non-fatal warnings:
  - hyperref PDF-string warnings for math in section title containing `$H$`.

## F) Remaining uncertainties and next steps
- The paper still contains placeholder sections (simulation/data/discussion dashes) unrelated to RHS update scope.
- If desired, we can further standardize whether `\zeta` is fixed vs random in all experiments and make that explicit in the experimental protocol section.
- If this manuscript will be submitted, a light final pass to reduce hyperref title warnings (e.g., `\texorpdfstring`) is recommended.
