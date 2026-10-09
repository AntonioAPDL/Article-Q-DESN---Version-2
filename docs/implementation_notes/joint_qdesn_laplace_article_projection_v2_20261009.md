# JOINT Laplace article projection v2

## Scope and authority

This coordinator revision integrates the frozen Laplace scientific branch
`work/joint-qdesn-laplace-article-confirmation-20261008` at
`6ff88298d7f10814071a9fec4a9a6d32804cdfb1`. Its three dedicated commits are
`58fc231c957c261968ce5ae73d0a77004012eede`,
`f7b152de757a7e792f1f441eec563170a576b4ab`, and
`6ff88298d7f10814071a9fec4a9a6d32804cdfb1`. The initial integration main is
`16ee797331c7f92ed69159b5c4ea9d83d6d74857`.

The article projection replaces all four Laplace MCMC cells and all four
Laplace VB cells coherently. It does not select favorable rows from competing
backbones. Every original scientific column and CSV row for the seven other
scenarios is retained exactly. Independent-study, GloFAS, and PriceFM results,
their figures, and the early empirical placeholders remain unchanged.

Historical `joint_qdesn_pure_desn_v1_*` assets and their hash-pinned receipt
remain intact in Git. The active manuscripts and article-only upload instead
use `joint_qdesn_pure_desn_v2_*`. Historical checks validate the old evidence
without requiring it to remain the live article projection.

## Corrected handoff arithmetic

The original handoff and the owner's corrected addendum have SHA-256 hashes
`c382e03056ecbe49c4e8e9ac928c3907d14292a9af13f9b6ead64c5d50aebe43`
and `ad069e7efd88c2dbc7012ebbc3a5bc5829d82fac38878a7eca4b20be70e6c56f`,
respectively. The correction changes bookkeeping, not frozen fits or scores.

The old article's global raw posterior-mean-grid crossing counts were
`11 / 2645 / 0 / 288` for Joint AL, Independent AL, Joint exAL, and
Independent exAL. Its Laplace contribution was `1 / 41 / 0 / 0`.
Replacing those four contributions with `0 / 4 / 0 / 0` gives
**`10 / 2608 / 0 / 288`**, not the initial handoff's `8 / 2606 / 0 / 288`.
Each model has 47,520 forecast comparisons; the respective percentages are
0.021044%, 5.488215%, 0%, and 0.606061%.

The figures report scenario-specific percentages. The supplementary crossing
table gives equal weight to the eight scenario-specific posterior-draw rates,
so extra retained Laplace exAL draws do not implicitly increase its scenario
weight. Both equal-scenario and pooled draw-level rates, raw counts, and actual
denominators remain in the numerical CSV.

## Frozen-input verification

The retained runtime consists of 440 regular files with 316,467,546 file bytes.
The original 316,721,498-byte directory receipt also includes host-dependent
directory metadata. File-level transfer verification and all owned nested
manifests must pass; these quantities are not conflated.

The projection reads frozen designs, variational fits, posterior draws, score
receipts, and oracle inputs. It never constructs a fresh fitted context,
optimizes a variational objective, runs an MCMC chain, or changes a scientific
source. The retained source and copied runtime remain ignored and are not
deleted. The source closeout manifest and score receipt are pinned to:

| Artifact | SHA-256 |
| --- | --- |
| Closeout manifest | `13ea15c3b45e1cd373134b7e90bf643ccbf463bd703cff079f126ddb3f22efd3` |
| Closeout scores | `b670b1deadd7fc056605780893b910c2480fec9f7eec9e48ee768ae112f3882b` |
| Closeout decision | `fdea5c463c14030511cae540cfc55aad119d3b9eacd0013697dd7be5e814e6ef` |

The generated source-hash, runtime-manifest, replacement, target-hash, and
postprocessing ledgers provide the remaining compact provenance. These are
Git reproducibility evidence; companions referring to runtime objects are
excluded from the article-only upload.

