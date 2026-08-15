# Joint exQDESN Phase 176-180 Post-M0 Recovery

## Phase 178 completion and exact-M0 transition

The protected structured-VB feasibility screen completed all 126 planned rows
without worker failures. It retained 15 templates across five case-specific
model/scenario cells. These templates are feasibility survivors only: VB does
not select an article winner, and the article fixture remains excluded from
ranking. The next evidential stage is the frozen exact-M0 ranking packet of 180
chains (15 templates, three calibration replicates, and four chains per
template-replicate pair).

The Phase 178 and Phase 179 launchers use a completion-aware CPU lease queue.
Each audited CPU is assigned to at most one live child process and is returned
to the queue only after that exact PID terminates. This replaces cyclic CPU
assignment, which could place a new worker on a CPU still occupied by an
unusually slow predecessor. Worker-level resume checks, exit files, logs, and
failure packets remain unchanged.

Before an exact-M0 launch, operators must:

1. verify the Phase 178 VB audit and its artifact manifest;
2. verify the exact-M0 freeze, unique chain and component seeds, and the
   `M0_v_collapsed_support_logit` method contract;
3. supply a contemporaneously audited CPU list rather than an inferred range;
4. confirm that no article-fixture row can enter ranking; and
5. retain the selected-versus-parity protected confirmation as a separate
   phase after ranking.

## Production exact-M0 ranking launch

The production Phase 178 ranking packet contains 180 independently seeded
workers: 15 case-specific survivor templates, three protected ranking
replicates, and four chains per template-replicate case. Each chain uses
`M0_v_collapsed_support_logit`, 24,000 iterations, 4,000 burn-in iterations,
and thinning by four. The 45 structured-v initialization cases and all freeze
hashes must pass before sampling begins.

The launch is deliberately case-specific. Candidates compete only within the
same scenario and readout structure; no global DESN specification is selected.
VB evidence determines feasibility only. Exact-M0 functionals determine the
ranking, and a later fresh-seed selected-versus-parity stage determines whether
a candidate can replace the current article authority.

The August 15 production allocation uses 16 audited CPUs
(`19-24,31-39,60`) and leaves four otherwise free CPUs unclaimed. The lease
queue may reuse a listed CPU only after its registered child PID exits. A
resume relaunch reads the same immutable chain plan and allows the worker API
to reuse already completed checkpoints. Runtime artifacts remain ignored and
must not be interpreted as complete until the final health audit reports 180
completed workers, zero failures, and a verified ranking manifest.

Production preflight also requires schema-compatible candidate identifiers.
Structured initialization carries a transient `phase166_candidate_id`, whereas
the immutable M0 chain plan carries `phase178_template_id` and the historical
source `candidate_id`. Design construction therefore resolves identifiers in
that explicit order and is regression-tested without requiring the transient
VB field. This identifier affects provenance labels only; it does not alter the
frozen design specification, seeds, likelihood, prior, or sampler target.

Ranking prioritizes finite and stable posterior quantile-grid functionals:
fit and forecast oracle MAE, check loss, grid CRPS, raw and contract crossings,
and replicate stability. Scalar gamma and scale diagnostics remain supporting
evidence: review-level scalar mixing does not by itself disqualify a candidate
whose quantile functionals are stable, but functionally unstable candidates
cannot be promoted regardless of apparent point-metric gains.

## Scientific boundary

Phase 173 completed exact-M0 confirmation for all 16 exAL cells. Phase 173B
promoted 11 functionally qualified M0 rows and retained five historical rows
because the M0 posterior quantile functional remained unstable. Phase 174 is
the current article authority and is not modified by this recovery lane.

The recovery objective is performance-first. Scalar gamma or scale mixing may
remain review-level when posterior quantile-grid summaries are finite, stable
under independent chain allocations, and noncrossing after the declared
contract. A favorable subset of chains may never be selected.

## Correction to earlier screening authority

