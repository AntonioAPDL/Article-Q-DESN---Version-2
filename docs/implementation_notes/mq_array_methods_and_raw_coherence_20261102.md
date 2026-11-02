# MQ array methods and raw-grid coherence

This change supplies opt-in, source-only numerical building blocks. It does not
authorize reconstruction, accept an authentic shard, change posterior fitting,
change a score, or replace article results. The original scalar implementation
in `application/R/integrated_quantile_forecast.R` is unchanged. Existing batch
interfaces retain their defaults and their original return schema.

## Interfaces

After loading the native dependencies and `scripts/integrated_quantile_mq_batch.R`,
explicitly source `scripts/mq_forecast_array_methods.R`.

* `app_iqf_mq_batch_arrays(adapter, draw_id, origin_id, inner_ids)` returns
  `response[B,H]` and `ordered_quantiles[B,K,H]`, with `paths=NULL`. It does not
  allocate the unused nested path/kernel lists. Traces remain opt-in. Scientific
  inner IDs, draw/origin identities, response streams, observed-origin state,
  recursive updates, endpoint atoms, and equal-weight isotonic projection are
  unchanged. The new route uses the same `stats::isoreg` call after validating
  the common grid once in the adapter, rather than once for each crossed path.
* `app_iqf_mq_matrix_inverse(q, tau, probabilities, tolerance=1e-8)` accepts an
  `N` by `K` kernel matrix. Its event sweep, CDF-bracket checks, and exceptional
  numerical fallback reproduce the native common-grid mixture inverse. The
  fallback retains **unprojected** endpoints for the initial reference bracket;
  projecting those endpoints first can perturb the numerical bisection result
  within tolerance. No atoms, plateau rule, tail rule, or RNG law are replaced.
* `mq_coherence_merge(states)` merges complete **disjoint batches of the same
  original draw and origin**, rejecting overlaps and incompatible identities.
* `mq_coherence_weighted_summary(states, weights)` requires explicit positive
  normalized outer weights. First merge all batches within each member. The
  function averages each member's inner-path statistics and then applies its
  outer weight; it never weights a posterior member by how many integration
  paths happened to be needed for numerical precision.

The two hierarchy cases remain distinct: joint MQ uses each original correlated
posterior row; independent MQ uses only its previously frozen product-posterior
assembly. These helpers neither select nor alter a coupling. They integrate
response paths **conditional on one parameter draw**; they do not substitute a
pooled posterior-predictive quantile for a parameter-conditional quantile.

## Compact raw-coherence state

The schema is `mq_raw_kernel_coherence_v1`. Every horizon records adjacent-pair
crossing counts and exposures, positive-gap sums/maxima, and per-level absolute
and squared isotonic adjustments and maxima. These concern the **raw readout
before projection**, not the final integrated quantiles. The raw crossing rule
is `q[k]-q[k+1] > tolerance`; positive-gap magnitudes include every strictly
positive gap independently of the reporting tolerance. Values use the native
readout response scale, which must be named accurately in later public output.

Path ID intervals are compressed without dropping identity. State size is
independent of the number of inner paths except for the number of noncontiguous
ID intervals. Counts are exact; merged floating magnitude sums can differ at
roundoff because batch addition changes summation order. The tests compare
these sums at `1e-12`, not by a false bitwise-summation claim.

The weighted summary reports both the adjacent-pair rate matrix and its
uniform mean over the stated horizons/pairs. Any differently weighted horizon
or quantile-pair summary requires an explicit additional prespecified rule.
These are path-kernel diagnostics; they must not reuse the old 47,520
posterior-mean-grid denominator or be interpreted as guaranteed ordering of
unprojected draws. Integrated quantile grids are ordered by construction.

All method outputs retain `production_authorized=FALSE` and
`source_identity_authenticated=FALSE` where those fields apply. Compact
coherence validation is structural and arithmetic; it is not independent
proof of the origin of arbitrary matrices or a replacement for authenticated
source, stream, candidate, and validation receipts.

## Synthetic verification and reproducible profile

