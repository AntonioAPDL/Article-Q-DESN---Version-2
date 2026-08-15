# Joint exQDESN Phases 158--159: quantile-fan diagnosis and split-RHS calibration

## Decision

Phase157b completed 64 verified collapsed gamma--sigma MCMC chains. It removed
the implementation blocker and improved the Phase149 VB fit in every scenario,
but six scenarios still trail their matched Joint QDESN AL references. More
chains are not a general remedy: five scenarios already have acceptable mixing,
and chain-specific forecasts preserve the same performance ordering.

Phase158 therefore performs no refit. It reconstructs the pooled posterior mean
from all 192,000 verified draws and decomposes each fitted quantile gap into its
ordered-intercept and dynamic readout contributions. The audit confirms a
systematic compressed fan. Forecast 90% width ratios range from 0.77 to 0.86,
and the fitted 0.90--0.95 gap is only 0.53 to 0.78 of its oracle value. The
dynamic contribution to that upper gap is negative in every scenario.

## Why Phase159 is new

Earlier phases screened gamma slice geometry, priors and initialization,
posterior summaries, chain length/count, common RHS `tau0` and `zeta2`, ordered
intercept scales, and alternative reservoir maps. Phase152 rejected the two
reservoir candidates under independent replication. Repeating those searches
would not target the mechanism identified by Phase158.

The RHS prior already represents the first quantile coefficient vector as an
anchor and subsequent vectors as cross-quantile innovations. Before Phase159,
the public fitters forced both block types to share the same global and slab
controls. Phase159 exposes separate `anchor_tau0`, `innovation_tau0`,
`anchor_zeta2`, and `innovation_zeta2` arguments. Defaults inherit the legacy
`tau0` and `zeta2`, so all existing fits remain exactly reproducible.

## Calibration design

Persistent Heavy Tail is frozen as the Phase157b pass. Asymmetric-Laplace Tail
retains its current specification and is reserved for additional same-contract
chains. The six underperforming scenarios each receive four candidates:

1. exact same-contract reference;
2. moderate innovation-`tau0` relaxation;
3. stronger innovation-`tau0` relaxation;
4. the moderate relaxation with a twofold looser innovation slab.

The multipliers are scenario-specific and are generated from the Phase158
severity classification. Anchor controls, DESN features, likelihood, scale
prior, ordered-intercept prior, gamma transition, fixtures, and scoring contract
remain frozen. The complete campaign contains 24 candidates and 96 independent
chains. Each chain uses 6,000 iterations, 1,500 burn-in iterations, and thinning
by 3. Twenty-four single-threaded workers run concurrently by default.

## Gates and promotion

Hard failure covers source/hash errors, malformed controls, nonfinite draws or
scores, nonpositive scales, incomplete workers, and contract crossings. A
candidate is eligible only if it materially improves forecast oracle MAE over
the same-screen reference while keeping fit MAE within 5% and check loss/grid
CRPS within 2%. Ranking and promotion are scenario-specific. A calibration
winner is not article evidence; it must receive a subsequent eight-chain,
12,000-iteration confirmation.

## Commands

```bash
Rscript --vanilla application/tests/test_joint_exqdesn_phase158_159.R
Rscript --vanilla application/scripts/196_audit_joint_exqdesn_phase158_quantile_fan.R
bash application/scripts/201_launch_joint_exqdesn_phase159_split_rhs.sh
Rscript --vanilla application/scripts/200_check_joint_exqdesn_phase159_split_rhs.R
```

Phase158 artifacts:

`application/cache/joint_qdesn_phase158_quantile_fan_decomposition_20260804`

Phase159 freeze and result directories:

`application/cache/joint_qdesn_phase159_split_rhs_calibration_freeze_20260804`

`application/cache/joint_qdesn_phase159_split_rhs_calibration_mcmc_20260804`

No article asset is modified by either phase.

## Completed Phase159 result

All 96 chains completed and all 576 declared worker artifacts passed SHA-256
verification. All 24 pooled candidate summaries are finite, and both raw and
contract crossing counts are zero. The implementation gate therefore passes.

Two candidates meet the prespecified material-gain and guard criteria:

- Nonlinear Reservoir Friendly: `innovation_tau0_x3` reduces forecast oracle
  MAE from 0.15394 to 0.15009 (2.50%) and fit MAE by 0.53%.
- Student-t Location-Scale: `innovation_tau0_x1p5` reduces forecast oracle MAE
  from 0.10624 to 0.10333 (2.74%) while increasing fit MAE by only 0.13%.

Check loss and grid CRPS improve slightly in both cases. The other four
scenarios prefer the same-contract reference; increasing innovation flexibility
there is neutral or harmful. The tail decomposition is mixed: the nonlinear
candidate improves the lower tail but slightly worsens the upper tail, whereas
the Student-t candidate improves the upper tail but worsens the lower tail.
Consequently, Phase159 supports two case-specific predictive candidates but
does not establish a universal repair of quantile-fan compression.

The first automatic finalization attempt stopped before writing aggregate
tables because Phase159 supplied incomplete metadata to the shared CRPS
grouping helper. No worker or posterior draw was affected. The finalizer now
uses the established Phase122 metadata constructor, the regression test covers
that contract, and the repaired finalizer source is recorded separately in
`finalizer_source_code_snapshot.csv`.

The next admissible stage is an independent eight-chain, 12,000-iteration
confirmation of only these two candidates. It must use new seeds and compare
against the already frozen Phase157b eight-chain references. Article assets
remain unchanged until that confirmation passes.
