# JOINT Laplace Coupling Recovery Integration Handoff

Date: 2026-10-08

Integration state: `READY_FOR_INTEGRATION`

Article-result state: `NOT_READY_FOR_ARTICLE_PROMOTION`

This handoff closes the targeted Laplace Bridge coupling-recovery lane. The
integration coordinator owns merging into `main`, combined-tree testing, and
any article or Overleaf action. This lane must not perform those actions.

## 1. Lane Identity

| Field | Value |
|---|---|
| Lane | JOINT Laplace Bridge fixed-backbone prior/coupling experiment and schema-safe recovery |
| Transcript | `/home/jaguir26/.codex/sessions/2026/10/08/rollout-2026-10-08T01-40-00-01a11a06-8f9c-7100-9169-118f69b79875.jsonl` |
| Muscat worktree | `/data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_laplace_coupling_recovery_20261007` |
| Jerez worktree | `/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_laplace_coupling_recovery_20261007` |
| Branch | `work/joint-qdesn-laplace-coupling-recovery-20261007` |
| Upstream | `origin/work/joint-qdesn-laplace-coupling-recovery-20261007` |
| Scientific execution HEAD | `1afa983ec28c2ff858572a288378aa4629a75bf9` |
| Origin main at final audit | `e2a3be97853b1af9c8cb269a3e065336ca5590f3` |
| Merge base | `e721bfddee81269864febea0eca0bbd0c5eba369` |
| Relationship before this handoff commit | 4 task commits ahead, 49 main commits behind |

The commit containing this handoff follows the scientific execution HEAD. Use
the current remote branch tip as the merge target after fetching; do not merge
the old execution HEAD by itself.

## 2. Unique Commit Sequence

| Commit | Subject |
|---|---|
| `199ed8f0bb7a947c0a51800c466f9c458f25f238` | Add fixed-backbone JOINT prior screen and fresh confirmation workflow |
| `80e2c887188071349395d2784a42fef7f08e7033` | Add bounded training-calibrated JOINT Laplace coupling experiment |
| `e9a1a68ad17cc16a10763286969583ed3da381af` | Add targeted JOINT Laplace coupling recovery |
| `1afa983ec28c2ff858572a288378aa4629a75bf9` | Resume JOINT coupling recovery safely |

These four commits form one dependency-ordered stack and should be reviewed and
merged together. Current `origin/main` contains none of their 23 pre-handoff
task paths, so no partial cherry-pick is recommended.

## 3. Exact Tracked Change Scope

```text
application/R/joint_qdesn_fixed_backbone_prior_screen.R
application/R/joint_qdesn_laplace_coupling.R
application/R/joint_qdesn_laplace_coupling_recovery.R
application/config/joint_qdesn_fixed_backbone_prior_contract_v1.csv
application/config/joint_qdesn_laplace_coupling_contract_v1.csv
application/config/joint_qdesn_laplace_coupling_recovery_contract_v1.csv
application/scripts/_joint_qdesn_fixed_backbone_prior_bootstrap.R
application/scripts/_joint_qdesn_laplace_coupling_bootstrap.R
application/scripts/_joint_qdesn_laplace_coupling_recovery_bootstrap.R
application/scripts/joint_qdesn_fixed_backbone_prior_capacity.R
application/scripts/joint_qdesn_fixed_backbone_prior_screen.R
application/scripts/joint_qdesn_laplace_coupling.R
application/scripts/joint_qdesn_laplace_coupling_capacity.R
application/scripts/joint_qdesn_laplace_coupling_recovery.R
application/scripts/launch_joint_qdesn_fixed_backbone_prior_screen.sh
application/scripts/launch_joint_qdesn_laplace_coupling.sh
application/scripts/launch_joint_qdesn_laplace_coupling_recovery.sh
application/tests/test_joint_qdesn_fixed_backbone_prior_screen.R
application/tests/test_joint_qdesn_laplace_coupling.R
application/tests/test_joint_qdesn_laplace_coupling_recovery.R
docs/implementation_notes/joint_qdesn_fixed_backbone_prior_screen_20261005.md
docs/implementation_notes/joint_qdesn_laplace_coupling_20261006.md
docs/implementation_notes/joint_qdesn_laplace_coupling_recovery_20261007.md
docs/implementation_notes/joint_qdesn_laplace_coupling_recovery_integration_handoff_20261008.md
```

No article, Overleaf, PriceFM, GloFAS, Phase182, or independent-lane file is in
scope. Runtime and `local_trackers/` remain ignored.

## 4. Run Inventory

| Stage | MCMC workers | Score cells | Failures | Status |
|---|---:|---:|---:|---|
| Fixed-backbone source screen | 32/32 | 16/16 | 0 | complete |
| Supplemental AL adjudication | 6/6 | 3/3 | 0 | complete after schema-safe continuation |
| Fresh protected exAL confirmation | 18/18 | 6/6 | 0 | complete |
| Total | 56/56 | 25/25 | 0 | closed |

All 18 confirmation chains use `M0_v_collapsed_support_logit`, contain 1,500
finite retained draws, and match target hashes within cell. All six score rows
are finite, all functional checks pass, and forecast contract crossings are
zero. No JOINT recovery worker, launcher, or finalizer remains active.

## 5. Scientific Result

The relaxed exAL innovation slab failed protected confirmation:

| Model | Mean score | Mean 95% width | Canonical score | Raw crossings |
|---|---:|---:|---:|---:|
| Independent exAL | 0.405934 | 0.065639 | 0.395803 | 3,360,412 |
| Joint exAL baseline | 0.486456 | 0.202751 | 0.476564 | 117,224.5 |
| Joint exAL relaxed slab | 0.489506 | 0.210895 | 0.479350 | 118,033 |

