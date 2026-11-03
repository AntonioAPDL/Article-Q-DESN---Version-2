# Guarded historical fitted-quantile reporting

`scripts/materialize_glofas_same_family_fitted_history.R` closes the separate
historical-curve extraction gap. It does not fit or retune a model, forecast,
score, read future truth, choose a model by results, edit an article or publish.
Existing fitters, running worktrees, closeout defaults and publication guards
are unchanged. No authentic materialization was performed during development.

## Statistical quantity and authenticated source schemas

The materializer calls the existing pure `gfh_transition_rows()` and
`gfh_normal_rows()` decoders. The transition constructor/writer in
`application/R/glofas_family_transition.R` saves the complete result in
`fit.rds`, including its task identity, target, claim nonce and `fit` core.
`gsc_validate_target()` checks the same retained identity and scientific
target before the pure decoder is used. Multiquantile cores remain in their
declared seven-level order; fixed-probability AL/exAL locations are not
replaced by a Normal quantile rule.

For the enrolled Normal baselines, `enroll_glofas_normal_baselines.R` retains
both `models[[model]]$original_fit` and `input_bindings[[model]]$fit`. They
must be identical to the new purpose's exact path/size/SHA pin. The existing
`gsc_normal_rows()` also validates the separate authenticated enrollment,
prepared-design mapping and analytic reporting contract. The loaded original
state/design identity must agree with that enrollment. No invented decoder,
new Normal reference fit or generic fixed-scale substitute is supplied.

Historical AL/exAL curves are `H_Y E(theta_p)` on the log1p scale, with the
discrepancy block exactly zero in the historical gauge/reference design.
Normal curves use `H_Y E(theta) + Phi^-1(p) E(sqrt(sigma))`, where the saved
Normal `sigma` is inverse-gamma **variance**. With shape a and rate b,
`E(sqrt(sigma)) = sqrt(b) Gamma(a-1/2)/Gamma(a)`, requiring a>1/2; this is not
`sqrt(E(sigma))`. The pure helper performs these checks and the mathematical
tests remain unchanged.

Each curve is the VB mean conditional quantile on the transformed scale,
then inverse-transformed with expm1. It is not the original-scale mean, a
posterior-predictive historical quantile, or a 95% credible band. Future
`q(y_F)` marginal response curves have a different functional and must retain
their existing label. Saved feature-builder callbacks are never invoked.

## Separate purpose and pre-read gates

Exact CLI form (not an execution grant):

```text
Rscript --vanilla scripts/materialize_glofas_same_family_fitted_history.R --contract PRIVATE_JSON --sha256 SHA --execute
```

`glofas_same_family_fitted_history_contract_v1` has an exact field set checked
by `gfm_scope()`. All non-history permissions must be false. It fixes a fresh
nonce/expiry; exact clean committed execution worktree/commit/tree and ten
reader/validator/constructor source pins; origin25December2022; log1p scale;
30 consecutive historical dates26November–25December2022; input-manifest,
design, Normal-enrollment and selected fit roles; finite CPU/wall/memory/output
and read budgets; and a fresh ignored destination. Metadata interfaces are
checked before their role reads. Source role paths must equal the declared
closure before those source files are hashed.

The complete sixteen-producer collector runs before any RDS deserialization.
It requires matching COMPLETE/master/source/target, exactly sixteen accepted
attempts with successful owner/worker termination and accounting, and a pinned
closed query-only SQLite snapshot without a nonempty WAL. The active state
ledger path is forbidden as the snapshot input. The collector never loads a
model, mutates a ledger or opens truth; its complete model-payload hash pass
is explicitly priced. A missing/failed/unclosed producer is not filled by an
old result. The Normal receipt remains a separate enrolled source, not a
seventeenth transition producer.

Two **presentation scopes**, not result-based selections, are explicit:

| Scope | RDS model reads | Fitted rows |
|---|---:|---:|
| `main_figure_v1` | Seven independent AL + Normal Ridge =8 | 420 |
| `all_six_families_v1` | All16 transition fits + both Normal fits =18 | 1,260 |

Both scopes require the same complete16-producer acceptance gate. The design
is deserialized once; each selected model once, sequentially. Every selected
model pin must equal its accepted or separately enrolled original role before
any model is loaded. Before/after hashes protect every design/model read.
No raw-GloFAS seven-quantile historical fan is fabricated from its single
retrospective product value.

Before invoking the collector, `gfm_precollect_read_cost()` requires its
declared complete-artifact ceiling plus two hashes of every selected model
and design to fit the combined read grant. It also checks prospective RDS
bytes and the exact count; incompatible nested caps fail before the first
collector payload read. After collection, `gfm_read_cost()` keeps the exact
accepted-artifact calculation and requires the full hash count plus two
additional hashes for every selected RDS/design, their exact serialized byte
sum, and the exact deserialization count. `gfm_metadata_cost()` adds a
conservative metadata/code-path upper bound, including collector sidecars
at their documented caps, repeated source/metadata reads, source Git checks,
purpose parsing and small native-process records. That bound is not measured
OS I/O. These read budgets are distinct from CPU, wall and memory limits.

The collector and its explicit controller import use only Python's standard
library. It is invoked with `/usr/bin/python3.11 -I -S -B`, excluding ambient
site/PYTHONPATH initialization and bytecode writes. The native vanilla
Muscat R4.6 one-thread/affinity/finite-limit and exact
whole-group TERM/KILL checks are reused from `gst_runtime()` and its pure
process-group helpers. Loading that helper source defines its other functions;
the materializer never calls its truth adapter or allows a truth role. Any
actual actor still needs the coordinator's fresh complete16/quiescence check,
exact source/read/resource purpose and independently closed supervisor. A
purpose or generated test is not permission to consume a currently active fit.

## Output and verification

Outputs are `fitted_conditional_quantiles.csv`, `raw_fitted_crossings.csv`,
`FITTED_HISTORY_DECISION.json` and `artifact_manifest.csv` in a new ignored
directory. Raw adjacent fitted-grid crossings and their exposure are retained
without sorting or isotonic adjustment. The decision keeps all input roles,
source/purpose identity, read accounting, estimand/transform and zero
fit/forecast/scoring/callback/truth/publication flags. These are candidate
plotting inputs only; article changes require later scientific review.

`application/tests/test_glofas_same_family_history_materializer.R` uses only
generated metadata and small in-memory designs/results. It exercises exact
permissions, field/role names, scope/count/resource budgets, complete16 and
terminal-accounting failures, model/enrollment pin mismatches, Normal state
identity, full six-family geometry, inverse transforms and retained crossings.
The separate existing pure-history suite tests the Normal half-moment and
source/date/feature guards. No authentic model/design/truth file or ledger is
read by either test. Full CLI source/runtime/collector execution is not claimed
from these generated tests; it remains closed until a fresh admitted purpose.