The exact-M0 sampler materially improved exAL posterior exploration. Therefore,
DESN and regularized-horseshoe `tau0` results obtained before M0 are not accepted
as final MCMC-era rankings. They remain useful candidate-region history, and
VB-only evidence remains useful for inexpensive pruning, but a new winner must
be ranked on protected replicates and confirmed with exact M0.

This does not imply that every old VB fit was numerically invalid. It means the
old VB-to-MCMC promotion decision cannot establish the best post-M0
specification.

## Phase 176: functional-mode audit

`application/scripts/240_audit_joint_exqdesn_phase176_post_m0_functionals.R`
performs no sampling. It verifies the Phase 171-175 source manifests, loads the
retained Phase 172 chain checkpoints, and audits exactly five held cells.

The audit adds evidence not supplied by Phase 173:

- all order-invariant chain-pair qhat distances rather than two fixed chain
  partitions;
- deterministic two- and three-cluster sensitivity;
- within-chain early/late qhat drift;
- instability localization by fit/forecast window and quantile level;
- gamma, sigma, actual-scale, alpha, and beta context for each qhat cluster;
- cluster-only and leave-cluster-out score sensitivity.

Oracle truth is not used to form clusters. It is used only after clustering to
describe the consequences of posterior chain allocation.

The output assigns one of two actionable states:

- `same_spec_additional_chains_eligible`: estimate posterior mode weights with
  new seeds before changing the model;
- `post_m0_spec_screen_required`: reopen case-specific DESN and `tau0`
  controls under the new inference era.

Hard implementation failure remains a separate terminal state in downstream
gates.

### Completed Phase 176 decision

The published Phase 176 artifact contains all five held cells and passed all
19 source and artifact hash checks after a metadata-only post-publication
integrity upgrade. Every cell was classified
`post_m0_spec_screen_required`; none was classified as a finite-chain-allocation
problem. Consequently, Phase 177 is deliberately skipped rather than run as a
generic increase in chain count. The five cells advance to Phase 178.

## Phase 177: same-spec exact-M0 confirmation

Only Phase 176-eligible cells may enter. The design uses 16 new chains, 48,000
iterations, 8,000 burn-in iterations, thinning by eight, unique hierarchical
seeds, one numerical thread per chain, compressed CSV checkpoints, and exact
missing-chain resume. The new packet is primary; the old eight-chain packet is
an external replication and is not silently concatenated.

Promotion requires a stable posterior-mean quantile functional, finite scores,
zero contract crossings, noninferior check loss and grid CRPS, and a metric gain
that is not explained by available chain-jackknife uncertainty. Scalar mixing
alone cannot fail a functionally stable result.

## Phase 178: case-specific post-M0 screening

This phase is conditional on Phase 176/177. It does not seek one universal
specification. Each unresolved scenario/readout cell receives its own small,
predeclared candidate neighborhood.

The search uses three evidence layers:

1. old pre-M0 results only to define plausible candidate ranges;
2. structured-v VB on calibration replicates for inexpensive pruning;
3. explicit exact-M0 confirmation for the surviving candidates before any
   winner is frozen.

Candidate dimensions are limited to controls that can alter the quantile
readout materially: direct versus previously supported deterministic DESN
feature maps, local `tau0` neighborhoods, finite-slab scale where justified,
and a low-dimensional quantile-specific intercept-prior schedule. Gamma kernel,
slice-width, fixed-gamma, and broad sampler-method screens are excluded because
Phases 128-170 already addressed them.

The article fixture is excluded from candidate ranking. Calibration and
confirmation replicate IDs and seeds are frozen before fitting. If retained
Phase 153 replicates have been exposed to materially equivalent candidates,
new fixed-seed fixtures are required rather than relabeling them as untouched.

