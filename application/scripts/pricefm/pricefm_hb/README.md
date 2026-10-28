# PriceFM Hummingbird preparation and control

This adapter provides a separately identified, Python-only Hummingbird TEST
qualification and a prospective FI/DK2 COST_ONLY lifecycle. Original scientific
sources, fixtures, thresholds, campaigns and sealed local audit bundles retain
their own identities. The new adapter does not impersonate an old host launcher.

The continuation entry and live qualification evidence are in
`local_trackers/pricefm_hb_scientific_preparation_20261027/START_HERE.md` in the
main article checkout. That local audit contains the exact site configuration,
source/input manifests, retained failures, scheduler accounting and retrieved
results. These data and SSH credentials are deliberately outside this package.

## Verified boundary

Environment job868112 and reference-profile parity job868114 completed and were
retrieved to Muscat. All15 retained arrays passed the comparison fixed before
execution; nine identity/truth/lag arrays were bitwise exact. Predictions use the
original absolute1e-12/relative1e-10 tolerance. Native HB dispatch first failed
that strict comparison; the fixed profile below reproduces the original
Sandybridge/AVX execution profile, with unchanged science, fixture and tolerances.

```text
OPENBLAS_CORETYPE=Sandybridge
NPY_DISABLE_CPU_FEATURES=AVX2,FMA3,F16C,AVX512F,AVX512CD,AVX512_KNL,AVX512_KNM,AVX512_SKX,AVX512_CLX,AVX512_CNL,AVX512_ICL
```

Both OpenBLAS pools must attest Sandybridge, one thread and the qualified ELF
SHA256s. The worker verifies the compiled NumPy dispatch targets before a model
call. Python3.11.13 and all nine wheels are pinned; interpreter artifacts and
hashes are retained. The remote interpreter is built in an allocation from
explicit conda-forge packages, then installed from the offline wheelhouse.
Conda defaults terms were not accepted. No environment is copied from Muscat.

The three failed setup/parity attempts remain charged. The qualification ledger
has exhausted its explicitly amended five-attempt/5400-reserved-CPU-second
allowance. This is not permission to retry qualification. Future regional cost
work uses a separate canonical ledger and one attempt per region.

## Prepare a fresh regional launch package on Muscat

Administrative commands must run on CPU31 with the pinned interpreter. From
this worktree's `application/scripts/pricefm` directory:

```bash
admin() {
  taskset -c 31 /data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python -B "$@"
}
audit=/data/jaguir26/local/src/Article-Q-DESN---Version-2/local_trackers/pricefm_hb_scientific_preparation_20261027
plan="$audit/benchmark_plans/FI_COST_PANEL_NOT_ADMITTED.json"
```

Choose new absolute paths for every `--output`, `--new-config` and
`--destination`; existing evidence is never overwritten. The examples below
use a new operator directory named `next_FI_01`.

```bash
admin -m pricefm_hb.readiness new-window \
  --plan "$plan" --config "$audit/READINESS_OPERATOR_CONFIG.json" \
  --output "$audit/operator/next_FI_01/calendar.json" \
  --new-config "$audit/operator/next_FI_01/config.json" --seconds 7200
admin -m pricefm_hb.readiness refresh \
  --plan "$plan" --config "$audit/operator/next_FI_01/config.json" \
  --output "$audit/operator/next_FI_01/proofs"
admin -m pricefm_hb.cost_control prepare-launch \
  --plan "$plan" --request "$audit/operator/next_FI_01/proofs/launch-request.json" \
  --config "$audit/site.canonical.json" \
  --destination "$audit/operator/next_FI_01/release"
```

`new-window` creates an unclaimed calendar proposal, never an authority or a
renewal. It refuses a spent region or unresolved canonical claim. `refresh`
reads actual EE closure, Muscat/Jerez process ownership, legacy closure, HB
queue/node/partition, memory and disk. The observer has60 wall seconds and10
CPU seconds. Any missing, stale, unreadable or conflicting proof blocks it.
Positive site/no-overlap/drain proofs last300 seconds. `prepare-launch` verifies
and copies every allowlisted byte and executed source; it creates no claim,
authority, SSH operation or job. A saved prepared package is an immutable
snapshot, not a standing launch permission. Regenerate fresh proofs and a new
package at execution time. Use the DK2 plan for a separate DK2 preparation.

## Explicit future cost execution

Only after the prospective cost run is deliberately selected, use a freshly
prepared release. Each operation checks the immutable release and canonical
Muscat ledger. The actual cost run is one CPU,4096MiB in the currently prepared
site proof, at most1200 wall/CPU seconds, on the measured eligible node. The
controller requests account/partition128x24 and QoSnormal explicitly.

```text
admin -m pricefm_hb.cost_control submit-held --release RELEASE --config SITE
admin -m pricefm_hb.cost_control issue-authority --key RETURNED_TASK_KEY --config SITE
admin -m pricefm_hb.cost_control release-job --key RETURNED_TASK_KEY --config SITE
admin -m pricefm_hb.cost_control status --key RETURNED_TASK_KEY --config SITE --receipt NEW_RECEIPT
admin -m pricefm_hb.cost_control collect --key RETURNED_TASK_KEY --config SITE --receipt TERMINAL_RECEIPT --incoming NEW_QUARANTINE --destination NEW_PUBLICATION
```

Replace uppercase placeholders with actual absolute paths and the returned key.
Submission writes its intent before `sbatch --hold`. Authority binds the actual
held job/node before release. Lost replies stay ambiguous and consume their
attempt; there is no automatic resubmission, retry or budget refund. An unused
held job can be explicitly cancelled with `cancel-held --key KEY --config SITE`.
Poll no more often than every300 seconds. Collection requires the exact queue
identity gone, complete root/batch/.0 terminal accounting and resource limits,
all16 retained packets, the full result seal and original scientific identities.
Retrieved data go through a new quarantine directory and create-only verified
publication on Muscat. Do not double-count step CPU in parent-job totals.

The panel comprises12D calls,4S calls and2 immediate C0 replays in eight
contexts. It retains16 zero-loss NPZs, reports cost only and computes no AQL or
candidate selection. Imports, input preparation, serialization and cleanup share
the same finite1200-second scope. FI has60 parent proofs; DK2 has63. Neither
region's complete prefix, AL fitting, official-origin evaluation, promotion or
posterior update is admitted by a cost result. Actual own-region timing and
memory must price any later continuation, including the declared contingency.
Run the two prospective panels sequentially; the current single cost owner
deliberately prevents simultaneous regional cost claims.

## Validation and boundaries

```bash
admin -m unittest discover -s pricefm_hb -t . -p '*_tests.py' -v
```

Local tests mock numerical/transport boundaries; no local model is run by them.
Real Slurm environment, forecast, accounting and retrieval checks are documented
separately. The qualification controller admits only `environment` and `parity`
TEST roles. All numerical work requires a real single-CPU Slurm compute
allocation; login-host execution is rejected. Physical remote paths start with
`/mnt/beegfs/home/jaguir26/`; symlink ancestors remain forbidden.

The existing local baseline scheduling, GEFS ownership uncertainty, seven
mandatory AT/LT/NO3 certificate failures,29 withheld dependants and source525
runtime-compatibility proof are separate gates. Their repair plan is preserved
in the audit; successful HB parity does not mark them fixed.
