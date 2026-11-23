# JOINT super-final predictive-stability continuation

Date: 2026-11-22

Branch: `work/joint-qdesn-superfinal-predictive-stability-20261122`

This continuation preserves the completed stronger-window campaign and reads
its ignored runtime as immutable evidence. It does not rerun screening, VB,
or DGP oracle generation. It targets only three joint MCMC score functionals:
Laplace parity exAL and persistent-heavy-tail challenger AL/exAL.

## Frozen source

- branch: `work/joint-qdesn-stronger-window-richer-screen-20261121`
- HEAD: `4381c14c50aa60de93eb952e3f67965bde9904f5`
- runtime: `application/cache/joint_qdesn_stronger_window_richer_screen_20261121`
- handoff-manifest SHA-256:
  `20ade34f91e08de24f213a532af994b6232aa7fffc5f62f08022291bc42fe277`
- transfer-inventory SHA-256:
  `213dc7f45004b0383db87054abf479200193b45056b64d461f2edc75a34f28d0`

Preparation fails closed unless those receipts and all 39 consumed source
artifacts verify. The source branch and runtime remain unchanged.

The source audit found chain-local recursive forecast excursions. Persistent
joint AL contains one chain-2 draw with DGP-integrated aCRPS 295.42 while its
median is 0.543. Persistent joint exAL contains a short chain-1 episode
peaking at 2.90. Laplace joint exAL contains a chain-2 episode peaking at
4.12. No draw is discarded or winsorized.

Five fresh chains are added to each exact unchanged posterior target. exAL
continues to use exact M0. The combined eight-chain score uses the frozen
oracle bank, quantile weights, recursive-mean-state policy, and model
specification. Predictive-functional gates, not perfect scalar mixing, decide
whether a row is stable.

## Frozen decision gate

The combined eight-chain score must be finite, have zero contract crossings,
rank R-hat at most 1.05, folded R-hat at most 1.10, bulk and tail ESS at least
100, relative score-mean MCSE at most 1%, leave-one-chain relative mean range
at most 2%, and maximum single-draw score share at most 1%. These gates target
the forecast functional implicated by the audit. They do not demand perfect
mixing of every scalar gamma, sigma, or coefficient coordinate.

The supplemental run preserves each posterior target, original chain budget,
frozen oracle bank, seven-level quadrature, and recursive-mean-state policy.
It neither trims excursions nor changes the DESN architecture or prior.

If both persistent joint rows stabilize, the complete challenger packet may
remain. Otherwise the entire persistent scenario falls back to
new-geometry parity. Model-specific packet splicing is prohibited. Article,
`main`, and Overleaf files remain untouched; only the super-final branch will
be offered for one final coordinator integration.

## Execution sequence

1. Verify the frozen receipts and reproduce the source influence audit.
2. Run five deterministic fresh chains for each of the three targets.
3. Verify exact-M0 dispatch for both exAL targets and one target hash per cell.
4. Recompute the three score functionals from all eight chains.
5. Apply the frozen predictive gate and complete-scenario fallback.
6. Freeze one 32-row packet, manifests, hashes, tests, and integration handoff.

No intermediate branch is to be integrated. The coordinator should review
only the final clean continuation branch after runtime closeout.

## Final result

All 15 supplemental chains completed without failure. The five AL chains
retained 750 draws each; the ten exAL chains retained 1,500 draws each and
used `M0_v_collapsed_support_logit`. Precision-repair jitter was at most
`1e-12`. A foreground smoke attempt was externally terminated before atomic
publication and produced no accepted artifact; worker 1 was subsequently
rerun from its frozen seed in the persistent launch.

Laplace joint exAL passed every predictive-functional gate after combining
the original three and five fresh chains. Its DGP-integrated score mean moved
from 0.3664 to 0.3615 while its median remained approximately 0.3585, with
rank/folded R-hat 1.014/1.010 and relative MCSE 0.78%.

Persistent-heavy-tail joint AL remained functionally unstable: its combined
mean was 0.5897 versus median 0.5425, relative MCSE was 57%, and the largest
draw contributed 8.3% of the total score. Joint exAL had stable mean influence
but folded R-hat 1.156 exceeded the frozen 1.10 ceiling. The predeclared
whole-scenario rule therefore retains all four persistent-heavy-tail parity
rows. No draw was removed and no model-specific splicing occurred.

The final packet has exactly 32 unique scenario-model rows, four models for
each of eight scenarios, finite scores, and zero canonical contract crossings.
The runtime finalizer reports
`SUPERFINAL_PACKET_READY_FOR_INTEGRATION_REVIEW`. This is a scientific and
reproducibility packet only; article assets, authoritative `main`, and
Overleaf remain unchanged.
