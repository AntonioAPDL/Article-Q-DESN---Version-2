# GloFAS Search III source reconciliation

Date: 2026-10-07

## Frozen coordinates and scope

| Coordinate | Value |
|---|---|
| Fresh main base | `e721bfddee81269864febea0eca0bbd0c5eba369` |
| Authoritative source branch | `work/glofas-search3-adjacent-tau-recovery-20260930` |
| Authoritative source HEAD | `fecc4bd5dbf608cc30e4b38a49e6d8cb08bf92a1` |
| Scientific authority ancestor | `6aa44a71a4914872d6b0bc6a754920e7f805b9d4` |
| Recomputed merge base | `757522db0f85815244370ec92a194de132268883` |
| Main-only / source-only commits | 44 / 40 |
| Source inventory | 134 paths: 103 additions and 31 modifications |
| Scientific inventory excluding this handoff | 133 paths: 102 additions and 31 modifications |
| Main inventory | 144 paths: 128 additions and 16 modifications |
| Source-only paths | 130: 103 additions and 27 modifications |
| Both-sides paths | Four modifications |
| Source deletions or renames | None |

The source inventory includes the supplied documentation-only main-article
integration handoff. The frozen science worktree was clean at the specified
handoff HEAD. The integration worktree began clean at the freshly fetched main
base; the coordinator inspected every source path before starting the
ancestry-preserving, non-fast-forward merge. No ignored runtime path is part of
the Git source delta. No campaign model fit, search, continuation, forecast, or
calibration was executed by reconciliation; only prescribed synthetic
regression fixtures exercise model kernels.

The path audit is
`docs/implementation_notes/glofas_search3_source_integration_manifest_20261007.csv`.
Its hashes are Git blob object IDs, not SHA256 file checksums. It records every
source-side path, source status, frozen source blob, integrated working-file
blob, and disposition. Of the 130 source-only paths, 128 blobs match the
frozen source exactly; one addition has a documented trailing-whitespace-only
formatting disposition and one test addition has a synthetic-fixture
isolation disposition. The four reviewed shared files have explicit manual
dispositions. There are therefore 128 exact-source and six manual rows.
The manifest covers imported source paths; this reconciliation note and the
manifest itself are newly authored integration audit artifacts.

## Shared-file dispositions

| Path | Git result | Final disposition |
|---|---|---|
| `application/R/README.md` | Conflict | Preserve main's recursive JOINT module documentation; append source GloFAS integrity, continuation, Search II/III, driver-prior, and closeout documentation. |
| `application/scripts/README.md` | Conflict | Preserve main's recursive JOINT launch documentation; append GloFAS history and distinguish frozen historical controllers from final closeout authority. |
| `application/tests/README.md` | Automatic merge, manually reviewed | Preserve main's recursive JOINT coverage; document imported synthetic GloFAS regression coverage and the real-data no-refit exclusion. |
| `application/tests/run_tests.R` | Automatic merge, manually reviewed and extended | Preserve every current-main registration and updated historical-v4 comment; add missing imported synthetic regressions and use explicit Python 3.11. |

The reconciliation preserves current-main pure-DESN article projection,
recursive mean-design, recursive DGP-oracle, and recursive score-packet test
registrations. It does not substitute historical source versions for main-side
JOINT modules or article assets. Current PriceFM and independent-model
surfaces are outside this source delta and are not replaced.

The staged whole-diff whitespace gate found one existing source trailing space
on line 442 of `application/scripts/434_finalize_glofas_search3_adoption.py`.
Only that terminal space was removed. The manifest marks the path
`manual_formatting_only`; source commit and source blob remain frozen. Python
tokens and scientific behavior are unchanged. Whitespace validation uses the
complete diff against the fresh main base, not merely the unstaged working
diff, and the coordinator repeats the staged gate after staging this fix.

The source registry covered 19 of the 35 imported executable test files.
Fifteen missing synthetic regression registrations were added, including the
fixed Dec-25 workflow, Part 2 forecast bridge, partitioned RHS solver,
quadrature/inner audit, exact structured exAL kernel, integrity launchers,
release controller, Search II schedulers, and Search III scheduler, stage-seal,
adoption, and dependency-closure tests. All 34 imported synthetic test files are
registered. Tests use synthetic fixtures and may exercise the audited kernels;
they do not regenerate the campaign authority.

The remaining file, `test_glofas_dec25_real_data_smoke.R`, is imported exactly
but deliberately not executed or registered. It reads real USGS/GloFAS inputs
and performs AL, exAL, and joint fits. The handoff's no-refit boundary prohibits
running it during this integration, even if a local input happens to exist.
Its execution requires a separately authorized development task.

The first combined harness run exposed test-namespace contamination, not an
inference regression. The newly registered standalone ensemble-likelihood test
assigns `cfg` to its Part 4 fixture; the later legacy forecast-contract test
expects `cfg` from the original point-bridge input-contract fixture. A second
combined run exposed another invocation mismatch: sourcing the standalone
quantile-integrity fixture executes its top-level `on.exit()` cleanup before
the next expression can save its synthetic temporary RDS files. The same
unchanged test passes when invoked as its intended standalone `Rscript`.

