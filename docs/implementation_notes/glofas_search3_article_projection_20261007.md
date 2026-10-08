# GloFAS Search III article projection

## Scope and fixed authority

The projection tag is `glofas_search3_part1234_final_20261007`. The builder
consumes the reviewed final-closeout authority explicitly; it never fits,
continues, forecasts, screens, calibrates, or selects a model. Its first action
is the independent final-closeout checker. All eleven gates, the frozen output
manifest, the six-page vector source, and the corrected terminal joint-fit
identities must pass before any staging output is generated.

The reference specification is `search3_ref_001` (retained incumbent); the
discrepancy specification is `search3_dis_007` (adopted rainy-season challenger).
These are internal-training decisions, not protected-window selections. The
Part 4 Independent AL ranking is descriptive. Corrected Joint AL and Joint exAL
are strictly converged comparators; their numerical status is not evidence of
adequate calibration.

## Builder, checker, and test

Run with the pinned project R installation and an explicitly supplied frozen
authority directory:

```sh
Rscript application/scripts/447_build_glofas_search3_article_projection.R \
  --runtime_root "$FROZEN_SOURCE" --output_root "$ARTICLE_ROOT"
Rscript application/scripts/448_check_glofas_search3_article_projection.R \
  --article_root "$ARTICLE_ROOT" --runtime_root "$FROZEN_SOURCE"
Rscript application/tests/test_glofas_search3_article_projection.R
```

The builder stages and independently checks every derivative before publishing
versioned assets or switching the four current aliases. Alias installation is
a rollback-protected transaction and must be committed as a single reviewed
authority switch. A failing stage leaves existing aliases untouched.

The checker is independent of the closeout scoring implementation. It recomputes
per-date check loss, trapezoidal grid aCRPS, central coverage, median errors, and
adjacent crossing counts from the public frozen quantile sources. It also
recomputes all 49 family-by-level calibration cells, raw-relative reductions,
TeX rounding, prior scale ranges, stable aliases, and relative-path hash/byte
closures. The scalar prior evidence distinguishes fixed hyperparameters from
learned posterior scales; posterior effective tau is exactly
`1/sqrt(posterior_inverse_tau2_mean)`.

## Publication surface

Versioned scientific CSV and display-only TeX derivatives are provided for
Parts 1–3 scores, seven-family Part 4 scores, calibration, selected specifications,
strict joint convergence, scientific authority, decision interpretation, and
executed prior settings. Public provenance includes supersession, original
source-role hashes, 3,892 frozen scoring quantiles, and 174 executed RHS scalar
rows. Full-precision CSV numbers use round-trip 17-digit representations;
rounding is confined to TeX display. No interval scores are imported or spliced.

The six single-page PDFs are named by their scientific roles: `part1`, `part2`,
`part3`, `part4`, `convergence`, and `calibration`, beneath
`figures/glofas_application/` using the projection tag. They preserve the vector
content and extracted text of the reviewed six-page source. The frozen source
canvas clips the last tick in the Part 4 joint panel. A temporary, same-byte-length
MediaBox expansion from 1,094 to 1,120 points restores already-present content
without altering data, curves, font objects, or the frozen original. Deterministic
pdfTeX extraction suppresses creation dates, trailer identifiers, and local
filename metadata. Every derivative has a 1,120-by-424-point canvas, one page,
embedded vector fonts, nonblank text, and zero embedded raster images.

The publication manifest records repository-relative paths, byte counts, SHA256,
source-role authority hashes, scientific publication roles, Git inclusion, and
Overleaf inclusion. It excludes itself to avoid a circular hash. The current
selection manifest reproduces the versioned asset and other-alias hashes; the
publication manifest additionally hashes that selection manifest. No runtime
paths, hostnames, sessions, logs, fit-object filenames, or completion markers
are exposed in these article assets.

## Boundaries retained

- Parts 1 and 3 have thirty scored recursive days; Part 4 has twenty-eight issued
  horizons and seven quantile levels. Their scopes are not pooled.
- All six Part 2 score rows retain missing scores and zero scored horizons. Its
  post-cutoff discrepancy path cannot be scored because retrospective GloFAS
  ends at the cutoff.
- Part 1 Independent AL retains three crossing pairs and Independent exAL one;
  no crossing correction is applied. All Part 3 families have zero pairs.
- Future USGS is scoring-only. The realized future covariates remain an oracle
  qualification, and the issued members enter the fitted latent-path experiment
  with weight `1/51`, not a post-fit forecasting stage.
- Parts 1–3 Ridge priors are taken from executed fits, not the selected-candidate
  screening row. The discrepancy slab is fixed at sixteen except Part 2 Normal
  RHS/VB, which learns it. Part 4 learns both component slabs in all RHS families;
  its executed tau0 rounding is reported separately from Search III calibration.

Before promotion, run the complete builder twice from unchanged authority and
compare the full publication-manifest hash, run the independent checker and
focused test, and compile both manuscripts and the clean source bundle. Those
integration-wide gates are recorded in the coordinator report, not inferred
from projection generation alone.

## Projection verification record

On 2026-10-07, two independent complete builder executions used the pinned R
installation and re-executed all eleven frozen-source gates before extracting
the full evidence. Both passed the staged and installed-output checkers. All
32 manifest-listed files, including all four current aliases and all six PDFs,
and the publication manifest itself were byte-identical. Both output snapshots
then passed an additional independent check against the frozen runtime with
zero-tolerance score, specification, and convergence comparisons. The standalone
macro and nine-table TeX smoke build and focused analytic unit test passed.

| Artifact | SHA256 |
|---|---|
| Publication manifest | `5a7ac4fc1b35f3e7b19c4535e5e5c1cc56c4dfe87927b42f6f66122d49a01335` |
| Current output macros | `57d8ac0430dd2174c700cc6657eb396b6460909f6b9f9055eb4d8f28a69da471` |
| Current score CSV | `c15d21cda11c8c8a89742b32b8a0c07b85851176dac29c30076941e32c52c998` |
| Current score TeX | `43604de723086dfa1e132715d8d14f624e400969dbe5b3b0ef6a949b8f74f183` |
| Current selection manifest | `25691eddb333d85dbc00de8ec33389d23796499343e0b01500778754e94f2c1c` |
| Frozen public quantile source | `d4a6c18eac599c66e9e95edda01e98d9f14c8f6a8efc6dd2a54f16544ae7181a` |
| Executed RHS prior scalars | `fc71014d3a39548e1c06d08fb6df116545745ae17f50abb8841a988267b6d8d5` |

This is a projection gate only. Worktree installation, manuscript closure,
complete source regression, promotion, and Overleaf gates remain coordinator
responsibilities; these fingerprints are not permission to bypass them.
