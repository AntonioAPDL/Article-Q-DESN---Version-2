# PriceFM matched fold and horizon comparison

## Purpose

The main PriceFM table now presents comparisons evaluated on common held-out
timestamps. The contextual values reproduced from PriceFM Table II have been
removed because they arise from different fitted analyses and aggregation and
therefore do not form a direct comparison with the Q--DESN results.

## Main-text display

The replacement table has two panels.

1. The first panel reports overall and fold-specific AQL summaries for all 114
   matched region--fold comparisons. It gives the number of comparisons in
   which Q--DESN has lower AQL, the number in which PriceFM has lower AQL by at
   most 5%, the number in which PriceFM has lower AQL by more than 5%, and the
   model-specific mean AQL and paired mean and median differences. The 5%
   classification is one-sided and is computed relative to PriceFM AQL.
2. The second panel reports paired AQL differences for four forecast-lead
   blocks. These summaries use the 72 comparisons with complete
   horizon-specific diagnostics. The source records paired differences rather
   than separate model-specific horizon means, so the table retains that
   estimand.

In both panels, the difference is Q--DESN AQL minus PriceFM AQL. Negative
values favor Q--DESN. The two denominators are stated in the caption and prose
because the horizon subset does not decompose the 114-comparison aggregate.

## Manuscript organization

The main article reports the overall, fold, and forecast-lead results in one table.
AQCR, MAE, and RMSE remain in the surrounding paragraph. The supplement retains
the twelve selected-versus-reference Q--DESN comparisons and the comparison by
predictor set; its duplicate fold and forecast-lead tables have been removed.

The protected PriceFM Table II values remain in the archived CSV used by the
asset checks, but no generated TeX table or manuscript file displays them.
The PriceFM R92 scientific values and case-selection decisions are unchanged.
