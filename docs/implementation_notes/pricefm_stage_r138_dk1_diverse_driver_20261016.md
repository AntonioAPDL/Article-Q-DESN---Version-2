# PriceFM R138 DK_1 diverse receiver and driver confirmation

R138 is a bounded developmental continuation of the completed R134/R135 DK_1 work. It does not repeat the 640-candidate Ridge screen or the 30-structure Normal RHS screen. The defect being corrected is selection breadth: both R134 seven-quantile finalists used the same reservoir architecture at two `tau0` values.

## Scientific question

Can a structurally different pure Q-DESN receiver, optionally paired with a different Normal RHS recursive driver, improve DK_1 relative to the frozen R135 receiver-driver pair when selection uses only the three internal rolling validation splits?

## Design

1. Verify the exact sealed R134/R135 source, manifests, hashes, candidate specifications, and Normal RHS fits.
2. Collapse the R134 RHS ranking to one best `tau0` per unique architecture.
3. In Wave 1, fit all seven AL quantiles for the first six unique receiver architectures.
4. Score each receiver against three predeclared Normal RHS drivers: the R135 control, the best distinct target-only architecture, and the best graph-informed architecture.
5. Run Wave 2 with the next six unique receiver architectures only if Wave 1 does not strictly improve the frozen R135 internal AQL of `7.321827444818605`.
6. Freeze the receiver, its `tau0`, and the driver using equal-weight mean seven-quantile AQL over the three internal splits. Test-fold information is forbidden at this decision.
7. Refit the frozen receiver and driver on each official fold training window, fit the seven nested AL receivers, and generate 500-path recursive forecasts.
8. Compare the completed DK_1 folds with the frozen Q-DESN and clean local PriceFM references. No authority, registry, article, or wider rollout mutation is permitted.

## Forecast contract

The driver and receiver may use different reservoirs and feature policies. At each horizon the Normal driver generates a path-specific target in its own standardized units. That target is transformed back to EUR/MWh and then into the receiver's training scale before it enters the receiver's next lag vector. Exogenous values remain the released retrospective conditional inputs. States advance recursively within each 96-step origin and observations teacher-force the next origin.

## Efficiency and stopping

R138 reuses all certified Ridge and Normal RHS evidence. Only the missing seven-quantile confirmations, cross-driver scoring, and the final fold refits are computed. It launches after the two Jerez R137 controllers have released their reserved cores. Wave 2 is conditional. MCMC, exAL, joint fitting, another broad screen, and all-region rollout are outside this stage.
