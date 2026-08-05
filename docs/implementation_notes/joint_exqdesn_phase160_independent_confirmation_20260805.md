# Joint exQDESN Phase160 independent confirmation

## Purpose

Phase159 evaluated 24 case-specific split-RHS candidates with four chains each.
Its implementation gate passed, and only two candidates met the prespecified
forecast-MAE and fit/score guards: `innovation_tau0_x3` for Nonlinear Reservoir
Friendly and `innovation_tau0_x1p5` for Student-t Location-Scale. Phase160 is a
strict confirmation stage, not another screen.

## Why this design is appropriate

The selected candidates must not be promoted from the same four chains used to
select them. Phase160 therefore uses eight new chains per candidate, new seeds,
12,000 iterations, 3,000 burn-in iterations, and thinning by three. Each case
retains 24,000 posterior draws. The frozen Phase157b eight-chain results are the
reference and are not recomputed. This avoids unnecessary baseline work while
preserving an article-scale comparator that was not selected by Phase159.

The candidate likelihood, DESN features, ordered-intercept prior, collapsed
gamma--sigma transition, fixtures, and quantile-grid scoring contract remain
fixed. Only the Phase159-selected anchor/innovation RHS controls differ from the
Phase157b reference. Selection and confirmation remain scenario-specific.

## Reproducibility contract

The freeze records the selected registry rows, frozen VB initialization, chain
start dispersion, chain seeds and seed roles, source-manifest verification,
the Phase157b comparator rows, source-code hashes, provenance, and an artifact
manifest. Phase160 seeds are unique and are checked against the Phase159 and
Phase157b seed inventories. Workers retain compact gzip CSV draws rather than
binary R workspaces.

Sixteen single-threaded workers may run concurrently. A worker directory is
reused only when every artifact hash verifies; incomplete directories are
quarantined before recomputation.

## Gates

Hard failure covers source or artifact hash failures, nonfinite draws or scores,
nonpositive scales, missing workers, or contract crossings. Predictive
confirmation requires a forecast oracle-MAE improvement of at least the larger
of 0.0025 and 2% relative to Phase157b, fit MAE within 5%, and check loss and
grid CRPS within 2%. Rank R-hat must not exceed 1.10. Bulk ESS of at least 100
is a confirmation pass; ESS from 50 to 100 is explicitly retained as mixing
review rather than silently rejected when predictive evidence is otherwise
stable.

The final packet reports overall, lower-tail, upper-tail, and tau-level metrics.
It also reports the remaining gap to the matched Joint QDESN AL result. Passing
Phase160 permits article-candidate review; it does not automatically update the
article.

## Commands

```bash
Rscript --vanilla application/tests/test_joint_exqdesn_phase160_confirmation.R
bash application/scripts/206_launch_joint_exqdesn_phase160_confirmation.sh
Rscript --vanilla application/scripts/205_check_joint_exqdesn_phase160_confirmation.R
```

Freeze:

`application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_freeze_20260805`

Results:

`application/cache/joint_qdesn_phase160_split_rhs_independent_confirmation_mcmc_20260805`

No article, PriceFM, GloFAS, TT500, or independent-QDESN asset is modified.

## Completed result

All 16 chains completed, yielding 24,000 retained draws per candidate. All 96
declared worker artifacts and all 13 top-level artifacts pass SHA-256
verification. Forecast quantiles are finite, and both raw and contract crossing
counts are zero.

The Nonlinear Reservoir Friendly candidate does not confirm. Its forecast
oracle MAE is 0.15402 versus 0.15339 for the Phase157b reference, a 0.41%
increase. The candidate improves the upper extreme but worsens both lower-tail
levels, so the Phase159 aggregate gain was selection noise. The original
Phase157b specification is retained.

The Student-t Location-Scale candidate confirms. Forecast oracle MAE decreases
from 0.12031 to 0.11768 (2.19%), fit MAE decreases slightly, and check loss and
grid CRPS also improve. Six of seven quantile levels improve; the largest gains
occur at tau 0.75 and 0.90. Rank R-hat is at most 1.019 and bulk ESS is at least
464, so this is not a weak-mixing result. The candidate is eligible for an
article-candidate audit, not automatic article promotion.

The confirmed Student-t candidate remains materially behind the matched Joint
QDESN AL row: forecast oracle MAE is 0.11768 versus 0.07967. Phase160 therefore
validates a local exAL improvement but does not resolve the broader AL--exAL
performance gap. Because gamma and sigma mixing are now healthy, adding chains
or iterations is not the appropriate next remedy. The next stage should freeze
this decision and audit the gamma posterior and AL-nesting behavior without new
MCMC before deciding whether any further model calibration is scientifically
justified.
