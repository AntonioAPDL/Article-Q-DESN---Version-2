# Post-seal GloFAS scoring-truth interface

This source supplies a missing data interface, not a new model or a scientific
result. The actual scoring-only sidecar remains unopened while the last
same-family fit is running. All tests use generated values and temporary Git
fixtures. No actual extractor, finalizer, scorer or publisher was run.

## Why a separate interface is needed

The retained source constructs `part4_scoring_panel_sidecar.rds` as a list
with `panel`, `role`, `future_truth_used_in_fit` and `future_truth_rows`.
Its panel has only `target_date,y_transformed`; it has no horizon column.
This construction is visible in
`application/scripts/386_run_glofas_part4_latent_family_job.R`. The separately
frozen original identity is 862 bytes, SHA-256
`24be9fa631bca346a04a7a855bff5ef3ebc7bf5c748fbade7a213d88fdfe63e6`.
The earlier reused-source manifest records that identity. No actual RDS read
was needed to establish the written schema or this recorded provenance.

The new scorer expects a 28-row CSV with
`target_date,horizon,y_transformed`. Neither an unverified export nor the old
eighteen-fit finalizer is a compatible substitute. The old finalizer's
quantile models have zero same-family future-response factors; the current
sixteen-fit authority instead has 28 such factors per level.

## Required order

1. Finish all sixteen corrected producers, with zero active, failed or
   ambiguous attempts, closed supervisor accounting and the complete cohort
   receipt. Create and pin a SQLite-consistent quiescent snapshot separately;
   do not copy or checkpoint the active WAL database blindly.
2. Use the new read-only producer collector and truth-free plotting-input
   extractor. Authenticate the existing analytic Normal reports and all
   51 issued members on each of the common 28 dates.
3. Run `finalize_glofas_same_family_transition.R --mode assemble` under its
   own finite purpose. This creates exactly 1,372 forecasts, seven raw
   crossing summaries and the original `FORECAST_SEAL.json` (seal A), without
   opening USGS scoring truth.
4. Admit `glofas_same_family_truth_bridge.R` under a **new external purpose**.
   It verifies the complete assembly manifest, decision and seal A, including
   all sixteen accepted producer identities and all forecast/input hashes,
   before opening the original scoring-only RDS. It reads that RDS once,
   validates its source schema, and matches every retained date to the sealed
   28-date issued window. A complete 30-date source may be reduced by those
   explicit keys; it is never truncated by row position. No additional log
   transformation is applied.
5. The bridge writes `scoring_truth.csv`, `TRUTH_DERIVATION.json`, the exact
   `TRUTH_PURPOSE.json`, a progress receipt and a hash manifest in a fresh
   ignored output directory. Failures retain their phase, attempted/completed
   RDS-read counts and partial manifest; they are not overwritten or retried.
6. Run score mode with `truth_interface_version` explicitly set to
   `authenticated_truth_bridge_v2`. It constructs its own forecast seal B
   and requires B's three forecast-artifact hashes/sizes, all sixteen producer
   bindings and all five truth-free input bindings to equal seal A. The
   approved original RDS/provenance identity, producer source/purpose and
   derived CSV pin must agree before the CSV is read. The exact CSV and both
   provenance files are retained in the scored packet.
7. The independent packet/projector checker repeats the A/B comparison,
   source/purpose/provenance checks and exact retained-CSV check before
   accepting numerical summaries. Recomputing an output manifest after
   changing a forecast, scoring CSV, derivation or original seal cannot hide
   the change.

The explicitly named `legacy_pinned_csv_v1` interface remains available for
already legitimate, separately pinned CSV inputs. Missing version fields in
historical purposes/packets are interpreted as this original v1 interface;
new purposes should always specify the version. This compatibility does not
authorize an arbitrary RDS conversion to bypass the new v2 derivation.

## Bridge command and contract

Entry point, only after a separately issued purpose and resource grant:

```bash
Rscript --vanilla scripts/glofas_same_family_truth_bridge.R \
  --contract /PRIVATE/NEW_APPROVED_PURPOSE.json \
  --sha256 APPROVED_PURPOSE_SHA256 --execute
```

The purpose schema is `glofas_same_family_truth_bridge_contract_v1`:

```text
mode = extract_scoring_truth_after_forecast_seal
allow_truth_read = true
allow_refit = allow_retuning = allow_forecast_changes = allow_publication = false
truth_role = post_fit_scoring_only
source_commit, source_tree = exact clean committed bridge source
source_files = exact bridge, closeout algebra, and source-constructor file pins
assembly_root, assembly_manifest, assembly_forecast_seal = exact pre-truth A pins
truth_rds = exact frozen original 862-byte scoring-sidecar pin
truth_provenance_manifest = original reused-source-manifest pin
output_root = new ignored child under the source worktree's local_trackers
expires_utc = full bounded UTC lifetime
limits = cpu_seconds, wall_seconds, memory_bytes, output_bytes, logical_cpu
```

The bridge requires native vanilla R 4.6.0 on Muscat, one numerical thread,
no `LD_PRELOAD`, finite OS limits, and a native TERM/KILL supervisor sharing
the R process's CPU, process group and session. CPU and wall budgets agree
(10--120 seconds), with at most 2 GiB address space and 8 MiB output. The
supervisor's TERM time is wall minus one second and KILL-after is one second.
These source ceilings are not a live resource grant. Administrative setup
and terminal accounting must be priced separately. Protected fitting cores
and siblings remain excluded.

For v2 score mode, add these pins/bindings to the existing closeout purpose:

```text
truth_interface_version = authenticated_truth_bridge_v2
truth = approved derived scoring_truth.csv pin
truth_rds, truth_provenance_manifest = original authenticated identities
truth_derivation, truth_adapter_purpose = exact bridge output/purpose pins
assembly_root, assembly_manifest, assembly_forecast_seal = original A identity
```

The scored `DECISION.json` records those bindings and the interface version.
The v2 scored-packet manifest additionally contains `TRUTH_DERIVATION.json`
and `TRUTH_PURPOSE.json`. All other score definitions, family/date/quantile
membership, uncertainty labels and crossing/coverage disclosures are unchanged.
The finalizer now sources the bridge helper, so every new finalizer purpose
must include that transitive source pin, including extract/assemble modes.

## Acceptance and remaining work

The focused truth-bridge tests exercise the source schema, keyed 28/30-date
selection, callback/field rejection, immutable RDS identity, finite purpose
limits, native timeout process groups, original assembly/seal membership,
actual source-file verification in a temporary Git repository, valid v1/v2
interfaces, A/B forecast equality, and independent scored-packet checks.
They reject changes to the original seal after extraction, a resealed B with
changed forecasts, and resealed output packets with altered truth or proof.
They perform **zero retained truth-RDS reads and zero scientific runs**.

Actual use still requires all sixteen completed producers, a sealed ledger
snapshot, authenticated issued-member/history extracts, external purposes,
fresh resources and source-bound execution receipts. The v2 adapter does not
turn incomplete fits into accepted results and does not select the best model.
The recorded MQ--AL raw crossing count (43/168) must remain in the complete
comparison rather than being projected away.

The article candidate projector remains candidate-only. Authentic fitted
historical quantile curves, reviewed vector figures, a coherent seven-family
table/alias/prose replacement, manuscript builds, section-authority review
and direct-Git publication remain separate gates. The new raw/history
extractor provides historical observations and issued members, not fitted
historical quantile curves. No release follows solely from these tests.
