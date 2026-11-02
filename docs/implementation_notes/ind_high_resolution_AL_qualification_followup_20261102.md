# Independent-study AL filter: audited follow-up and opt-in batching

Status: **SOURCE IMPLEMENTED; AUTHENTIC HIGHER-RESOLUTION DIAGNOSTICS NOT RUN**.
No original model was refitted. No source qualification, source benchmark or
agreement check in this note authorizes full forecast reconstruction or an
article change. The coordinator must review, freeze, test and grant new
finite purposes before execution.

## Why a new diagnostic is justified

The source-`b380b279626def03c5bfc99a524e0b21b4080e76` attempt completed
six filters at 64, 256 and 1,024 particles for seeds 71521 and 71522. It
failed its final strict runtime comparison and remains **unaccepted**.
Its 54 quantile rows independently reconstruct 20 of 27 passing descriptive
agreements; seven fail. Completing the arithmetic did not establish accuracy.

The strict-runtime issue has a separate source correction: initialize native
numerical modules before pinning, and retain before/after inventories. A
generated-data diagnostic identified `modules/lapack.so` as the sole newly
mapped software file; no other path or byte digest changed. Commit
`53cb0d4b823b5d75ccbd885b28ee3e5be9613371` preserves strict hashes and the
old failure rather than declaring that old execution successful.

A separately bounded audit verified the frozen manifest before reading
exactly the six generated filter artifacts. It read no original fit,
training-input RDS or future truth and ran no additional genuine filter.
All six share the same static parameter identity: original c72 native column
1, AL probability 0.05 and scale 1.1506455357846179. Relevant diagnostics are:

| At 1,024 particles | Seed 71521 | Seed 71522 |
|---|---:|---:|
| Median look-ahead ESS |1019.15|1017.97|
| Minimum look-ahead ESS |1.96|6.04|
| Minimum selected ancestor count |40|50|
| Checkpoint-500 residual ESS |1024|1024|

The smallest look-ahead ESS occurs near observations 16 and 34; a further
concentration occurs at observation 458. Residual weights are equal under the
fully adapted AL step, so residual ESS equal to the particle count is an
algebraic property, not evidence of numerical accuracy. Initial-lineage counts
alone are also insufficient: all initial components represent the same
Gaussian. Checkpoint state moments and the full look-ahead histories must be
considered instead.

At checkpoint 500, seed-71522 minus seed-71521 quantile differences are
-1.6090, -1.6527 and -1.6527 at probabilities 0.05, 0.50 and 0.95. This
near-common shift, together with the state-mixture diagnostics, is consistent
with Monte Carlo variation in the filtering distribution; it is not evidence
of a tail-specific inversion error. This interpretation is diagnostic, not a
proof that a larger particle count will pass.

## What the new source changes

`scripts/ind_batched_al_auxiliary_filter.R` is opt-in. The reference/default
`ind_aaf_step()` and `ind_aaf_continue()` are unchanged. The new
`ind_baf_al_propose()`, `ind_baf_step()` and `ind_baf_continue()` batch the
existing AL proposal transforms and retain scalar matrix arithmetic and
**every** reference positive-semidefinite check.

For each selected ancestor, the same four supplied uniforms choose a tilted
truncated-Gaussian temporary location and the same native GIG auxiliary.
The temporary location is discarded before the state update. The initial
Gaussian, discount matrix, static parameter, look-ahead weights, systematic
ancestor selection, Kalman means/covariances, residual weights, ancestry and
checkpoint representation remain unchanged. The evolution remains
`P = G C G'`, `R = P + D * P`, where `*` denotes the Schur product. No
observation is assimilated twice and no static-parameter weight is updated.
The opt-in backend rejects exAL; exAL retains its existing reference.

Generated-data tests compare extreme probabilities, remote observations,
zero/tiny variances and open uniforms near both endpoints. They compare the
whole filter, weighted states/covariances, exact ancestry, chunk continuation
and caller RNG. Scalar/batch parity uses the predeclared absolute-plus-relative
`1e-10` tolerance; transform checks use `1e-12`. These are arithmetic checks,
not Monte Carlo precision certificates.

## Measured benefit, with its scope retained

A one-core generated profile with six states, 256 particles, 36 observations
and several extreme observations attributed 43.15% of inclusive sampled time
to scalar AL proposals and 36.50% to PSD checks, including 19.27% to eigenvalue
calculations. This motivated batching proposals rather than removing checks.

After warm-up, three interleaved repetitions per backend gave median CPU
times 6.283 s scalar and 3.276 s batched: **1.918 times faster** in this
generated example. All resulting weighted states, covariances, ancestry and
checkpoints passed the declared parity checks; no RNG state changed. This
is not an authentic higher-resolution benchmark, a host qualification or
proof of affordable whole-campaign reconstruction.

## Prospective two-actor diagnostic

Use a new purpose schema `ind_high_resolution_AL_filter_contract_v1`.
`scripts/qualify_ind_high_resolution_filter.R` admits exactly one of two fixed
seeds, 71521 or 71522, and exactly two higher resolutions, 4,096 and 8,192.
Both process the same 500 training observations and original parameter column
and report H=1 conditional quantiles at checkpoints 100, 250 and 500 for
probabilities 0.05, 0.50 and 0.95.

| Actor | Logical CPU, only after a fresh grant | CPU / native timeout | Address space | Complete output |
|---|---:|---|---:|---:|
| Seed 71521 |26|5400 s; TERM5399 s, KILL after1 s|2 GiB|256 MiB|
| Seed 71522 |27|5400 s; TERM5399 s, KILL after1 s|2 GiB|256 MiB|

