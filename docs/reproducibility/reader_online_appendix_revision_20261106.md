# Reader-focused article and Online Appendix revision

## Authority and scope

This editorial revision starts from
`6370677bf37204dd494db1b7f649d2ceb288f36b`. The implementation authority is
the author's correction plan, with the terminology and mathematical
standards in `Academic_Writing_Style_Profile_v0.2.md`. The companion
`reader_online_appendix_corrections_20261106.csv` records all attachment
items, including the empty item 12 and the appendix request.

The main-paper revisions and appendix consolidation are implemented. The
input comments have SHA256
`086c4a0958a83a3479f1fdc593004fe2ceed8f129c2aeec96314af04167ff48c`.
The approved planning authority is the ignored
`local_trackers/article_corrections_advisor_review_20261106/FINAL_PLAN.md`
in the baseline integration worktree. This revision does not replace a
scientific result or qualify the paused GloFAS optimizer.

## Main changes

- The abstract and Introduction identify the statistical contributions,
  distinguish direct response-quantile regression from residual calibration,
  and retain the current comparator and provisional-result scopes.
- The displayed DESN readout contains reservoir features only, with its
  corrected dimension; direct-input extensions remain analysis-specific.
- The main NS joint-prior kernel remains explicit. Its normalization and
  Bruno's authenticated centering question are addressed in Online Appendix A,
  rather than repeated as main-text qualifications. Internal equation labels
  and the actual prior specification are retained.
- MQ--DESN motivation, adjacent-slope shrinkage, constrained intercepts and
  computation are described without claiming hard noncrossing. The particular
  point-intercept VB approximation is scoped to its simulation algorithm.
- The forecasting display pairs each parameter draw with its own recursively
  generated predictors. The MQ study still identifies the averaged-feature
  construction that produced the current primary scores. Its single main
  projection disclosure distinguishes adjusted scores from raw crossings.
- The score equations define unstarred reported quantiles. The Bracher et al.
  reference explains the interval-score connection without relabelling the
  unequal-weight trapezoidal score as conventional WIS.
- Main references use Online Appendices A--E. GloFAS wording distinguishes
  sampling quantities together from the MQ--DESN model name; PriceFM retains
  its actual direct-horizon design.

The appendix content-disposition register separately records retained,
consolidated and archived presentation roles. Internal source filenames and
the article publication inventory are not renamed by this revision.

## Appendix organization and decisions

| Appendix | Retained purpose |
|---|---|
| A | Distributional conventions, priors, single-level MCMC and VB, structured scale--shape calculation and variational objectives |
| B | Multiquantile target, difference-prior precision, coefficient/intercept updates and covariance moments |
| C | Recursive trajectories, the actually scored mean-feature construction, ordering, crossing and scores |
| D | Simulation designs, computation, recovery, 500-target sensitivity, empirical frequencies and multiquantile comparisons |
| E | Application specifications, the current GloFAS target/approximation and full-family evidence, and the electricity-price design |

The 56-role disposition map records 20 retained, 19 consolidated and 17
public-archive roles. Archiving means removing a repeated PDF inclusion,
not deleting its public source or numerical asset. The 128-file article
allowlist is unchanged.

Three requested simplifications need a precise statistical treatment:

- The forecasting display can describe paired recursive draws, but it must
  not relabel existing mean-feature scores as newly reconstructed forecasts.
  The simulation account and Appendix C retain that distinction.
- The actual scored grids are projected. One main-text disclosure and the
  exact appendix definition remain; deleting both would obscure the estimand.
- The current trapezoidal weights are unequal. The new Bracher citation
  supports the interval-score identity, not a false equality with conventional
  WIS under those weights. The original metric and every score remain fixed.

The NS normalizing factors and the authenticated response to Bruno's
centering question remain in Appendix A. Numerical computation details
needed to interpret the reported fits survive consolidation. The retained
GloFAS computation table reports elapsed time; the prose does not promise
an absent CPU-time column.

## Presentation and validation ownership

Caption edits are made in their generators and generated TeX together.
The new `refresh_reader_online_appendix_receipts_20261106.py` successor
preserves all three earlier refresh records and verifies current semantics,
required evidence routing, unchanged scientific assets and post-write source
stability. Earlier refresh scripts and frozen scientific manifests are not
rewritten to bless this revision.

Dated literal-prose checks may read authenticated baseline text only after
the actual new documents pass the current semantic and scientific checks.
Live routing checks continue to reject stale forecasts, omitted mandatory
results and altered numerical assets. Tests distinguish compiled evidence
from unchanged archived material instead of requiring every upload asset
to be printed in the appendix.

Copied Python mutation fixtures use an explicit test-only API mode after
full admission of the real checkout. It checks the copied current documents,
roles and public manifests and reports that Git ancestry is not authenticated.
There is no automatic missing-Git fallback, receipt/environment switch or
publication CLI override; ordinary validation still checks the full current
Git-backed source. R data-only fixtures validate scientific data without
requiring an unrelated article-text adapter.

## Protected scientific evidence