The source confirmation has 40 chains: 20 matched-baseline and 20 replacement
chains, including 20 exAL chains in total. The article replacement alone has
10 exAL chains. Its sampler audit records 55 precision repairs in eight
candidate workers, with maximum relative jitter `1e-12`. Historical full-packet
repair totals are kept separately: the old aggregate cannot be converted into
a current aggregate without the old Laplace-specific breakdown. Current
exAL chain cardinality remains 80 across the 32 article cells.

## Deterministic reconstruction and uncertainty

All candidate MCMC draws are used: five chains with 750 draws each for AL
and 1,500 each for exAL, giving 3,750 and 7,500 pooled draws. The unchanged
historical cells retain their original 3,750 draws. Independent quantile blocks
retain their documented within-chain permutation before projection.

The VB projection draws 4,000 stacked slope vectors from each retained
covariance, holds intercepts at their fitted point values, and records the
deterministic seeds. Recursive-feature integration is checked against the
original state/score stability criteria; any additional integration draws
are postprocessing of the same frozen fit, not refitting. The VB intervals
therefore omit intercept covariance and are explicitly partial.

True fitting RMSE is recomputed from the projected posterior-mean quantile
paths. Reconstructed MCMC fitting MAE and primary mean-design scores must
match the frozen receipts. MAE is never relabeled RMSE.

For trajectory-inclusive sensitivity, every retained scoring draw receives
its own recursively simulated feature path. A vectorized implementation is
checked against the native evaluator for three draws at all 990 forecast rows
per cell. The numerical comparison must be within the declared tolerance.
The primary intervals condition on the averaged future feature matrix;
trajectory-inclusive intervals retain future-feature variation and are
reported separately. Neither calculation establishes predictive calibration.

Same-family contrasts pair matching retained draw indices. Cross-family
contrasts use the larger cardinality and repeat the shorter AL sequence;
no exAL thinning is permitted. This is an explicit descriptive coupling
between separate fits, not a claim of a unique posterior for model contrasts.
The new Laplace contrast percentiles use R's type-7 interpolation to reproduce
the handoff endpoints. Primary score intervals retain the native type-8
calculation, and unchanged scenarios retain their historical summaries.
This small interpolation distinction is recorded, not concealed by enlarging
a numerical tolerance.

Old and new architecture and shrinkage specifications differ together.
The evaluation realization was excluded from candidate selection but had
previously been evaluated. Neither single-component attribution nor a claim
that this realization was previously unseen is justified.

## Reader-facing presentation

The main article retains forecast DGP-integrated score means and equal-tailed
95% limits; the supplement retains point fitting RMSE. Figures use the current
large-label vector style, with no canonical-action ticks or internal campaign
identifiers. Numerical tables retain the distinct projected-mean-grid score
with an explanation, not an unexplained graphical marker.

For Laplace, the Independent AL mean is 0.361285947519198, Joint AL is
0.362708531591024, Independent exAL is 0.362677987460607, and Joint exAL is
0.362621750203866. Their marginal intervals overlap. This supports descriptive
ranking, not predictive equivalence. The full packet has two joint and six
independent numerical winners; the two asymmetric-tail joint-minus-independent
intervals favor joint fits, and the other fourteen contain zero.

`qdesn_article_presentation_manifest_v2.json` retains the nine unaffected
independent/GloFAS presentation outputs and replaces only the four JOINT
figure/wrapper outputs. The old presentation receipt remains unchanged in Git.

## Reproduction and acceptance checks

On a clean repository checkout, the public presentation can be reproduced
without runtime objects:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_joint_qdesn_pure_desn_article_projection_v2.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/check_joint_qdesn_pure_desn_article_projection_v2.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  application/tests/test_joint_qdesn_pure_desn_article_projection_v2.R
```

Frozen-fit reconstruction additionally requires the ignored authenticated runtime:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript \
  scripts/build_joint_qdesn_pure_desn_article_projection_v2.R --reconstruct \
  --runtime-root /absolute/path/to/verified/frozen/runtime \
  --cache-root /absolute/path/to/fresh/ignored/postprocessing/cache --workers 4
```