Use pinned R 4.6.0, one CPU and one numerical thread. The new test is
`application/tests/test_mq_forecast_array_methods.R`; the existing regression
is `application/tests/test_integrated_quantile_mq_batch.R`. Neither opens fits,
protected truth, or scientific runtime evidence. Cases cover randomized and
crossed grids, atoms/ties/plateaus, very narrow intervals, fallback parity,
all supported layer/activation/projection forms, horizon 30, arbitrary path-ID
ordering, both frozen RNG modes, traces and scalar paths, single-path/single-
horizon shapes, compact merge, unequal-resolution outer weighting, and
negative counter/identity/geometry tests.

The bounded profile is `scripts/profile_mq_forecast_array_synthetic.R`, using a
512-path, ten-horizon small synthetic reservoir. It prints operation timing,
result size, and an Rprof breakdown. These measurements are not a representative
authentic stress set or a whole-campaign ETA. Sample-to-sample timing variation
must be retained rather than turning a tiny matrix-inverse timing into a broad
speedup claim. The main assured advantage is avoiding large nested R lists.

On Muscat, pinned R 4.6.0, logical CPU 27, with OMP/OpenBLAS/MKL threads fixed
at one and each invocation under a 120-second timeout, the final new suite
passed 616 checks in 6.34 seconds (106,828 KiB peak RSS). The reference batch
suite passed 2,759 checks in 3.80 seconds (105,040 KiB peak RSS). The final
synthetic profile used 13.04 seconds (137,384 KiB peak RSS):

| Operation | Median wall seconds | Returned bytes |
|---|---:|---:|
| Reference path lists, 512 paths by 10 horizons | 0.720 | 4,675,000 |
| Array-only, without coherence | 0.536 | 333,408 |
| Array-only, with coherence | 0.539 | 342,736 |
| Build 512 kernel lists and invert seven probabilities | 0.008 | 112 |
| Matrix inverse of the same kernels | 0.005 | 112 |

Generation timings use three repetitions; inversions use twenty. The array
route with coherence returned about 13.6 times fewer bytes and was about 1.34
times faster on this small fixture. The 0.003-second inversion difference is
too small to establish a representative speedup. Inclusive Rprof samples
attribute about 40% to purpose-key hashing and 39% to `stats::isoreg`; inclusive
times can overlap and are not an additive cost decomposition. Larger authentic
reservoir matrices can have a different bottleneck.

## Source bridge and remaining gates

This change deliberately invalidates old exact `source_files` checks for the
batch helper. **Do not rehash an old purpose contract or reuse an old CLI to
label these bytes as the previously qualified baseline.** Existing historical
qualification receipts remain attached to their authentic old Git tree.

A new prospective qualifier remains to be implemented/reviewed. Its bridge
must authenticate the old batch Git blob and old qualification receipts;
authenticate all unchanged scalar, design, seed/RNG, and forecast-law closure
files; pin the new batch/helper/runner bytes and clean candidate Git tree;
repeat scalar, old-batch, array, CDF, inversion, and source-mutation checks;
and issue new typed receipts under a new external purpose and finite host/OS
budget. A prepared bridge or parity test alone must not return QUALIFIED.

The standalone MF01 numerical experiment is not production B07. Before any
authentic execution or production admission, complete independent precision
validation with frozen candidates and original split/alpha gates, actual
training-metadata-selected stress strata, production consumer/storage replay,
complete native-row inventory and weights, correct source/host grants, and
whole-inventory CPU/wall/storage/transfer pricing. No thinning, posterior-row
dropping, weaker error thresholds, changed coupling, old grants, or enlarged
unreviewed source guards are permitted to obtain acceptance.

The profile supports ranking future work, not immediately compiling a new
backend: authenticate unchanged serialized seed-purpose bytes first; profile
the actual source-compatible RNG hashing and isotonic/array loops; only then
consider a separately tested compiled implementation. Preserve both original
APIs as independent references and reject unsupported backends/designs rather
than silently falling back to a different scientific stream.
