# Technometrics submission preparation: verified baseline and remaining gates

Date: 2026-10-08.
Starting authority: `3f85d92a3e70f1981264d43d4f1686c0db06ed67`.
Preparation branch: `work/technometrics-submission-format-20261008`.

## Decision

The published advisor revision is not a certified Technometrics submission.
Its generic article class is acceptable in principle, but its 11-point,
one-and-a-half-spaced layout was a working-paper choice. Journal preparation
must not be confused with a new scientific authority or a results promotion.

This branch prepares the authenticated general submission baseline. It does
not submit the paper, modify any scientific fit, or certify the remaining
requirements. Main and direct Overleaf remain unchanged until publication is
separately validated.

## Official evidence

The publisher-hosted [ASA guide](https://files.taylorandfrancis.com/asa-style-guide.pdf)
explicitly includes Technometrics. Retrieved 2026-10-08; no publication date
was supplied. Relevant pages: 2--5, 13--15, 19--20.

Its general baseline permits `article` or a journal template, requires US Letter,
12-point double spacing (26 text lines per page), limits the abstract to 200
words, and specifies three to five keyword phrases. It uses author-year
references and double-anonymous review; neutral self-citations remain. Author
details and acknowledgments are omitted from the anonymous version. Figure
lettering should remain at least eight points at reproduction size. Extended
appendices belong in supplements. Author affiliations/email, relevant funding,
and a competing-interest disclosure must be provided.

The [ASQ journal page](https://asq.org/quality-resources/pub/technometrics)
links to the [journal-specific author instructions](https://www.tandfonline.com/action/authorSubmission?show=instructions&journalCode=utch20).
That endpoint could not be retrieved in this audit. Its current page limit,
count exclusions, portal file categories and exceptions are therefore open.
The older ASA/ASQ-attributed Overleaf example and former-editor writing advice
are not treated as current requirements. Published two-column pages are not
a substitute for the required review layout.

## Controlled preparation

| Source | Change | Boundary |
|---|---|---|
| `main.tex`, `qdesn-supplement.tex` | 12-point Letter; double spacing; body height based on 26 baselines | Scientific meaning and equation values unchanged |
| Both sources | A single anonymous-review switch | Same body and evidence, no separately drifting manuscripts |
| Main | Five keyword phrases | No unexplained acronyms |
| Both sources | Explicit author-year citation punctuation | `apalike` is retained provisionally, not certified as ASA bibliography style |
| Main | Author-owned code link and writing acknowledgment only in identified mode | Neutral third-person self-citations retained |
| Manuscript checker | Enforce the 200-word abstract ceiling | Existing numerical and scientific checks retained |
| Review builder | Compile both documents in both modes in a new temporary directory | No submission, publication, fitting, or deletion |
| Independent figure manifest | Refresh only manuscript/checker hashes | Original source and figure pins must remain unchanged |

At the larger type size, long displays are broken without changing their
mathematical values or labels. The baseline/difference parameter substitutions
are stated individually to avoid an unbreakable inline tuple. The GloFAS
heading is shortened; the retrospective scope remains explicit in its text.
Two supplementary tables receive local presentation adjustments without
editing their authenticated TeX or numerical sources. Identified builds use a
separate title page; anonymous builds use a compact title above the abstract.
Abstract text explicitly uses 12-point type rather than `article`'s smaller
default. Duplicate title-page PDF anchors are avoided without disabling body
links.

The default document remains identified for author review. To compile anonymously,
define `\QdesnReviewMode` before inputting the source. The builder makes four
PDF proofs and checks extracted review text for document-level author identifiers.
It is not an anonymous source ZIP: raw `.tex` still contains the identified
conditional branch, `refs.bib` retains metadata, and the Overleaf projection's
README/source marker identify the repository. Do not send that source ZIP to
reviewers as anonymous material.

## Remaining gates before submission

1. Obtain the current journal-specific instructions or portal checklist.
   Confirm length and included components in the actual double-spaced layout.
   A 22-page working manuscript does not establish a submission page count.
2. Confirm corresponding author and email, complete affiliation address,
   funding and competing interests with all authors. Do not invent a no-conflicts
   statement or grant acknowledgment. Prepare the requested identified title
   page once these facts and portal requirements are available.
3. Replace or adapt `apalike` using an authenticated compatible reference style.
   It does not print DOI fields and does not reproduce all ASA reference
   conventions. Audit rendered entries, citation order and supplement-only
   references without changing bibliographic facts.
4. Repair final-size typography in all six GloFAS Search III vector figures.
   The measured axes/legend sizes are around 3--3.2 points. Authenticate
   missing Part 2 display inputs or derive presentation from existing
   authenticated vector panels. Preserve all data/curves and original PDFs;
   record derivative provenance. Do not refit or relax frozen hash checks.
5. Confirm the representative code/data submission requirement and furnish
   a small verified reproduction of a prominent result, with no private paths
   or model/runtime payloads accidentally bundled. A public repository link
   alone is not proof of a self-contained reproduction package.
6. Obtain accurate author confirmation of the writing-assistance disclosure,
   including relevant tool/version information where required.
7. Check equations, floats, captions and figure lettering at final printed
   size; check identified and anonymous PDFs, their metadata and bibliography.
   Build and inspect the isolated article projection before any publication.

These are submission gates, not scientific rerun instructions. The model,
priors, selection, uncertainty scope and all numerical evidence remain unchanged.

## Reproduction and publication boundary

Run:

```bash
bash scripts/build_technometrics_review.sh
```

Run the existing manuscript, independent figure, JOINT, GloFAS and PriceFM
projection checks under the pinned environments, then `git diff --check`.
Verify all scientific CSVs, figures and inference/configuration files remain
byte-identical to the starting authority, except the explicitly dependent
manuscript-hash manifest. Preserve logs in the ignored QA directory.

No merge or Overleaf publication is implied by this preparation branch.
Any later publication uses the existing guarded command-line Git publishers,
a fresh main-based integration worktree and exact remote read-backs.

Status: `VERIFIED_BASELINE_PREPARED_NOT_SUBMISSION_READY`.

## Verification at the preparation checkpoint

The four proofs compiled with resolved citations and cross-references:

| Mode | Main | Supplement |
|---|---:|---:|
| Identified, including separate title page | 33 pages | 76 pages |
| Anonymous | 32 pages | 75 pages |

Proof root: `/tmp/qdesn-technometrics-review.CcIbq1`. Each PDF is US Letter.
Final logs report `textheight=623.93454pt`, the configured 26 body baselines.
There are no overfull/underfull boxes, undefined citations/references, or
duplicate page anchors. Anonymous extracted text and PDF author metadata
contain none of the document-level author identifiers checked by the builder.
Neutral literature references remain; a complete reference/link review is
still required before treating a file as a final anonymous submission.

Supplementary logs retain two float-only text-page warnings and two Cairo
PDF page-group inclusion warnings from placing two authenticated figure PDFs
on a page. These are not hidden or counted as clean publication checks. They
must be resolved in the remaining table/figure presentation pass before the
strict article-snapshot publication checker can certify the new layout.
The small GloFAS labels remain the independent submission-legibility gate.

Checks passed under pinned R 4.6.0:

```text
scripts/check_independent_validation_dgp_oracle_figures_v14.R: 132 checks
scripts/check_independent_validation_exdqlm_mcmc_rolling_state_fix_article_v14.R: 328 checks
scripts/check_joint_qdesn_pure_desn_article_projection.R: 167 checks
scripts/check_qdesn_final_manuscript_revision.R: 19 scientific hashes, abstract 173 words
application/tests/test_glofas_search3_article_projection.R: PASS
```

Python 3.11, with the existing dependency directory:
`application/tests/test_pricefm_r98_article_projection.py`: one passed.
Shell syntax and `git diff --check` passed. No repository-wide harness or
Overleaf publisher is claimed for this preparation. No scientific run was
launched, continued, stopped, or transferred.

The only changed protected asset is the independent figure manifest: its
three manuscript/checker hash entries are refreshed, with every scientific
source/figure hash unchanged. No numerical CSV, table source, figure binary,
configuration, inference routine or scientific test was modified.