These are prospective hard caps, not current reservations or execution
permission. Protect the SMT siblings 58 and 59 and existing scientific owners.
The second actor must wait if CPU27 is occupied by another admitted purpose.
Both R and the exact native timeout must retain the one-core affinity and
the same timeout-led process group/session. Per-process `RLIMIT_CPU` alone
is not sufficient aggregate enforcement. Setup and terminal accounting have
separate coordinator prices. There is no automatic restart or seed selection.

The supplied-stream namespace is
`ind_ancestor_first_AL_high_resolution_max8192_v1`. Each seed generates one
maximum-8192 stream before fitting; both resolutions use its prescribed
prefixes. This deliberately differs from the previous maximum-1024 layout.
Do not call it an unchanged old numerical stream or relabel the old 20/27
REVIEW. Both old fixed seeds are retained; neither is selected from outcomes.

Before the expensive phase, a 64-particle/eight-observation check compares the
scalar and batched calculations on the authorized native prefix and verifies
exact ancestry and unchanged caller RNG. This is part of the new bounded
purpose, not an unadmitted preflight run. It is followed by the two complete
higher-resolution filters. No original fit RDS is deserialized; its bytes are
hashed only. The sole scientific RDS read is the existing 13,728-byte,
500-observation truth-free input. Historical failed artifacts are rehashed,
not deserialized or altered.

The coordinator's combined-source review strengthened this native-prefix
check to elementwise absolute-plus-relative `1e-10` comparisons at every
numeric leaf, with exact structure/attributes and metadata. It does not use
an aggregate `all.equal` discrepancy that could obscure an isolated mismatch.
The default scalar algorithm and the Monte Carlo agreement tolerances are
unchanged.

Each actor retains its supplied stream, both complete filter artifacts,
18 H=1 quantile rows, nine within-seed comparisons, runtime inventories and
source/progress/terminal evidence. `ind_hq_comparisons()` combines the two
18-row surfaces into 27 predeclared comparisons: nine within each seed and
nine between seeds at 8,192 particles. The criterion remains absolute OR
relative tolerance 0.005, with relative scale `max(1, abs((a+b)/2))`.
`ind_hq_aggregate_metadata()` additionally requires two complete actor receipts
and two accepted external terminal receipts with identical source/static
target. The coordinator still authenticates actual file manifests and receipt
bytes; the pure aggregation helper does not authenticate files by itself.

All failures and numerical REVIEWs are retained. Even 27/27 descriptive
agreements cannot set `filter_accuracy_certified`,
`future_integration_accuracy_certified`, `full_IF01_or_production_qualified`
or publication flags to true. Other parameters, mechanisms, quantiles and
multistep forecasts remain outside this one-column diagnostic.

## Cost and admission

The earlier six-filter attempt used 936.26 CPU seconds across two seeds at
64+256+1024 particles, plus small metadata/inversion overhead. Linear scaling
provides a conservative planning estimate of about 71.3 CPU minutes per seed
for 4096+8192; a 25% contingency gives about 89.2 minutes, motivating the
90-minute cap. Applying the generated-example speed ratio suggests about
37 minutes, but that is not an authentic prediction or an admitted cost
estimate. Retain the conservative cap unless later evidence justifies another
separately reviewed purpose.

An 8192-by-500-by-4 double stream is 131,072,000 bytes before compression.
Scaling the previous compressed streams and filter artifacts suggests roughly
150.6 MB per seed plus small receipts. The source checks a conservative
uncompressed serialization reservation before writing and enforces complete
256 MiB packet and 2 GiB process limits. Two accepted actors still require
an independent complete-cost and representative-accuracy assessment before
any full study reconstruction; this optimization alone cannot justify it.

## Coordinator interfaces and exact boundaries

Pure/runtime metadata helpers:

```r
source("scripts/ind_high_resolution_qualification.R")
ind_hq_required_sources()       # exact 11-file transitive source closure
ind_hq_runtime_inventory()      # initialized strict runtime plus native SSH
ind_hq_comparisons(q, TRUE)     # exactly 36 unique input rows -> 27 checks
ind_hq_aggregate_metadata(q, actor_receipts, external_terminal_receipts)
```

Actor interface, **only** inside a freshly granted OS supervisor:

```bash
Rscript --vanilla scripts/qualify_ind_high_resolution_filter.R \
  --contract /PRIVATE/NEW_PURPOSE.json --sha256 EXACT_SHA256 --execute
```

Use the actually pinned launcher `R.home()/bin/Rscript`, not an unpinned copy.
The purpose must be external, source and tree must be clean/committed and
published, all 11 source bytes must match their Git blobs, and both initial
and final online Git ref readbacks must succeed. SSH uses the same explicit
noninteractive no-Proxy/no-Control options as the MQ qualifier; credentials
belong only in the separately prepared private SSH agent, never in a file,
command, source or chat. Its lifetime must cover the complete 90-minute
payload and terminal source readback.

The new external accounting hook must recognize
`ind_high_resolution_filter_receipt_v1`: **two** large run receipts and
**nine** within-seed comparisons per actor, not the legacy six-run/27-row
schema. It must verify the output manifest, native time, source/purpose
identities and zero exit before the pure two-actor aggregator is used.
Accepted execution and a descriptive agreement pass remain separate states.

No `main.tex`, supplement, article asset, PriceFM, GloFAS or Phase182 path is
owned by this change. Ignored runtime and audit receipts must remain outside
Git. Integration and any later publication remain coordinator responsibilities.
