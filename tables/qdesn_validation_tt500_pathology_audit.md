# 500-Observation Validation Pathology Audit

- input_csv: `/data/jaguir26/local/src/Article-Q-DESN__wt__main_validation_tables/tables/qdesn_validation_tt500_final_summary.csv`
- output_csv: `/data/jaguir26/local/src/Article-Q-DESN__wt__main_validation_tables/tables/qdesn_validation_tt500_pathology_audit.csv`
- generated_at: `2026-07-04 08:29:32.005282`

## Thresholds

- catastrophic: MAE >= 5.00x external OR check loss >= 2.50x external OR MAE >= 8.00x cell-best OR check loss >= 3.00x cell-best
- needs_review: MAE >= 2.00x external OR check loss >= 1.50x external OR MAE >= 3.00x cell-best OR check loss >= 2.00x cell-best

## Severity Counts

         model_key ok needs_review catastrophic
   qdesn_al_rhs_ns 13            5            0
    qdesn_al_ridge  0            8           10
 qdesn_exal_rhs_ns 14            4            0
  qdesn_exal_ridge  2            6           10

## Flagged Rows

  family  tau inference        model_label forecast_qtrue_mae_lead_weighted
  normal 0.50        vb     Q--DESN AL RHS                         2.229036
  normal 0.05        vb   Q--DESN AL ridge                        10.051865
  normal 0.25        vb   Q--DESN AL ridge                        28.531628
  normal 0.50        vb   Q--DESN AL ridge                        27.877334
 laplace 0.05        vb   Q--DESN AL ridge                        11.997847
 laplace 0.25        vb   Q--DESN AL ridge                         9.352963
 laplace 0.50        vb   Q--DESN AL ridge                        13.506345
 gausmix 0.05        vb   Q--DESN AL ridge                        10.265878
 gausmix 0.25        vb   Q--DESN AL ridge                        15.928435
 gausmix 0.50        vb   Q--DESN AL ridge                         8.481225
 laplace 0.50        vb   Q--DESN exAL RHS                         2.663431
  normal 0.05        vb Q--DESN exAL ridge                        14.682085
  normal 0.25        vb Q--DESN exAL ridge                        29.607389
  normal 0.50        vb Q--DESN exAL ridge                        27.587458
 laplace 0.05        vb Q--DESN exAL ridge                         9.045776
 laplace 0.25        vb Q--DESN exAL ridge                        12.405271
 laplace 0.50        vb Q--DESN exAL ridge                        13.558211
 gausmix 0.25        vb Q--DESN exAL ridge                        14.306598
 gausmix 0.50        vb Q--DESN exAL ridge                         8.758449
  normal 0.05      mcmc     Q--DESN AL RHS                         7.930257
  normal 0.50      mcmc     Q--DESN AL RHS                         3.791026
 laplace 0.05      mcmc     Q--DESN AL RHS                        12.141271
 laplace 0.50      mcmc     Q--DESN AL RHS                         2.764547
  normal 0.05      mcmc   Q--DESN AL ridge                        11.043684
  normal 0.25      mcmc   Q--DESN AL ridge                        26.105491
  normal 0.50      mcmc   Q--DESN AL ridge                        27.752752
 laplace 0.05      mcmc   Q--DESN AL ridge                        19.767144
 laplace 0.25      mcmc   Q--DESN AL ridge                         9.953829
 laplace 0.50      mcmc   Q--DESN AL ridge                        13.409490
 gausmix 0.05      mcmc   Q--DESN AL ridge                         8.722499
 gausmix 0.25      mcmc   Q--DESN AL ridge                        16.815190
 gausmix 0.50      mcmc   Q--DESN AL ridge                         8.096825
  normal 0.50      mcmc   Q--DESN exAL RHS                         3.474777
 laplace 0.50      mcmc   Q--DESN exAL RHS                         3.247621
 gausmix 0.25      mcmc   Q--DESN exAL RHS                         5.376069
  normal 0.05      mcmc Q--DESN exAL ridge                        16.601541
  normal 0.25      mcmc Q--DESN exAL ridge                        27.051181
  normal 0.50      mcmc Q--DESN exAL ridge                        27.657952
 laplace 0.05      mcmc Q--DESN exAL ridge                         9.678132
 laplace 0.25      mcmc Q--DESN exAL ridge                        10.933680
 laplace 0.50      mcmc Q--DESN exAL ridge                        12.434950
 gausmix 0.25      mcmc Q--DESN exAL ridge                        13.170272
 gausmix 0.50      mcmc Q--DESN exAL ridge                         7.531729
 forecast_check_loss_lead_weighted mae_vs_external check_loss_vs_external
                          4.103532       2.0093298               1.020371
                          1.533206       6.9575352               1.422707
                          8.890197      14.1084206               2.667264
                         14.136134      25.1295896               3.515046
                          2.508014       3.2923227               1.342544
                          5.582593       3.9856519               1.261154
                          8.888760      10.5136065               1.750623
                          2.407074       1.9859346               1.494793
                          6.745427       4.0059768               1.431896
                          7.131282       4.6097565               1.287008
                          5.265837       2.0732672               1.037096
                          1.566360      10.1624050               1.453472
                          9.119897      14.6403665               2.736180
                         13.993411      24.8682855               3.479557
                          2.099310       2.4822465               1.123764
                          6.087917       5.2863564               1.375311
                          8.907766      10.5539796               1.754366
                          6.386323       3.5980873               1.355667
                          7.183486       4.7604344               1.296430
                          1.252014       2.0708900               1.134755
                          4.339175       3.2639348               1.077026
                          2.103368       1.2400731               1.068827
                          5.254108       2.0670993               1.033853
                          2.461469       2.8839233               2.230937
                          8.262600      11.8199763               2.483005
                         14.067370      23.8941078               3.491659
                          2.483192       2.0189570               1.261835
                          5.685533       2.8276912               1.250203
                          8.863323      10.0265077               1.744039
                          1.929554       2.9049384               1.282347
                          6.924302       6.7602600               1.525332
                          7.012474       4.1906740               1.262090
                          4.284751       2.9916560               1.063517
                          5.333870       2.4283022               1.049548
                          4.803266       2.1613568               1.058096
                          1.651948       4.3352899               1.497233
                          8.496303      12.2481631               2.553236
                         14.028719      23.8124891               3.482066
                          2.063332       0.9884955               1.048482
                          5.820793       3.1060479               1.279945
                          8.453014       9.2978276               1.663303
                          6.236155       5.2948830               1.373742
                          6.780430       3.8981972               1.220327
 mae_vs_cell_best check_loss_vs_cell_best     severity
         2.009330                1.020371 needs_review
         6.957535                1.442192 catastrophic
        20.624387                2.727783 catastrophic
        25.129590                3.515046 catastrophic
         3.949653                1.342544 needs_review
         5.761925                1.265540 needs_review
        14.059645                1.761298 catastrophic
         3.187879                1.536159 needs_review
         9.277382                1.501869 catastrophic
         6.222569                1.310286 needs_review
         2.772541                1.043420 needs_review
        10.162405                1.473379 catastrophic
        21.402012                2.798262 catastrophic
        24.868285                3.479557 catastrophic
         2.977840                1.123764 needs_review
         7.642311                1.380094 catastrophic
        14.113635                1.765064 catastrophic
         8.332757                1.421915 catastrophic
         6.425965                1.319878 needs_review
         2.990368                1.163170 needs_review
         3.263935                1.077026 needs_review
         5.665531                1.131238 needs_review
         2.067099                1.033853 needs_review
         4.164389                2.286800 needs_review
        11.819976                2.483005 catastrophic
        23.894108                3.491659 catastrophic
         9.224024                1.335517 catastrophic
         4.022895                1.265292 needs_review
        10.026508                1.744039 catastrophic
         4.300629                1.282347 needs_review
         6.760260                1.525332 catastrophic
         4.190674                1.262090 needs_review
         2.991656                1.063517 needs_review
         2.428302                1.049548 needs_review
         2.161357                1.058096 needs_review
         6.260164                1.534724 needs_review
        12.248163                2.553236 catastrophic
        23.812489                3.482066 catastrophic
         4.516147                1.109706 needs_review
         4.418907                1.295393 needs_review
         9.297828                1.663303 catastrophic
         5.294883                1.373742 catastrophic
         3.898197                1.220327 needs_review
                             article_interface_ids
 qdesn_al_rhs_recalibrated_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
             qdesn_vb_stage4_remaining_cell_repair
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
      qdesn_mcmc_al_rhs_recalibrated_authoritative
      qdesn_mcmc_al_rhs_recalibrated_authoritative
      qdesn_mcmc_al_rhs_recalibrated_authoritative
      qdesn_mcmc_al_rhs_recalibrated_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
   qdesn_mcmc_vb_winner_confirmation_authoritative
   qdesn_mcmc_vb_winner_confirmation_authoritative
   qdesn_mcmc_vb_winner_confirmation_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
     qdesn_ridge_corrected_candidate_authoritative