The registry therefore runs all 14 newly imported, self-bootstrapping R
fixtures sequentially as subprocesses using
`file.path(R.home("bin"), "Rscript")`. The five newly imported suite-loaded R
fixtures retain the harness bootstrap and run in isolated child environments.
All 100 current-main test registrations and their fixture dependencies remain
unchanged. Every test assertion and production implementation is preserved;
the manually reconciled registry and README integration-blob hashes are
refreshed. These changes repair only harness invocation and isolation, not
scientific fitting, inference, or publication behavior.

The focused imported-test batch also exposed a missing Python runtime
dependency. The pinned executable is Python 3.11.13, while the host default
Python is 3.6.8. An isolated temporary test environment supplies PyYAML 6.0.3,
pytest 8.3.5, pluggy 1.6.0, iniconfig 2.3.1, and packaging 26.3. The PyYAML
version agrees with the repository's recorded PriceFM runtime dependency.
Official PyPI artifacts were used, including a SHA256-verified pip 24.3.1
bootstrap wheel; no repository dependency, shared Python installation, or
scientific runtime directory was modified. The coordinator uses this same
temporary environment for the final combined harness.

The launcher-integrity test had one further fresh-worktree fixture omission:
the unchanged historical preparer expects a local-only selected-components
CSV. The test now supplies a temporary synthetic CSV through a scoped wrapper
for the `selected_components` import role. The expected historical source
pathname is asserted, and the original strict path-resolution, linking, and
SHA256 implementation performs the import. An added SHA256 assertion verifies
the imported fixture. The same unchanged preparer `main()` parses the declared
arguments and constructs the DAG; no generated fit or forecast command is
executed. All existing assertions remain intact. The manifest marks this
test-only change explicitly. No ignored production evidence is created in the
integration worktree, and no production script or frozen source blob changes.

## Direct review of high-risk scientific implementations

Every handoff-listed high-risk file was unchanged on current main relative to
the merge base. Exact source import is therefore an ancestry-preserving
modification, not replacement of concurrent main edits.

- `joint_exqdesn_exact_structured_inference.R`: the discontinuous diagnostic
  `inverse_gamma_limit` is excluded from the operative quadrature stopping
  norm by default. Its value remains stored, and
  `all_moment_relative_change` retains the unrestricted diagnostic. No
  likelihood, prior, ELBO, or posterior-target formula is changed. This shared
  helper is used by JOINT and historical PriceFM structured-VB callers, so
  synthetic regression and retained-asset publication checks are required;
  existing scientific outputs must not be regenerated.
- `latent_path_vb_al.R` and `latent_path_vb_exal.R`: optional, validated
  Gaussian driver priors and zero-weight future-Y working rows are explicit.
  Defaults retain the prior behavior when the option is absent. Fixed
  `zeta2` support distinguishes a fixed hyperparameter from learned scales.
  The exAL initializer preserves complete saved local-factor state.
- `latent_path_vb_joint.R`: complete same-tau local state is preserved across
  outer sweeps. A bounded inner RHS solver deepens the same coordinate map,
  checks release/response eligibility, and requires three consecutive
  full-state terminal passes.
- Scripts `381`, `386`, and `389`: executed manifests, validated driver
  priors, exact tau initialization, and hash-bound continuation govern the
  scientific workflow. Their source is imported for reproducibility; no
  scientific worker is invoked by article integration.
- `glofas_oracle_desn_forecast.cpp`: the only changes add state-norm and
  saturation diagnostics. Forecast formulas and RNG operations are unchanged.
- `test_joint_exqdesn_exact_structured_inference.R`: synthetic regression
  retains the diagnostic indicator while verifying its exclusion from the
  operative stopping norm.

The two distinct source scripts numbered `440` are preserved as their exact
frozen filenames. Subsequent projection scripts must use unused paths.

## Reconciliation verification and downstream gate

The reconciled registry parses successfully. The working diff passes
`git diff --check`, and all 128 exact-source blob comparisons pass.
Conflict markers are removed from the two conflicted working files. Only the
coordinator stages files and records the integration commit.

The focused imported synthetic regression coverage passes all 34 newly
registered test files: 22 completed successfully before the fresh-worktree
fixture omission was reached, and the final 12-file remainder passes with
known exit status zero after that repair. The repaired launcher test also
passes independently with exit status zero. The registry still contains all
100 current-main registrations, and all 134 integrated working-file hashes
match the audited manifest. This focused receipt does not replace the
coordinator's required final combined-harness successful exit.

Before article projection, the coordinator must run every handoff-mandated
focused test and the complete reconciled application harness, obtain known
successful exit statuses, and record them in the final integration report.
No test is weakened to obtain a pass. Retained JOINT/PriceFM publication
checks preserve unrelated scientific authority. Article projection, manuscript
builds, publication closure, stale-authority audit, and promotion remain
separate required gates; this note does not assert they have passed.
