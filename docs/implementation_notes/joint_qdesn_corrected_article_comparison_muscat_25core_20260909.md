# Corrected JOINT article comparison: Muscat 25-core execution lane

Date: 2026-09-09

## State

```text
SCIENTIFIC_CONTRACT:  FROZEN_AND_IDENTICAL_TO_V2
IMPLEMENTATION:       VERIFIED
PRODUCTION_RUNTIME:   NOT_CREATED
VB:                   NOT_LAUNCHED
MCMC:                 NOT_LAUNCHED
ARTICLE_AND_OVERLEAF: OUT_OF_SCOPE
CAPACITY:             BLOCKED_BY_PRICEFM_AND_GLOFAS
```

This lane adapts the corrected common-posterior JOINT comparison from Jerez
to one Muscat execution. It does not alter the model, selected backbones,
article fixture, seeds, posterior target, score, coupling, diagnostics, or
promotion rule. It does not reuse any historical VB or MCMC fit.

## Authority and isolation

The lane descends without rewriting from:

```text
work/joint-qdesn-corrected-article-comparison-jerez-20260909
f2c5303f5683c2606330997c744d836210bfead4
```

The Muscat branch and worktree are:

```text
work/joint-qdesn-corrected-article-comparison-muscat-25core-20260909
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_corrected_article_comparison_muscat_25core_20260909
```

The ignored production runtime is reserved at:

```text
application/cache/joint_qdesn_corrected_article_comparison_muscat_25core_20260909
```

Historical Jerez, Phase181, and Phase182 outputs remain separate and cannot be
used as inputs or destinations.

## Frozen scientific graph

| Stage | Count |
| --- | ---: |
| Gaussian RHS VB initializers | 8 |
| Independent AL VB fits | 56 |
| Independent exAL VB fits | 56 |
| Joint AL VB fits | 8 |
| Joint exAL VB fits | 8 |
| Total VB components | 136 |
| Compact model-cell initializers | 32 |
| Five-chain MCMC workers | 160 |
| Joint-minus-independent contrasts | 16 |

The seven-level grid is `0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95`. The AL
continuation order is `0.50, 0.25, 0.75, 0.10, 0.90, 0.05, 0.95`. Each exAL
fit receives only the matching AL fit as initialization. Joint fits start
after the matching independent grid is complete. MCMC starts only after all
136 VB components and all 32 compact initializer hashes verify.

The common-posterior contract retains the corrected global variance shape,
fixed RHS slab variance one, Gaussian-location intercept-prior centers,
positive unbounded likelihood scale, five chains per model cell, and one
chain-invariant posterior-target SHA-256 per cell. The primary score remains
the known-DGP expected finite-grid quantile score using twice check loss and
the frozen trapezoidal weights.

## Exact v2-to-v3 differences

The confirmation contract may differ only in:

```text
contract_version
run_tag
execution_branch
host_profile_id
source_worktree
initial_concurrency
maximum_concurrency
cpu_affinity_list
required_physical_cores
capacity_approval_token
```

The score contract may differ only in `contract_version` and `runtime_root`.
The automated Muscat contract test compares every row and rebuilds both seed
plans to prove that execution metadata does not alter scientific seeds.

## Physical-core and process gates

Muscat exposes 64 logical CPUs on 32 physical cores. Production uses logical
CPU IDs `0-24`, which map to 25 distinct physical cores on this host. Every v3
R invocation is prefixed by `taskset -c 0-24`, and each numerical library is
restricted to one thread.

The R preflight reads `Cpus_allowed_list` from `/proc/self/status`, reads the
Linux package/core topology from sysfs, and fails unless the effective set is
exactly `0-24` on 25 distinct physical cores. It records the complete mapping
in `cpu_affinity_preflight.csv` and the summary in `host_preflight.csv`.

The process gate fails when any user-owned PriceFM, GloFAS, Phase182,
historical article-confirmation, corrected Jerez, corrected Muscat, or generic
JOINT article queue is active. Only the current process and its descendants
are excluded. The Muscat runtime cannot be created until this host and
affinity preflight passes.

