# PriceFM R146: bounded AT fallback and complete-surface closeout

AT's failed architecture has required AL fits that exhausted the original
bounded rescue. R146 selects the first distinct architecture from the saved
training-only RHS ranking, completes its internal AL confirmation, and then
fits the three official folds. It preserves the healthy rollout and original
failure evidence. It does not promote a model or publish article changes.

## Frozen scientific decision

The fallback is RHS rank 4, candidate `r134_7a422c0c3473f81f`,
`tau0=0.0016320908467640013`, readout dimension 577. Ranks 1–3 share the
failed architecture. The saved three-split Normal-RHS proxy AQL is
7.02839841945065, approximately 0.45% above the failed architecture's best
proxy. No official score is used to select this candidate.

This changes the architecture and shrinkage setting relative to failed AT;
it is a new training-ranked model choice, not same-target continuation.
Within each fit, the frozen priors, likelihood, target and certificate
standards remain unchanged. The model remains independent seven-quantile
AL-RHS VB with the stochastic Normal-RHS VB driver, 500 recursive paths,
96 quarter-hour horizons and the prespecified `cdf_pool_clipped` operator.
AL defaults to 300 iterations. There is no automatic second fallback,
expanded search, acceptance relaxation or additional model family.

Exactly six sealed training prerequisites are imported: statistics and
Normal-RHS fits for three splits. Their original R140 source identity is
verified through the R141 import receipt and exact hashes. No AL fit from
the failed architecture is reused. The new internal stage has 27 tasks
(three designs, 21 AL fits, three scores); the official stage has 59 tasks
(three designs, 24 fits and 32 forecast chunks). Official work is withheld
until the complete internal confirmation certifies.

## Components and ownership

- `489_run_pricefm_stage_r146_at_training_fallback.py` and its JSON config
  audit and prepare the new candidate, wait for the old AT lane to drain,
  run the unchanged frozen R141 engine through the new worker entry point,
  and record a separate AT fallback terminal/provenance.
- `490_closeout_pricefm_stage_r146_all_region.py` validates all regional
  artifacts and combines exactly four reused R137, 32 R141, original R144
  CZ and new R146 AT results. CZ is pinned to its original source, independent
  of this collector's source. The primary table must contain exactly 114
  unique region/fold rows; all four operators must have complete regional
  surfaces. Remote inspection failures raise errors instead of appearing
  as absent results. Existing sealed closeouts cannot be silently replaced.
- `491_supervise_pricefm_stage_r146_resource_handoff.py` returns released AT cores
  to the continuation queue only after the fallback reaches a terminal
  state and all its workers have exited. Its separate guardian and durable
  handoff receipts protect the old supervisor during the transfer.

The resource handoff initially leaves the 8+7+15 physical-core partition in
place. The old service uses `KillMode=control-group`, so stopping it while a
healthy child exists is forbidden. The handoff pauses only its verified
parent, allows children to finish, and stops the old service only after a
zero-child check. Before the commit receipt, guardian recovery resumes the
old parent if the new coordinator fails. After that receipt, the new
coordinator owns continuation and restarts/adopts existing work. Its service
must use `KillMode=process` and `Restart=on-failure`. No fitting worker is
signalled or moved to a different CPU by the handoff.

Muscat's original slot B (cores 15–29), both Jerez lanes, existing CZ waiting
service and unrelated research jobs retain their ownership. Operational
reserves are 180 GiB available RAM, 80 GiB free disk on Muscat and 50 GiB on
Jerez; these are not regional storage quotas.

## Reproduction and launch

Use a clean committed dedicated branch based on exact R145
`502ed3fc5fb5929be6377f85fbdcee0e807827f1`. The checkout path is not a source
identity: retain the branch, commit, source hashes and release receipt.
The scientific R141 dependency remains pinned at
`4cd92ac3654f16a84a67c8db6cfc7f381113aeb9`; R127 and package identities remain
those of its release. Keep this checkout frozen while services execute it.

The runtime data root remains
`/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm`.
Use its `runtime_envs/r137_py311/bin/python`, with `-B` and numerical thread
environment variables fixed to one. Bare system Python is unsuitable.

From this checkout, run:

```bash
PRICEFM_PY=/data/jaguir26/local/src/Article-Q-DESN/application/data_local/pricefm/runtime_envs/r137_py311/bin/python
"$PRICEFM_PY" -B application/scripts/pricefm/489_run_pricefm_stage_r146_at_training_fallback.py audit
"$PRICEFM_PY" -B application/scripts/pricefm/489_run_pricefm_stage_r146_at_training_fallback.py release
"$PRICEFM_PY" -B application/scripts/pricefm/490_closeout_pricefm_stage_r146_all_region.py status
```

Deploy three separate transient user services from this committed checkout:
`pricefm-r146-muscat-at-fallback.service` runs `489 ... run`,
`pricefm-r146-muscat-closeout.service` runs `490 ... wait --poll-seconds 300`,
and `pricefm-r146-muscat-resource-handoff.service` runs `491 ... run`.
The resource command additionally requires `--runtime` and `--audit`; generate
the latter with `491 ... audit --expected-old-pid <verified-live-pid>
--output <receipt>`. Keep its runtime under
`launch_prep/pricefm_stage_r146_resource_handoff_20261022/muscat/`.
Record the exact `systemd-run` arguments and source identity in the ignored
deployment receipt. The fallback must begin in a durable waiting state while
old AT attempts remain. Start and validate the new collector before stopping
only `pricefm-r144-muscat-closeout.service`, the superseded read-only watcher.
Never stop the old R145 fitting service directly during deployment.

## Runtime evidence and recovery

The AT campaign and launch preparation use tag
`pricefm_stage_r146_at_training_fallback_20261022`. Its runtime progress and
terminal are under `launch_prep/<tag>/muscat/`; global watcher evidence is
under `launch_prep/<tag>/muscat_closeout/`; final comparison is under
`runtime_audits/<tag>/closeout/`. Resource handoff has its own tag/config and
runtime receipts. Read actual progress and terminal reasons before resuming.

`R146_AT_FALLBACK_COMPLETE_NOT_PROMOTED` requires all certified regional
work. A blocked fallback is preserved as an explicit quarantine and must not
automatically rerun on restart. The collector's final status is
`R146_ALL_REGION_COMPLETE_NOT_PROMOTED`; its fold/region tables, provenance,
summary and completed-evidence seal are the global output. Completion is
not promotion and does not authorize registry/article/main/Overleaf writes.

Focused tests cover imported provenance and rank locking, the actual engine
task graph and worker routing, failure gates, CPU ownership, source and seal
mismatches, remote errors, complete operator/fold surfaces, nonfinite scores,
and handoff/guardian recovery. Live readiness additionally validates existing
regional artifacts; tests cannot guarantee future fit certification.

After this baseline is completely sealed, the separately agreed weak-region
development and independent/joint AL/exAL VB/MCMC study can be specified and
piloted. It is not launched by R146, and test-selected development regions
must not be presented as untouched confirmation.
