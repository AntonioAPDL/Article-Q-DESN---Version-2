# GloFAS corrected hybrid-authority manuscript change specification

## Authority composition

- Keep every Search III Part 1-3 table, figure, selected specification and prior setting unchanged.
- Replace only the Part 4 display layer with the qualified October coherent target.
- Remove both active `glofas_same_family_20261103_display_aliases.tex` inputs.
- Add `tables/glofas_hybrid_part123_search3_part4_october_20261107_display_aliases.tex` after `glofas_application_current_outputs.tex` in both manuscripts.
- Keep November files in Git as adverse evidence; never use them for article claims or aliases.

## Main-text model correction

Replace the future-reference working-likelihood line in Eq. (GloFAS Part 4) with a frozen Gaussian path prior line:

```tex
\text{Future path prior:}\quad
\vect y_F\mid D_T\sim\Normal(\vect m_N,\mat C_N),
```

State that `(m_N, C_N)` is moment-matched from 500 truth-free recursive paths of the frozen Part 3 Normal-RHS driver. The path prior replaces, rather than multiplies, future-USGS AL/exAL factors. The 1,428 issued-member factors remain in the likelihood. Future USGS is scoring-only.

Replace the reported marginal-path-quantile equation with the frozen reporting rule:

```tex
\widehat q_{p,h}=\mathrm E_q\{q_{p,T+h}(\vect y_{F,1:h-1})\},
```

Describe this as the Monte Carlo mean reference-readout location over the shared Normal-driver path law, not as a quantile of the latent-path Gaussian factor and not as a credible limit.

## Results correction

Report Normal Ridge as the descriptive Part 4 leader (aCRPS 0.8429). Report Independent AL 0.9299, Normal RHS/VB 0.9463, MQ AL 0.9544, Independent exAL 1.0501 and MQ exAL 1.0875, versus raw GloFAS 1.4360. All corrected quantile families improve on raw GloFAS. Raw adjacent crossings are 1 for Independent AL and 0 for the other corrected families.

Do not claim that the issued-window scores selected the target, family, geometry, priors or stopping rules. The target correction follows from the pre-existing probability contract and truth-free root-cause audit.

## Supplement correction

In the Part 4 target, replace the product of future-USGS AL/exAL factors with `R_T(y_F)`, the frozen Gaussian driver prior. Set the reference-likelihood count to the historical reference count only; retain 12,455 + 28*51 issued/retrospective GloFAS contributions. Update the Delta description so the path precision combines the Gaussian prior and issued-member terms. Replace November crossing, inversion, negative-flow and runtime statements with the corrected tables in this packet.

## Discussion correction

Remove the statement that AL/exAL regressions fail to beat raw GloFAS. State instead that all six fitted corrections reduce grid aCRPS relative to raw GloFAS, with Gaussian ridge best on this one protected window, and that coverage remains imperfect. Preserve the single-origin limitation.

## Hard exclusions

- No November score, crossing, calibration, convergence or figure may remain active.
- No Search III Part 1-3 value may change.
- No final-window score may be described as model selection.
- No fit, continuation, retuning, crossing repair or spread calibration is authorized.