Acceptance requires the three source-lane tests, relevant recursive-score,
oracle, RHS, posterior-target, historical-projection, supplementary-mathematics,
and bibliography checks; the new projection's fail-closed mutation checks;
vector/typography QA; independent and application publication invariance;
the final manuscript checker; dependency-inventory equality; and
`git diff --check`. Both identified and anonymous manuscripts are built by
`scripts/build_technometrics_review.sh` with no final warnings or overflow.
Any repository-wide fixture limitation is reported separately, not converted
into a full-suite pass.

The existing RHS reference test required a removed main-text heading and
equation label. Its numerical calibration assertions are unchanged; its
editorial assertions now check the current main-text reference and the
supplement's numbered Gaussian calibration. The current independent v14
checker also validates the versioned publication companion and all seven
unchanged independent display outputs. The hash-pinned older oracle-figure
checker remains unchanged: its historical-wrapper assertion does not describe
the already-published larger-label presentation. It is not claimed as a
current full pass; the v14 authority checker and presentation tests validate
the active derivatives instead.

## Completed coordinator validation

The final frozen-fit reconstruction verified 57 owned manifests and 230
payload entries. All eight replacement VB/MCMC cells satisfy the original
state/score integration gates. Native recursive-path checks agree with the
vectorized calculation to at most `2.38698e-15`. The 32 active MCMC cells
therefore have 32 strict stability passes and zero reviews; this does not
remove the separately reported scalar-mixing qualifications.

The public v2 checker passes 384 scientific/data assertions and 516 full
article assertions. Its regression test rejects all 13 deliberately corrupted
fixtures, including stale Overleaf entries and asset hashes. The historical
v1 checker passes 207 evidence assertions in historical-only mode. The
independent v14 authority checker passes 374 assertions, and the unchanged
GloFAS and PriceFM publication checks pass. The dependency inventory matches
all 100 article-allowlisted files.

Focused source, posterior-target, recursive-score, oracle, RHS, supplementary
mathematics, and bibliography tests pass on the combined tree. Suite-loaded
algebra and RHS reference tests are invoked with their declared dependencies,
not as invalid standalone scripts. The new vector-figure test passes all six
checks, and the unchanged PRO presentation test passes all five checks. The
guarded main and Overleaf publisher fixture suites also pass. These results
are scoped checks, not a claim that every historical repository test passes.

Final identified manuscript builds have 36 main and 84 supplement pages;
anonymous builds have 35 and 83 pages. Both versions have clean final logs,
with no undefined references, overflow, or final warnings. This verifies
manuscript compilation and anonymization; it does not certify that every
journal submission declaration or external submission requirement is closed.

Both regenerated JOINT PDFs are one-page vector figures with embedded fonts
and no raster panels. Their minimum ordinary label size after insertion is
approximately 9.08 pt. The forecast and fit figure SHA-256 values are,
respectively,
`365434ff899e8da47df213e42fd8d97b48e2a4f89b1edd004c9098c4b99303ac`
and
`1f4df7355ece393b1ec9a84096cd83af2e1429c52a2e7538e67adef86f3ee6bd`.

## Publication boundary

After validation, the coordinator preparation branch is committed and pushed.
A fresh final integration worktree merges that frozen coordinator branch onto
the latest fetched main with two explicit parents. Only the guarded
`publish_integration_main_git_only.sh` and
`publish_overleaf_article_snapshot.sh` commands publish main and the one-way
article snapshot. Normal command-line Git pushes are used; no force push,
GitHub extension, synchronization connector, or scientific-worktree mutation
is authorized. Final success requires fresh remote commit/tree/source-marker
readback and a clean final worktree. Authentication or gate failures stop
publication and are reported explicitly.
