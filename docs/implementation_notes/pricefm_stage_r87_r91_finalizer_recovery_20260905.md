# PriceFM R87-R91 Finalizer Recovery Contract

## Decision

Resume at R88. Do not rerun R87 and do not change any scientific threshold.
The 280-atom R87 homogeneous exAL refit completed cleanly on September 5,
2026. The downstream finalizer failed before importing R88 because it
dereferenced the PriceFM virtual-environment Python symlink and invoked the
system interpreter, which does not provide pandas. No R88 output, test access,
registry mutation, article mutation, joint fit, or MCMC fit occurred.

## Frozen completed evidence

| Evidence | Result |
|---|---:|
| R87 task terminals | 280/280 completed |
| R87 process failures | 0 |
| R87 hash/provenance audits | 280/280 passed |
| R87 atoms passing all frozen numerical gates | 243/280 |
| R87 formal convergence flags | 88/280 |
| R87 core-hours | 452.91 |
| Retained R83 atoms | 14 |
| Complete combined exAL surface | 294 atoms, 42 cases |
| Numerically eligible exAL cases | 32/42 |
| Numerical AL fallbacks | 10/42 |
| Additional AL-only cases | 14 |
| Provisional validation-only family split | 32 exAL, 24 AL |

All 32 eligible exAL surfaces have lower raw seven-quantile validation AQL
than their corresponding R73 AL surfaces. The provisional case-specific mix
reduces mean validation AQL from 6.846415 to 6.788610, a 0.844% reduction.
These values do not use test data and do not establish superiority over the
authoritative Q-DESN or cached PriceFM references.

Thirty-seven R87 atoms fail at least one frozen numerical gate. Thirty-six
exceed the first-state-step bound, one exceeds the tail-state bound, and one
exceeds the beta-norm-ratio bound, with one atom failing more than one gate.
The thresholds remain frozen. Six numerically ineligible cases have lower exAL
validation AQL, but they must still fall back to AL.

## Root cause and repair

The failed finalizer called `Path.resolve()` on
`application/data_local/pricefm/venv/bin/python`. Dereferencing that symlink
changed the command path to `/usr/bin/python3.11`; Python therefore lost the
virtual-environment prefix and R88 failed with `ModuleNotFoundError: pandas`.

The recovery preserves the executable path without dereferencing it and runs
an explicit environment probe before R88. The required environment is Python
3.11.13, NumPy 2.4.6, pandas 3.0.3, scikit-learn 1.8.0, PyYAML 6.0.3, and
joblib 1.5.3. The probe also requires `sys.prefix` to equal the PriceFM venv.
Any mismatch stops before test access. Every failure now writes a terminal
state with the failed stage, exception type, message, code commit, environment,
and whether test had been opened.
The recovery appends to a new recovery log; the original failed-attempt logs
remain unchanged as evidence.

## Resume sequence

1. Compile scripts 282-288 and run the focused R80/R90 test suites with the
   pinned PriceFM interpreter.
2. Commit and push the recovery on the dedicated PriceFM task branch.
3. Start the finalizer with explicit test-audit authorization and freeze its
   code HEAD.
4. R88 re-audits all 280 R87 and 14 R83 atoms and materializes the immutable
   294-atom closeout.
5. R89 selects one complete AL or exAL family per region/fold using raw
   original-scale validation AQL only. Test remains sealed during selection.
6. R90 regenerates validation and test designs, requires exact validation
   replay, scores stored beta means only, and removes heavy temporary design
   matrices. It performs no fitting or reselection.
7. R91 compares case-level seven-quantile test AQL with both authoritative
   Q-DESN and cached PriceFM. Promotion requires strict superiority to both,
   complete finite quantile and horizon diagnostics, validation replay, and
   all provenance gates.
8. R91 writes a read-only promotion queue and integration handoff. Registry
   and article changes remain the integration coordinator's responsibility.

## Stop conditions

- Never rerun R87 during this recovery.
- Stop before test if R88 or R89 differs from the audited 32-exAL/24-AL split.
- Stop if the pinned environment or code HEAD changes.
- Stop if validation replay fails for any R90 case.
- Do not relax numerical gates after seeing R87.
- Do not mutate registry, article, joint-model, or MCMC authority.

This is the minimum nonredundant path to complete the independent PriceFM VB
comparison while preserving validation-only selection and a one-time test
audit.

## Materialized recovery result

The repaired finalizer completed on commit
`bcbb71c5e57d5664bf517d9386e67bf61ea860a3`. R88, R89, R90, and R91 all
returned zero. R90 scored 56/56 cases with 20 workers, performed zero model
refits, and reproduced every frozen validation prediction within a maximum
absolute difference of `1.82e-12`. All 392 quantile metrics and 1,568
quantile-by-horizon-block metrics are finite and uniquely keyed. All four
source manifests re-hash without discrepancy, and R90 removed every temporary
validation/test design or response matrix after scoring.

R91 found 16 cases below authoritative Q-DESN, 30 below cached PriceFM, and 12
strictly below both. Eleven dual winners use repaired exAL and one uses AL.

| Case | Family | Candidate AQL | Q-DESN AQL | PriceFM AQL | Gain vs Q-DESN |
|---|---|---:|---:|---:|---:|
| IT_NORD fold 3 | exAL | 4.455446 | 4.584470 | 5.840089 | 0.129024 |
| SE_3 fold 1 | exAL | 7.563096 | 7.620994 | 7.628088 | 0.057899 |
| IT_CNOR fold 1 | exAL | 4.692527 | 4.723481 | 5.940016 | 0.030955 |
| DK_2 fold 2 | exAL | 6.314902 | 6.331814 | 8.251471 | 0.016913 |
| HU fold 1 | exAL | 7.871386 | 7.884141 | 8.500270 | 0.012755 |
| ES fold 1 | AL | 5.232137 | 5.243147 | 5.959308 | 0.011010 |
| DK_2 fold 3 | exAL | 7.407690 | 7.411013 | 9.368512 | 0.003323 |
| AT fold 1 | exAL | 6.739250 | 6.741377 | 7.402188 | 0.002127 |
| LV fold 3 | exAL | 12.838358 | 12.840327 | 13.756953 | 0.001969 |
| FR fold 3 | exAL | 5.719495 | 5.720239 | 6.817623 | 0.000743 |
| BE fold 2 | exAL | 6.396754 | 6.396922 | 6.496657 | 0.000167 |
| DK_1 fold 3 | exAL | 7.212994 | 7.213099 | 7.943293 | 0.000105 |

The complete 56-case candidate surface has mean test AQL 6.704209, compared
with 6.607637 for authoritative Q-DESN and 6.897056 for cached PriceFM. It is
therefore 1.462% worse than the current Q-DESN surface but 2.796% better than
PriceFM on the unweighted case mean. Replacing only the 12 registered dual
winners would change mean authoritative Q-DESN AQL from 6.607637 to 6.602869,
an improvement of 0.004768 or 0.072%.

The promotion queue is valid under the pre-registered strict ordering rule,
but effect sizes against Q-DESN are often small: six exceed 0.1%, three exceed
0.5%, and one exceeds 1%. Article prose must therefore describe targeted
case-level gains, not uniform or material global dominance. The strongest
new evidence is IT_NORD fold 3, followed by SE_3 fold 1 and IT_CNOR fold 1.
The smaller deterministic wins remain valid registry candidates but should not
be exaggerated as practically large improvements.

R91 is read-only. No registry, article, joint-model, or MCMC authority was
changed. The 12-row queue is ready for integration-coordinator review under
the existing case-specific promotion contract.
