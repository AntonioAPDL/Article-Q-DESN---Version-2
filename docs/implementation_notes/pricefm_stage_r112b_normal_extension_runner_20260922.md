# PriceFM Stage-R112B: host-local Normal-extension runner

## Scope

The R112B runner executes one deterministic host subset from the validated
R112A package. It does not run on import and cannot launch without the exact
approval token, a clean synchronized PriceFM task branch, matching source and
prepared-output hashes, and an idle host-local CPU/resource preflight.

The controller supports `muscat` and `jerez` independently. Their campaign
outputs live below distinct `hosts/<host>` roots, so locks, progress records,
logs, failures, and winner terminals cannot overwrite one another.

## Execution sequence

For the host-owned regions, the controller:

1. validates the R112A summary, source manifest, launch control, candidate
   manifests, grids, branch identity, CPU set, memory, and disk;
2. materializes the 240-candidate Ridge bank per region;
3. verifies or reuses the three fold-1-training-contained temporal windows;
4. fits incomplete Ridge cells only, one process per selected logical CPU;
5. compacts each completed cell immediately to hashed metric/method evidence;
6. ranks Ridge candidates on median inner-validation AQL and retains 30 per
   region;
7. fits three dimension-adjusted RHS `tau0` arms per retained Ridge candidate;
8. requires convergence and valid AQL on all three inner folds;
9. freezes one regional Normal RHS winner and its full ranking hash;
10. writes a host terminal without opening test data or starting quantile
    models.

The controller is resumable. A cell is skipped only when its R112B compaction
terminal and every retained SHA-256 hash are valid. Failed cells receive a
separate fail-closed terminal and cannot be counted as complete.

## Resource contract

- workers must equal the number of distinct requested logical CPUs;
- Muscat is capped at 25 workers and Jerez at 50;
- every model receives one logical CPU;
- BLAS, OpenMP, MKL, NumExpr, Rcpp Parallel, and BLIS thread counts are fixed
  to one by the inherited validated command environment;
- selected CPU utilization is sampled twice before launch;
- disk and available-memory floors are checked before launch and before every
  model;
- CPU identifiers are chosen at runtime, not hard-coded in R112A.

## Storage contract

Screening posterior objects and adapter matrices are not scientific outputs.
After each successful fit, R112B retains only `metric_summary.csv`,
`model_method_summary.csv`, and their hashes. This keeps the 20,790 maximum
inner fit cells from consuming the disk while preserving the evidence needed
to reproduce every ranking and selection decision.

The selected specification and `tau0` are reusable; binary screening
posteriors are deliberately not reusable. Later quantile work must create the
required outer Normal initializers under the frozen specification.

## Scientific boundary

R112B selects only a Normal initialization/design specification. It does not
claim PriceFM improvement, score outer folds, choose AL versus exAL, fit a
quantile or joint model, run MCMC, mutate a registry, or edit the article.
Those steps remain blocked until both host terminals are complete and the 17
R100 plus 21 R112B winners form one validated 38-region Normal contract.

The companion read-only closeout
`387_close_pricefm_stage_r112b_normal_extension.py` enforces that union. It
requires both host terminals, verifies every winner contract and full ranking
hash, and rejects missing or duplicate regions before allowing R112C to be
prepared. The closeout itself cannot fit or launch a model.

## Invocation boundary

The normal preparation and tests do not invoke this runner. A production
launch is a separate explicit action requiring:

```text
--approval-token RUN_PRICEFM_R112B_NORMAL_EXTENSION
```

Use `--preflight-only` first on each actual host after the identical task
branch and R112A package are present there. Production should use the same
command without `--preflight-only` only after the resulting host audit is
reviewed.
