# PriceFM legacy artifact cleanup (2026-08-05)

This cleanup is limited to closed PriceFM runs owned by this workstream. It is
designed to recover disk space without removing the evidence needed to audit or
reproduce scientific decisions.

The cleanup preserves all R34-selected R33 experiments in full. For nonselected
R33 experiments and closed negative R25, R30, and R32 runs, it may remove only
an explicit allowlist of reconstructible row splits, prediction matrices,
feature-map matrices, and diagnostic PNGs. Metrics, manifests, logs, reports,
parameter summaries, provenance, hashes, and all R36-R39 artifacts are retained.

The script refuses to run while any PriceFM stage process is active. Dry-run is
the default and writes a SHA-256 ledger. Apply mode requires both `--apply` and
`--force`; it consumes the existing ledger and revalidates roots, allowlists,
selection status, and file sizes before deletion, avoiding a second high-I/O
hash pass. It never scans non-PriceFM directories.

```bash
python application/scripts/pricefm/165_cleanup_pricefm_legacy_run_artifacts.py
python application/scripts/pricefm/165_cleanup_pricefm_legacy_run_artifacts.py --apply --force
```
