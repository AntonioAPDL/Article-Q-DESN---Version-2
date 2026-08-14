# GloFAS Application Engine-Frozen Relaunch, 2026-05-27

The diverse, flex, and seed-repeat application candidate batches were stopped
after several active candidates hit the same Q-DESN engine source-policy
failure. Their configs pointed at the moving shared validation worktree but
required the older engine commit `d075941313186b15853e94c2a2cad7d0fec410d8`.
The shared worktree had advanced to
`73c043f0436b508808366f312350fd44c2d06771`, so those runs would not pass the
provenance gate.

To keep long application runs independent from validation-side movement, the
application now uses a frozen app-only engine worktree:

```text
/data/jaguir26/local/src/exdqlm__wt__article_app_engine_73c043f
```

Expected engine provenance:

```text
branch: article/app-engine-73c043f
commit: 73c043f0436b508808366f312350fd44c2d06771
version: 1.0.0
compiled shared object: src/exdqlm.so
```

The preparation script writes fresh config/model-grid copies with the suffix
`engine73c`, fresh cache paths, and fresh run IDs. It does not mutate the
historical configs or partial run folders.

The frozen worktree must contain `src/exdqlm.so` because the application loads
the Q-DESN engine from local source. If a fresh frozen worktree is created, copy
or rebuild the shared object before preparing or launching the batch.

```bash
Rscript application/scripts/03_prepare_engine73c_relaunch_batch_20260527.R
bash application/scripts/03_launch_engine73c_relaunch_batch_20260527.sh
```

Launch manifest:

```text
application/config/glofas_engine73c_relaunch_20260527_launch_manifest.csv
```

tmux session:

```text
glofas_engine73c_relaunch_20260527
```

The relaunch covers the stopped or invalidated no-score candidates plus the
one seed-repeat candidate whose score was produced but whose final readiness
gate reported the engine-provenance failure. Already completed, scored
candidates with clean outputs are kept as historical evidence and are not
restarted by this relaunch script.
