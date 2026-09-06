# PriceFM Stage-R63 unified corrected-joint plan

Date: 2026-08-27

Lane: PriceFM only

## Frozen evidence

Stage-R62 completed all 42 missing individual quantile fits and froze an exact
seven-quantile validation authority for all 114 region/fold cells. There are no
coverage gaps or provenance conflicts. The corrected surface contains 12
existing joint validation wins, 65 joint losses no larger than 1%, 31 losses
between 1% and 5%, and 6 losses above 5%. AL is selected in 27 cells and exAL
in 87. Twenty-eight corrected selections differ from the family inherited by
R57; two of those are already joint wins and are protected from further fitting.

The old `112/114` claim remains superseded because it compared joint
seven-quantile AQL with median-only individual values. R62 is the replacement
validation authority. Test remained sealed throughout.

## Optimal bounded experiment

R63 does not seek one global specification and does not rerun all cells. It
contains 38 case-specific validation-only arms over 30 cells:

- 26 corrected-family replays for losing cells where R57 used the wrong AL/exAL
  family under the corrected seven-quantile selection contract;
- three mechanism arms for each of four severe same-family failures
  (`IT_NORD` fold 2, `IT_SARD` fold 2, `LT` fold 1, and `SE_2` fold 2): a
  parameterization-safe RHS start, a training-only independent-quantile
  initializer, and stronger cross-quantile innovation shrinkage.

The 12 current joint wins are excluded by a harm guard. Near and moderate
same-family losses are held because no specific mechanism currently justifies
another fit. The two severe corrected-family cases (`NO_4` fold 1 and `NO_5`
fold 2) receive the corrected-family replay first rather than a confounded grid.

## Selection and promotion gates

Each cell is selected independently using original-scale validation AQL. An R63
candidate must beat both its exact R62 independent authority and its existing
joint contract, pass source/config/checkpoint hashes, preserve all seven
quantiles, have zero contract crossing, and satisfy the declared stability
guard. A validation win does not mutate the registry or article and does not
open test automatically.

MCMC remains reserved for frozen validation winners. Test comparison against
both the current authoritative QDESN result and cached PriceFM occurs only after
the VB winner is immutable. Registry and article promotion require that later
confirmation to beat both references, plus reproducibility and hash-manifest
checks.

## Reproducibility wiring

R63 reuses the validated R61 joint runner and the CPU-pinned resumable launcher.
Every runtime config preserves its region/fold-specific information set and
DESN geometry from R57, changes only its preregistered mechanism, uses
train/validation splits, and points to the preserved PriceFM virtualenv.
Generated configs and runs remain in the historical runtime repository; code,
tests, and this decision record live on the dedicated PriceFM task branch.

No test, registry, manuscript, Overleaf, GloFAS, or validation-lane action is
authorized by this plan.
