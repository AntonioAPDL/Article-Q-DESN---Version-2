# GloFAS Part 4 corrected-target qualification

## Purpose

The November same-family campaign converged numerically but produced 39--46
adjacent future-quantile crossings and worse CRPS than raw GloFAS. Global-path
references reproduce those crossings, so longer optimization, a different
Monte Carlo budget, or replacement of the local Gaussian-Delta approximation
does not repair the target.

The completed 29 October unit-member campaign is the exact coherent
counterpart that must be qualified before any refit. Its sixteen quantile fits
use one frozen Part 3 Normal-RHS Gaussian path prior, exclude future USGS
likelihood factors, retain all 1,428 issued-member factors, and use the same
Search III-selected reference and discrepancy specifications. November records
the October fit IDs and exact October design SHA256 as its source before
replacing that shared path prior with separate level-specific same-family
future laws.

## Workflow

`application/scripts/451_build_glofas_part4_corrected_target_qualification.R`
performs a read-only deep audit of:

- 18/18 October status markers and numerical gates;
- the 4.0 GB truth-free shared-design SHA256;
- all eighteen target manifests;
- all eighteen fit-side RDS objects, read sequentially;
- all independent and MQ future-prior flags and hashes;
- all sixteen November source configurations and target receipts;
- the frozen global-path root-cause decision;
- Search III, October, and November common-window scores and paths.

It emits ignored CSV evidence, a report, a multi-page forecast-path PDF, an
artifact manifest, and a decision receipt. The checker in script 452 verifies
that packet without reading or changing any fit.

## Scientific gate

Passing qualification means only:

`CORRECTED_PART4_TARGET_QUALIFIED_NO_REFIT_REQUIRED_INTEGRATION_REVIEW_PENDING`

It does not update article aliases, select on the protected issued window, or
promote a result automatically. Search III remains the coherent historical
control. The user must review the coherent later-design packet before the
coordinator performs any authority transaction.

The workflow launches zero fits, performs zero future-truth reads for model or
method choice, and modifies no article or Overleaf files.
