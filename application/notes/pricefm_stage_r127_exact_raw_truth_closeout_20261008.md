# R127 Exact-Raw-Truth Closeout

All 82 R127 diagnostic tasks completed successfully on Jerez using scientific
HEAD `e62331f11169cddf01d81a7dfba10b33176af25b`, with 15 physical-core workers.
The automatic report correctly refused a mismatch with the frozen reference.
The root was scoring truth, not a failed fit or failed recursive forecast.

The stored forecast-array truth had passed through an outer float32 transform
and two-stage inverse. R126's matched comparison instead uses exact raw BG
prices from FINAL.csv. Quantization changed AQL by about 2-3 billionths:

| Fold | Stored-Truth AQL | Exact-Raw-Truth AQL | Frozen Comparison |
| --- | ---: | ---: | ---: |
| 1 | 10.331240356537602 | 10.331240358679489 | 10.331240358679487 |
| 2 | 8.128371043200934 | 8.128371040031741 | 8.128371040031741 |
| 3 | 10.005795180194454 | 10.005795177365538 | 10.005795177365538 |

Maximum stored-truth roundtrip errors were 1.43e-5, 1.27e-5 and 2.07e-5
EUR/MWh. They explain the mismatch completely. This is a reporting provenance
correction, not a material performance improvement or a posterior-target change.

Do not relax the tight AQL identity gate, rewrite the old blocked receipt,
relaunch any model, or regenerate any forecast. A dedicated closeout branch
reads and verifies the exact executed source, preparation, input and task hashes,
uses exact raw prices at the validated quarter-hour response times, and writes
a new sealed report under `runtime_audits/pricefm_stage_r127_driver_diagnosis_20261008/`.
It records scientific and report-only HEADs separately. The original R127
worktree, branch, protocol, forecasts and controller error evidence remain frozen.

Entrypoint: `451_closeout_pricefm_stage_r127_driver_diagnosis.py --output ...`.
Only the report, report-only entrypoint, tests and these notes change. The
forecast algorithm, fitted parameters, priors, initialization and saved data
are unchanged. The executed release remains 518 Python tests plus four R
suites on both hosts. Focused additional closeout tests cover exact raw-clock
alignment, raw-source hashes, nonzero quantization discrepancies, independent
report destinations and preservation of the completed producer evidence.
No inference campaign or repeated broad fitting regression is necessary for
this narrow postprocessing correction.