The relaxed arm is 0.627% worse than the joint baseline in mean score and its
interval is 4.017% wider. It improves neither protected replicate. The joint
arms reduce raw crossings by about 96.5% relative to independent exAL, but have
worse predictive scores and intervals roughly three times as wide. Clean score
and functional diagnostics show that this is not a residual gamma/sigma mixing
failure. The frozen decision is `retain_baseline_review`.

AL remained blocked under its original contract because baseline maximum
functional R-hat was 1.544426 against the frozen 1.5 gate. The eligible
conditional-variance arm improved the internal mean by 0.003037, but this lane
correctly did not weaken the gate or force confirmation.

## 6. Evidence and Hashes

Jerez authoritative runtime:

```text
/data/jaguir26/local/src/Article-Q-DESN---Version-2__wt__joint_laplace_coupling_recovery_20261007/application/cache/joint_laplace_coupling_recovery_continuation_20261007
```

- size: 537 MiB;
- completion marker: `COMPLETE_READY_FOR_SCIENTIFIC_REVIEW`;
- complete draws, models, manifests, and logs remain on Jerez.

Muscat compact review packet:

```text
/data/jaguir26/local/src/Article-Q-DESN/.codex_work/joint_laplace_coupling_recovery_20261007/application/cache/joint_laplace_coupling_recovery_continuation_20261007
```

- size: 280 KiB;
- copied from Jerez after completion;
- closeout manifest entries: 7/7 verified by size and SHA-256;
- `freeze_manifest.csv`: `63b4fd039e6851f52520db48b56b8de00492c3da974d85c90402c26cd5ef6abd`;
- `source_evidence_manifest.csv`: `c6cb68dc84ba7f77d03afc9ea801cc51375cdbebb14de98688fe600defb82bf3`;
- `predecessor_import_manifest.csv`: `54af0a34d29c25c455543865138427ce20da774b665b62c6e19dcd3c6ad97aa6`;
- `screen/selection_manifest.csv`: `faffcb4ddc3e0f3dde8ffd52e65a93e15a7b752d1a32916369ff494fce681f96`;
- `confirmation/plan_manifest.csv`: `1daef1d1dc5bd2fd5674242150b301a2392fca9f0a337a80deeba308e73ab973`;
- `closeout/artifact_manifest.csv`: `5f0fb6e3678287c69b4dd9eb0a0d32ab8ec802ead9b346f0357e78edcd35cbd4`.

The seven closeout payload hashes are recorded in the closeout manifest. Key
payloads include `confirmation_scores.csv` at
`54a24582117b628685be1921d6caa7414b544b3ac848d637cdc5e6989239f1a4`
and `decisions.csv` at
`37260054b73e14b878daee4cee79bc185726e1e9d5ee9f317706fa101fb3f1ec`.

## 7. Verification

The scientific lane passed:

```bash
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  application/tests/test_joint_qdesn_fixed_backbone_prior_screen.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  application/tests/test_joint_qdesn_laplace_coupling.R
/data/jaguir26/local/opt/R/4.6.0/bin/Rscript --vanilla \
  application/tests/test_joint_qdesn_laplace_coupling_recovery.R
bash application/tests/test_joint_exqdesn_cpu_queue.sh
bash -n application/scripts/launch_joint_qdesn_fixed_backbone_prior_screen.sh
bash -n application/scripts/launch_joint_qdesn_laplace_coupling.sh
bash -n application/scripts/launch_joint_qdesn_laplace_coupling_recovery.sh
git diff --check
```

The compact Muscat packet was independently checked for its completion marker,
all 7 closeout hashes and sizes, exact stage counts, six finite score rows, zero
contract crossings, and the frozen `retain_baseline_review` decision.

## 8. Integration and Article Boundaries

The coordinator may integrate the reproducibility code, contracts, tests,
scientific closeout, and negative-result evidence. There is no article-safe
replacement table or figure in this lane. Do not replace current article values,
publish the protected confirmation, or present the relaxed slab as a winner.

Keep excluded from Git and Overleaf:

```text
application/cache/joint_laplace_coupling_20261006/
application/cache/joint_laplace_coupling_recovery_20261007/
application/cache/joint_laplace_coupling_recovery_continuation_20261007/
local_trackers/
```

Retain the full Jerez runtime until integration and any AL follow-up decision
are complete. The compact Muscat packet is review convenience, not a replacement
for the full draw archive.

## 9. Risks and Next Scientific Step

- Current `origin/main` is 49 commits ahead of the lane merge base; integration
  must start from fresh `origin/main` and rerun focused tests after merging.
- The result is one protected scenario and is not universal evidence about all
  joint models or all priors.
- Posterior intervals overlap; numerical differences remain descriptive.
- Joint exAL's coherence gain is real but does not compensate for its worse
  protected predictive score in this confirmation.
- The AL conditional-variance candidate is the only untested bounded follow-up
  supported by the screen. It must be a separate prospective experiment after
  integration, not an amendment to this frozen phase.

Recommended order:

1. Fetch the dedicated branch and create an integration branch from current
   `origin/main`.
2. Merge the complete four-commit stack plus this handoff commit.
3. Confirm the 24-file task scope and run the focused tests above.
4. Verify the compact packet hashes and preserve the Jerez runtime path.
5. Integrate code and evidence only; do not modify article assets.
6. If desired, create a new dedicated AL-confirmation branch from the resulting
   main and freeze its review-level baseline policy before any launch.

## 10. Final Declaration

`READY_FOR_INTEGRATION`

The implementation and audited evidence are complete, clean, reproducible, and
appropriate for coordinator integration.

`NOT_READY_FOR_ARTICLE_PROMOTION`

The tested exAL challenger failed protected confirmation, so this lane supplies
no replacement article result.
