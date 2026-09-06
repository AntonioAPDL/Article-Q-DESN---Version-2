# PriceFM Stage-R68 authority reconciliation

Stage-R68 is a read-only reconciliation layer for the PriceFM application lane.
It is designed to prevent wasteful refits by joining the frozen independent
seven-quantile Q-DESN authority, prior confirmation attempts, failed structured
exAL evidence, the CRAN 1.1.1 package boundary, cached PriceFM, operational
fold-aligned PriceFM, and current article assets into one case-level ledger.

The stage does not fit models, launch jobs, mutate registries, update the
article, or write launch YAML. Its output is a target queue for a later,
separately reviewed Stage-R69 CRAN-native independent VB refit.

## Inputs

- Stage-R62 matched seven-quantile independent authority.
- Stage-R48 frozen test audit.
- Stage-R50 MCMC confirmation closeout.
- Stage-R54 exAL-M0 closeout.
- Stage-R65 early-stop mechanism-failure closeout.
- Stage-R66 corrected structured exAL preparation summary.
- Stage-R67 CRAN 1.1.1 authority transition.
- Cached PriceFM full-surface decision registry.
- Operational PriceFM public-architecture replay proposal.
- Current PriceFM article asset manifest and summary.

## Decision contract

The operational PriceFM replay is treated as the controlling comparator for
future refit targets because it is the stronger full-surface fold-aligned
PriceFM replay currently available. Cached PriceFM remains a secondary
reproducible comparator. The paper Table-II value is external context only and
is not claimed as reproduced by this stage.

Rows where current Q-DESN already beats operational PriceFM are harm guards.
Rows with near or moderate operational gaps may enter a bounded future refit
queue. Far-gap rows remain on hold until a new mechanism is justified. Existing
R65/R66 structured exAL artifacts are not reused as promotion evidence.

Future new fits must use exact CRAN `exdqlm` 1.1.1 public APIs, preserve
validation-only selection, and keep registry/article mutation blocked until a
separate promotion gate passes.

## Validation

Focused tests:

```bash
application/data_local/pricefm/venv/bin/python -m pytest -q \
  application/tests/test_pricefm_stage_r68_authority_reconciliation.py
```

Materialization:

```bash
application/data_local/pricefm/venv/bin/python \
  application/scripts/pricefm/235_audit_pricefm_stage_r68_authority_reconciliation.py
```

Expected outputs are under:

```text
application/data_local/pricefm/authoritative/pricefm_stage_r68_authority_reconciliation_20260831
```