No model fitting, forecasting, rescoring, reservoir tuning or scientific
operation is authorized by this editorial record. Numerical CSVs, existing
scientific figure PDFs, contracts, empirical coefficient counts, priors,
software-execution provenance and current authorities must remain unchanged.
The general trajectory display does not claim a reconstructed scientific
comparison. Presentation generators and receipts require a narrowly scoped
update; historical receipts are preserved rather than overwritten.

GloFAS native optimizer development remains paused. The current article
authority and that unqualified future method are distinct states: no new
pending-result notice or optimizer result is introduced here. No scientific
operation has been launched by this editorial revision.

## Verification record

The baseline review proofs completed cleanly with unchanged formatting:

| Proof | Baseline main | Revised main | Baseline appendix | Revised appendix |
|---|---:|---:|---:|---:|
| Identified | 38 | 37 | 105 | 70 |
| Anonymous | 37 | 36 | 104 | 69 |

All four revised review proofs compile with clean final LaTeX/BibTeX logs.
Selected model, forecast and appendix pages were visually inspected. The
identified appendix is 35 pages shorter (one third); essential methods and
evidence remain accounted for rather than silently discarded.

| Validation | Outcome |
|---|---|
| Complete registered repository coverage | 249 validation steps completed across the preserved prefix (184) and resumed tail (65) |
| Current mathematical/source checks | 32 pass |
| New successor receipt tests | 13 pass |
| MQ nomenclature and negative fixtures | 21 tests pass |
| V2 article projection | 559 checks; 19 intended mutations rejected |
| IND authority/routing | 15 intended mutations rejected; current IND checker 23 checks |
| Reader, statistical-language and forecast-exposition checks | Pass, including their existing negative fixtures |
| Scientific evidence | 1,207 protected files unchanged; no application/R, configuration, scientific CSV or existing figure change |
| Article dependency inventory | 128-file allowlist and dependency check pass |
| Review proofs | Four clean builds; selected pages visually inspected |
| Whitespace/error check | `git diff --check` passes |

The final complete-environment invocation was interrupted by the session
termination, not an assertion failure. Its log ends at the start of
`test_ind_high_resolution_qualification.R`; the previous registered check
passed. The continuation re-executed that interrupted test and all remaining
original registry expressions after the exact original initialization. Those
remaining checks run in child processes and require no earlier test-fixture
globals. The continuation exited zero. This establishes complete registered
coverage in two segments, not an uninterrupted monolithic zero-exit claim.

The original driver SHA256 is
`c04cfe1aa35d96f8d673c552940b0289dfac2541c02c83d1bcb11b03dd9da318`;
the preserved prefix log SHA256 is
`667758b2b179754d7cc11c3543a148513f7b9cbf808c7fc28ea85330baee1383`;
the successful continuation log SHA256 is
`2d9d6e6c294ea1b67523c8db8ce20cd0799c71a5245e87e56bb56ecaef7afb10`.
The worktree-status digest was unchanged before and after continuation;
current source/receipt checks authenticate the manuscript and protected files.
The ignored resume runner and both logs are retained, along with earlier
environment and outdated-routing failures.

Declared boundaries remain: the unavailable external discrepancy-engine
adapter, the optional native interface without an explicit fixture, and the
four-worker affinity probe without an explicit allocation were not run.
Existing generated approximation-failure findings remain deliberately
retained by their diagnostic tests. Neither a passing software test nor this
editorial revision qualifies a new GloFAS scientific method or fixes its
forecast performance. One synthetic plotting-range warning occurred; the
four final manuscript build logs are clean.

### Qualified test environment

The verification uses R 4.6.0, Python 3.11, GCC 8.5.0 and `digest` 0.6.39.
The existing verified R library contains `posterior` 1.6.1, `checkmate` 2.3.4,
`distributional` 0.9.0 and `tensorA` 0.36.2.1, built under R 4.6.0. It was
used read-only, not upgraded. The isolated Python test environment contains
PyYAML 6.0.3 and PyMuPDF 1.26.5. System Python and R installations were not
modified. Use a full Git checkout for historical receipt authentication.

From the repository root, a fresh uninterrupted verification can use the
same registry with the qualified library and Python paths:

```bash
env -u PYTHONPATH \
  PATH="$QDESN_TEST_PYTHON_BIN:$PATH" \
  R_LIBS_USER="$QDESN_TEST_R_LIBRARY" \
  OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
  /data/jaguir26/local/opt/R/4.6.0/bin/Rscript application/tests/run_tests.R
```

Set the two task-specific path variables to verified environments with the
versions above; do not substitute unverified newer diagnostic packages.

### Integration and publication gate

The coordinator must record exact source/merge hashes and the isolated
committed source-bundle result in the local integration receipt. The merge
must retain the baseline and dedicated editorial commit as its two parents,
with no unreviewed content changes. Use only the existing guarded Git main
and article-only publishers. Remote completion is a separate state requiring
fresh main, snapshot and direct-Overleaf readbacks after the owner's command;
this tracked editorial record does not assert a remote push.

Current state: `EDITORIAL_VERIFIED_REMOTE_PUBLICATION_GATED`.