The read-only capacity audit at `2026-09-10T00:57:10Z` observed:

| Gate | Observation | Status |
| --- | ---: | --- |
| Effective affinity under `taskset -c 0-24` | IDs `0-24` | pass |
| Distinct physical cores | 25 | pass |
| Available memory | 456.8 GiB | pass |
| Free `/data` storage | 451.5 GiB | pass |
| Load average (1/5/15 min) | 24.68 / 24.62 / 24.55 | review |
| Competing-process matches | 46, including active PriceFM and GloFAS | blocked |
| Production runtime | absent | pass |

Therefore no launch-free production preflight and no worker launch was run.

## Detached source evidence

The production contract reads only this detached evidence worktree:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_shared_backbone_evidence_detached_muscat_20260909
```

It must remain clean and detached at:

```text
50cb2478bcbb9f59abf03203084b86e0a1d44ee6
```

Its ignored source runtime is copied without modifying the attached source
worktree. Before production, all eight frozen top-level hashes, the nested
manifest, 7,560 completed source jobs, zero failures, eight selected
backbones, 56 finite aggregate rows, 14 contrasts, and 32 future model cells
must verify.

## Execution controls

The launcher is:

```text
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh
```

It is fixed to R 4.6.0, the Muscat v3 contracts, the detached source evidence,
the isolated Muscat runtime, 25 workers, and CPU affinity `0-24`.

When the capacity gate is clear, run the launch-free preflight first:

```sh
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh --preflight
```

Inspect every generated preflight CSV. A zero exit code alone is not enough.
Then authorize only VB:

```sh
export JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED=MUSCAT_25_PHYSICAL_IDLE
export JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=VB
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh --launch-vb
unset JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION
```

After 136/136 VB components and 32/32 compact initializers verify, authorize
MCMC separately:

```sh
export JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION=MCMC
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh --launch-mcmc
unset JOINT_ARTICLE_CONFIRMATION_ALLOW_PRODUCTION
```

Only after 160/160 workers verify may the score packet be finalized:

```sh
application/scripts/launch_joint_qdesn_corrected_article_comparison_muscat.sh --finalize-score
unset JOINT_ARTICLE_CONFIRMATION_CAPACITY_APPROVED
```

## Failure policy

No worker is restarted, deleted, or replaced automatically. Any failure
preserves its output and log for classification as numerical, environmental,
or contractual. No historical cell can fill a failed corrected cell. The
complete 32-cell packet is accepted or rejected as one comparison.

## Publication boundary

This execution lane changes no manuscript, table, figure, PDF, bibliography,
article manifest, `origin/main`, or Overleaf ref. A successful packet will be
frozen and handed to a separate coordinator for article regeneration,
compilation, integration, and Git-only publication.

## Verification record

Verification used `/data/jaguir26/local/opt/R/4.6.0/bin/Rscript` with every
numerical-library thread variable fixed to one.

| Check | Result |
| --- | --- |
| Eight handoff-required focused tests | pass |
| Full `application/tests/run_tests.R` harness | pass |
| Changed R-file parse checks | pass |
| Jerez and Muscat corrected launcher `bash -n` | pass |
| `git diff --check` | pass |
| Detached source HEAD and clean state | pass |
| Eight frozen source hashes | 8/8 pass |
| Source artifact manifest | 7/7 pass |
| Nested source manifests | 14/14 pass |
| Source campaign health | 7,560 complete, 0 failed |

The full harness reported its existing optional discrepancy-adapter skip
because the Q-DESN discrepancy engine is unavailable; all executed tests
passed. The portable legacy confirmation fixture now reads the same immutable
detached Muscat source evidence, creates the minimal synthetic Gaussian
initializer required by its precision audit, and records deterministic parity
references under pinned R 4.6.0. Production provenance checks remain strict.

The branch must be committed, pushed, fetched back, and verified `0/0` before
any later capacity-cleared preflight or production launch.

Until PriceFM and GloFAS end, the correct state is:

```text
MUSCAT_25CORE_IMPLEMENTATION_READY_CAPACITY_BLOCKED
```
