# Article clarity corrections

## Scope

This revision implements the eleven-comment editorial plan against main
`e63bce30ab8cf70b9c3fc3d1c56418502c955c38`. It changes exposition, notation,
table organization, local figure placement and the presentation checks needed
to preserve reproducibility. It does not change statistical models, scientific
contracts, selected specifications, forecast paths, scores or fitted objects.
No scientific jobs are launched or modified.

## Comment dispositions

| Comment | Correction |
|---|---|
| C01 | Preserve the already neutral abstract statement of the streamflow application's purpose; add no provisional finding. |
| C02 | Make multiplication explicit in the predictor dimension and use the defined covariate-lag symbol consistently in the active weather-lag display. |
| C03 | Remove the main isotonic-projection display. Define the ordered ordinates briefly with the scores and retain the complete transformation in the supplement. |
| C04 | Explain each posterior computation directly, without audit-response contrasts. Correct the missing backslash on the supplementary scale–shape kernel's psi symbol. |
| C05 | Remove the computation-map table, which mixed likelihood families with a multiquantile model structure; remove premature application-specific methods. |
| C06 | Replace the allocation table with compact main prose. Preserve chain, iteration, burn-in, thinning, scoring-subset and stopping information in the study-specific supplement. |
| C07 | Separate recursive response generation from primary MQ reporting. Feature the existing common-mean-predictor readout formula as Equation (4.1), without changing the forecast analysis. |
| C08 | Use observation times for simulated-series positions, preserving the original generating-time convention, discarded prefix, evaluation ranges and posterior-draw indices. |
| C09 | Keep the simulation figures within complete local discussions and bring supplementary diagnostic figures nearer their interpretation. Preserve every scientific graphic. |
| C10 | Redesign the generating-mechanisms table around the shared construction and genuine differences, retaining all eight mechanisms in the original order. |
| C11 | Define the local relationship between the fitting endpoint, forecast origin, future path, horizon and ensemble-member domain immediately before the GloFAS model. |

## Forecast interpretation

The primary multiquantile score calculation already multiplies a common
averaged future-feature matrix by the retained coefficient draws and adds
their matching intercept draws. Recursive response generation supplies that
matrix; it is not the same operation as evaluating the readout. The revision
does not impose this reporting convention on the independent simulation or
applications. Score intervals retain their documented fixed-mean-feature
interpretation. The separate recursive-feature sensitivity remains available.

## Reproducibility boundary

The existing general and GloFAS-specific editorial histories remain intact.
A separately named general-editorial successor records the approved source
and display changes; this revision is not a GloFAS-only receipt refresh.
Protected scientific inputs and outputs must remain byte-identical. Regression
tests retain the posterior, prior, scoring, raw-crossing, future-truth and
authority safeguards while replacing assertions tied to deleted displays.

The legacy Python 3.6 receipt entry point remains usable for read-only checks
by calling the explicitly versioned Python 3.11 successor. Its former write
mode refuses the general editorial record. Historical provenance values remain
unchanged; deterministic JSON serialization also reorders some existing keys.

## Validation

The coordinator independently repeated the focused checks using R 4.6.0 and
the existing Python 3.11 presentation environment with pytest and PyMuPDF.

| Check | Result |
|---|---|
| Combined Python presentation, nomenclature, authority and receipt tests | 127 passed; five PyMuPDF/SWIG deprecation warnings |
| Reader-focused regression | 115 checks; 24 mutation rejections |
| Statistical-language regression | 121 checks; 89 mutation rejections |
| Forecast-exposition regression | 27 checks; 57 mutation rejections |
| Supplementary mathematical identities | 32 checks |
| Independent editorial receipt | 14 mutation rejections |
| Independent calibration | 47 checks, including 31 mutation rejections |
| Bibliography/initialization and RHS global-shape regressions | Passed |
| Git-only integration publisher | 9/9 disposable-remote fixtures passed |
| Git-only Overleaf publisher | Disposable-remote fixtures passed |
| General-editorial successor and legacy read-only adapter | Passed |
| Scientific file exclusion | 1,158 tracked model, configuration, figure and tabular-data paths unchanged |
| Shared and presentation receipt semantic comparison | Only the two manuscript hashes, the named successor record and two approved display/generator hashes changed |
| Working-source manuscript proof | Clean final LaTeX/BibTeX logs; main 38 pages, supplement 105 pages |

The baseline documents had 39 and 103 pages. The main text is shorter and its
simulation figures no longer interrupt paragraphs. The supplement preserves
the removed computation allocations and groups diagnostic figures with their
discussion; their citation-to-figure delays decrease from eight to two pages.
The page counts describe the reviewed one-column submission layout, not a
journal page-limit certification. Equation (4.1), both revised simulation
tables and the changed figure boundaries were inspected in the rendered PDFs.

The checks do not constitute a new complete scientific-campaign execution.
No historical posterior draws were reconstructed or new model fits generated.
A clean build is neither scientific promotion nor journal-submission approval.
Overleaf remains a one-way article-only deployment from verified main through
the repository's guarded command-line Git workflow. Integration, isolated
source-bundle validation and remote readbacks are recorded in the coordinator's
publication receipt; no deployment is inferred from these source checks.
