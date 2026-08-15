# Joint exQDESN Phases 148-149 case-specific calibration

## Decision

Phases 148-149 return the validation workflow to its primary objective:
scenario-specific model performance. Phase147 showed that improving sampler
acceptance did not improve the full Student-t quantile grid. Another broad
sampler screen is therefore not justified.

Phase148 is a small software-correctness gate. It verifies that the implemented
joint sigma-gamma target agrees with the established GIG sigma and slice gamma
conditionals, up to additive constants. A fixed-state numerical grid provides
an additional check of the conditional refresh transition.

Phase149 prepares 12 independent Joint exQDESN VB/VB-LD candidates for each of
the eight formal scenarios. It does not seek a global specification and does
not rerun AL.

## Scope

The formal simulation fixtures freeze the deterministic design matrix used by
the validation model. Consequently, Phase149 screens the controls exposed by
the validated fit/forecast pipeline:

- RHS global shrinkage (`tau0`);
- finite readout cap (`zeta2`);
- ordered-intercept prior scale;
- gamma initialization basin;
- VB/VB-LD effort and RHS coordinate passes.

It does not claim to screen reservoir architecture. Such a study would require
a separately versioned design-fixture layer rather than adding unused columns
to the existing registry.

## Commands

```bash
Rscript application/tests/test_joint_exqdesn_phase148_target_invariance.R
Rscript application/scripts/160_run_joint_exqdesn_phase148_target_invariance.R
Rscript application/tests/test_joint_exqdesn_phase149_case_specific_screening.R
Rscript application/scripts/161_prepare_joint_exqdesn_phase149_case_specific_screening.R
bash application/scripts/162_launch_joint_exqdesn_phase149_case_specific_screening.sh
bash application/scripts/164_finalize_joint_exqdesn_phase149_case_specific_screening.sh
```

The parallel launcher uses 12 single-threaded workers by default. Each scenario
has its own reference rows and local perturbations. Selection occurs within
scenario after the complete screen. Only two or three stable candidates per
scenario should proceed to eight-chain MCMC confirmation.

The detached finalizer waits for all worker sessions, verifies their exit
codes, builds the canonical Phase106 audit, and writes the Phase149
scenario-specific ranking and shortlist. It deliberately does not launch MCMC.

## Gates

Hard fail:

- any Phase148 conditional-target identity failure;
- source-manifest failure;
- malformed or duplicate candidate registry;
- nonfinite fit or forecast summaries;
- contract crossings or worker failures.

Review:

- VB/VB-LD iteration limit;
- raw crossings repaired by the declared monotone contract;
- candidate instability across initialization basins;
- performance gains smaller than the predefined practical tolerance.

No manuscript table should change from VB/VB-LD screening evidence alone.
