# PriceFM R123 Cadence-Verified Completion

Observer output: application/data_local/pricefm/campaigns/
pricefm_stage_r123_cadence_verified_closeout_20261005 (ignored).

## Verified correction to the audit interpretation

The frozen pipeline specifies 15-minute observations. The actual Jerez parquet
has 93,504 consecutive quarter-hourly rows. Matching every stored BG target
to its source rows proves that H96 means 96 fifteen-minute steps, not 96 hours.
For example, the first raw target block is 2022-02-03 00:00 through 23:45 UTC;
the next origin is February 4 at 00:00. Their targets do not overlap.

The initially proposed three-origin embargo assumed hourly rows and was wrong
for this campaign. It was not launched, and no score or model was changed.
The final implementation requires an explicit sample cadence, verifies labels
against timestamps, and retains all 125 / 135 / 174 internal validation origins.
The corrected rule is max(training anchors + 95 * actual sample step) < v.
For this campaign the final training target precedes validation by 15 minutes.

Lag orders are also in quarter-hourly steps: 720 is 7.5 days, 1560 is 16.25 days,
2880 is 30 days. Do not interpret them as hours. The historical window-expanded
training design has no repeated target blocks across these daily origins.

## Smallest efficient implementation

Preserve the active certified-successor source and all its evidence unchanged.
RHS dimensions, prior centres and posterior targets are not altered by this
timestamp clarification. Its Normal state certification and bounded tau pilot
remain valid; its nine independent AL ladders continue automatically.

`443_audit_pricefm_stage_r123_cadence_closeout.py` runs on a separate branch and
in a separate ignored output namespace. It verifies the parent's frozen source,
all target timestamps and every BG label, writes a hashed cadence receipt, then
monitors without fitting, rescoring, stopping, or changing parent artifacts.
One otherwise-idle physical core bounds this observer's work. On parent exit,
it acquires the parent's existing lock read-only, verifies Normal certifications,
saved-score identities, AL eligibility and artifact hashes, and freezes a final
evidence inventory. Incomplete or failed panels are reported, not fabricated.
Changed or missing source/label evidence blocks certification and never repairs
runtime files silently. A completed observer can resume by verifying both ledgers.

This phase is BG Fold-1 training-internal only. It excludes exAL, joint, MCMC,
official validation/test evaluation, registry/article changes and publication.
No Ridge, Normal, or AL fit is repeated by the observer. Primary AL fitting is
bounded at 63 atoms, with existing score-blind cap companions if required.
Predictive stability is not proof of full AL variational stationarity.

## Next scientific gate

Wait for the current AL panel, inspect its convergence/eligibility and internal
recursive forecast scores, and freeze its winner only if the panel is complete.
Never combine legacy coefficient-only convergence labels with certified Normal
states. A failed panel requires targeted diagnosis before another fit campaign.
Official comparison or expansion to new regions remains a later approved phase.
Do not claim exhaustive global optimality from this bounded shortlist.

The source branches may be clean and pushed while science is still running.
Article integration remains NOT_READY_FOR_INTEGRATION in this phase; only the
coordinator owns main and Overleaf publication. Earlier notes that described a
96-hour horizon must be clarified, not used to redesign or rerun correct fits.
