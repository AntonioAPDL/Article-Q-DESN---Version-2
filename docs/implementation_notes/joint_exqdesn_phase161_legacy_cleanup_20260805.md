# Phase161 legacy-output cleanup

The cleanup is deliberately narrow. It deletes only compressed posterior draws from the superseded Phase159 screening campaign and the independently rejected Phase160 nonlinear-reservoir candidate. Before deletion it records every path, byte size, SHA-256 hash, rationale, and decision. Compact metrics, diagnostics, provenance, source manifests, Phase157b reference draws, the confirmed Phase160 Student-t draws, fixtures, and all article-facing evidence are retained.

Preview and execute with:

```bash
Rscript application/scripts/208_cleanup_joint_exqdesn_phase161_legacy_outputs.R
Rscript application/scripts/208_cleanup_joint_exqdesn_phase161_legacy_outputs.R --execute true
```

Original worker manifests are retained as pre-cleanup provenance and therefore continue to name the intentionally archived payloads. The cleanup ledger is the authoritative record of their removal. This avoids rewriting historical evidence while preventing an automated health check from mistaking archival deletion for an unexplained loss.
