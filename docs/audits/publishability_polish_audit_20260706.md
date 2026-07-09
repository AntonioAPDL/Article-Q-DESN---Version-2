# Publishability Polish Audit

Date: 2026-07-06

## Scope

This audit records a manuscript polish pass on `main.tex` after the joint
quantile-vector readout subsection was added. The goal was to move the paper
toward a standalone article voice by removing internal repository labels from
visible prose while preserving the statistical claims, notation, tables, and
figures.

## Style Criteria Applied

- Use the academic writing profile's precise, restrained, statistically mature
  voice.
- Define statistical objects before using local shorthand.
- Separate model specification, computation, validation, and reproducibility.
- Avoid unsupported claims and avoid treating validation-screen outcomes as
  universal evidence.
- Replace lab-notebook labels with reader-facing descriptions.

## Main Findings

1. The abstract and simulation introduction exposed internal labels such as
   `TT500`, `DGP registry`, and validation-bundle language before a reader had
   enough context.
2. The joint multi-quantile validation section used operational terms such as
   bundle, manifest, launch directory, asset audit, and registry. These are
   useful for reproducibility notes but too repository-specific for the main
   article voice.
3. The GloFAS section used repeated phrases such as manuscript-facing run,
   audited reference case, and output-selection workflow. These were replaced
   with single-origin case-study language.
4. The PriceFM section exposed stage labels and internal selection terms such
   as Stage-M, Phase-I, registry, and rescue stages. These were replaced with
   selected-panel, released fold-aligned prediction, local reservoir-based
   forecast, and candidate-selection language.
5. The Discussion section was still a placeholder. A publishable draft needs a
   visible limitations and future-work discussion rather than an empty section.

## Implemented Corrections

- Rewrote the abstract and contribution paragraph to describe the simulation
  layers without internal names.
- Recast the simulation opening as two reader-facing validation layers:
  single-quantile dynamic recovery and joint multi-quantile synthetic forecast
  validation.
- Replaced repository artifact language in the joint multi-quantile section
  with reproducibility records, fixed seeds, source hashes, and generated
  table/figure hashes.
- Polished GloFAS prose into a single-origin calibration case study.
- Polished PriceFM prose into a selected-panel benchmark comparison with clear
  limitations.
- Removed the empty acknowledgments heading and added a substantive Discussion.
- Polished visible generated-table text by replacing internal specification
  identifiers, provenance notes, and stage-coded PriceFM rows with
  reader-facing labels.
- Retained file names, TeX labels, macro names, and generated table inputs where
  changing them would break the reproducibility wiring without improving the
  reader-facing article.

## Remaining Boundaries

- Internal names still appear in hidden TeX labels, file paths, and macros.
  These are not visible in the compiled article and were left unchanged.
- Generated-table source files still have internal file names and comments, but
  the rendered table labels and notes were rewritten for article readers.
- The PriceFM comparison remains a selected-panel analysis, and the GloFAS
  application remains a single-origin case study. The revised prose keeps those
  limitations explicit.
