# Phase163 case-specific upper-tail calibration

> **Superseded decision rule (2026-08-06).** The worker artifacts remain valid, but the original promotion audit compared VB/VB-LD candidates with MCMC article rows and omitted its documented `tau = 0.95` gate. Use the inference-matched Phase163b closure in `joint_exqdesn_phase163b_corrected_closure_20260806.md` for all promotion decisions.

Phase163 responds to the Phase162 finding that the five unresolved Joint exQDESN cases are dominated by negative upper-tail bias, especially at tau 0.95. It launches twenty new direct-readout VB/VB-LD candidates: four coordinated prior combinations for each scenario. Exact Phase149/151 control duplicates are prohibited.

The campaign does not rerun AL models, existing article rows, successful exAL cases, generic reservoir designs, split-RHS variants, sampler widths, fixed-gamma sensitivity, or MCMC. Existing article MCMC rows are frozen comparators.

Candidates advance only if they pass implementation and crossing gates, improve forecast oracle MAE by at least max(0.0025, 2.5%) relative to the current article exAL row, and keep check-loss deterioration below 1%. MCMC is a later independent-confirmation stage, not part of Phase163.

```bash
bash application/scripts/213_launch_joint_exqdesn_phase163_tail_calibration.sh
Rscript application/scripts/214_check_joint_exqdesn_phase163_tail_calibration.R
```
