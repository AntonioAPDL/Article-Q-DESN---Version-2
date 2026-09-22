# PriceFM Stage-R110D focus failure atlas

Date: 2026-09-21

R110D is the read-only decision bridge after R110C. It combines the frozen
R108 oracle decomposition, R110 direct-driver closeout, R110B downstream
replay, R110C path-representation decision, and exact R103 active-region
contracts. It reads validation evidence only and performs no model fit.

The atlas has three prospective decisions. BE is a frozen control if its raw
R110 replay remains within 10 percent of R97. BG is routed to exposure-aligned
readout design when it remains above R97 despite being target-only. EE may
authorize direct-driver completion for its actual graph neighbors, FI and LV,
only when replacing imperfect neighbors by exact neighbors improves the
exact-target replay by at least 10 percent.

Outputs include case- and horizon-level attribution tables, a region mechanism
summary, action queue, decision gates, source hashes, JSON summary, and a
Markdown report. The stage cannot authorize a BG fit, broad all-region work,
test access, registry or article mutation, joint models, or MCMC.

## Materialized decision

All nine focus cases and all six prospective gates passed. BE is held frozen:
its R110 replay is 9.32 percent above R97. BG is target-only and remains 14.82
percent above R97, with a 4.75 percent deterioration when its direct driver is
propagated through the frozen readout; only exposure-aligned readout design is
authorized there. EE remains 17.09 percent above R97 and deteriorates 10.60
percent through propagation, while exact neighbor replacement improves the
exact-target replay by 40.20 percent. Its active panel is exactly EE, FI, and
LV.

R111A is therefore authorized to run the frozen R110 direct-driver selection
protocol for FI and LV only, reuse the completed EE target driver, and then
perform a no-refit all-active EE replay. It must retain fold-1-training-only
selection, one policy per neighbor region, 500 paths, and the existing R103 EE
readout. This does not authorize BG fitting or any broad campaign.