The frozen production design contains 21 case-specific candidate templates:
four templates for each held cell, plus one additional compact hybrid template
for the independent regime-shift cell. Forty-eight fresh protected DGP rows
cover four unique mechanisms, six calibration replicates, three ranking
replicates, and three confirmation replicates. This yields 126 structured-v VB
candidate-replicate rows. VB is used only for feasibility and coarse pruning;
the surviving candidates are ranked and confirmed with exact M0.

The authority rule is explicit: pre-M0 MCMC-era DESN and `tau0` rankings are
not valid winner evidence after the M0 sampler correction. Their numerical
values can define local neighborhoods, and old VB results can inform
feasibility, but no new exAL candidate can be selected or promoted without
fresh protected exact-M0 evidence.

## Phase 179-180 boundary

At most one winner per cell receives a full exact-M0 article-fixture
confirmation. Qualified replacements are then recomposed into a 32-row packet
while preserving every unaffected Phase 174 row byte-for-byte. Article-safe
assets are staged with hashes, but this task branch never merges `main` or
publishes Overleaf. The integration chat performs that work from a frozen
handoff.

## Reproducibility

All phases write CSV, README, provenance, and SHA-256 manifests. No `.RData`,
`.rda`, or `.rds` workspace is retained. Tests cover exact five-cell scope,
chain-order invariance, draw-half correctness, truth-free clustering, manifest
verification, seed uniqueness, protected-data separation, and the requirement
that every new winner receive exact-M0 confirmation.

The implementation runs each M0 chain as an independent single-threaded worker
with globally unique chain and latent-component seeds. Launchers require an
explicit audited CPU list, support missing-worker resume, and keep fixture,
initialization, worker, result, and audit manifests separate.

## Gated execution sequence

Run each launcher only after the preceding checker has published a verified
audit artifact. `CPU_LIST` below denotes a comma-separated list of CPUs checked
against the live process table immediately before launch.

1. Launch structured-v feasibility:
   `JOINT_EXQDESN_PHASE178_VB_CPU_LIST="$CPU_LIST" bash application/scripts/249_launch_joint_exqdesn_phase178_vb_screen.sh`.
2. After its final health audit passes, launch protected exact-M0 ranking:
   `JOINT_EXQDESN_PHASE178_M0_CPU_LIST="$CPU_LIST" bash application/scripts/253_launch_joint_exqdesn_phase178_m0_ranking.sh`.
3. After one candidate per cell is frozen, launch protected confirmation:
   `JOINT_EXQDESN_PHASE179_CPU_LIST="$CPU_LIST" bash application/scripts/256_launch_joint_exqdesn_phase179_protected_confirmation.sh`.
4. Only qualified candidates enter the frozen article realization through
   `application/scripts/259_launch_joint_exqdesn_phase179_article_confirmation.sh`.
5. Build the recomposed packet and review-only article assets with
   `Rscript application/scripts/260_build_joint_exqdesn_phase180_recovery_handoff.R`.

The Phase 178 fixture, fit, and orchestration directories are runtime evidence
under `application/cache/` and remain excluded from git. Tracked source code,
policies, tests, and this note live on the dedicated scientific branch. The
Phase 180 handoff, rather than this branch itself, is the publication boundary.

## Verification commands

The implementation boundary is checked with:

- `Rscript application/tests/test_joint_exqdesn_phase176_180_post_m0_recovery.R`;
- `Rscript application/tests/test_joint_exqdesn_exact_structured_inference.R`;
- `Rscript application/tests/test_joint_exqdesn_inference_dispatch.R`;
- `Rscript application/tests/test_joint_exqdesn_phase164_166_orchestration.R`;
- `Rscript application/tests/test_joint_exqdesn_phase170_default_promotion.R`;
- `Rscript application/tests/test_joint_exqdesn_phase171_175_article_confirmation.R`.

The production preflight must additionally resolve exactly five target cells,
21 templates, 48 protected DGP rows, and 126 VB candidate-replicate rows before
fixture generation begins.
