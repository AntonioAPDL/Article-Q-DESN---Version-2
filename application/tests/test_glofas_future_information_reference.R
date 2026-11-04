# Generated coefficient/scale uncertainty only; no authentic input or fit.
local({
  source("scripts/diagnostics/glofas_future_information_reference.R",local=TRUE)
  report<-gfir_run_information_diagnostics()
  checks<-report$checks
  stopifnot(nrow(checks)>=50L,all(checks$reference_validity=="PASS"),
    all(checks$implementation_parity=="PASS"),all(checks$numerical_stability=="PASS"),
    any(checks$approximation_accuracy=="FAIL"),
    identical(report$scientific_runs,0L),identical(report$authentic_reads,0L),
    identical(report$future_truth_read,FALSE))
  # A parameter-independent joint future block is not sufficient. Its gap
  # depends on parameters; the conditional block cancels it pointwise.
  normal<-report$cases[grepl("^normal",names(report$cases))]
  stopifnot(all(vapply(normal,function(x)x$conditional_block_KL_changes_with_parameters>1e-4,logical(1L))))
  scale<-report$cases[["AL_unknown_scale_h2_p0.5"]]
  stopifnot(abs(scale$reference$scale_shape-6)<1e-12,
    abs(scale$mean_field$scale_shape-6)<1e-12,
    abs(scale$reference$prior_shape-3)<1e-12,
    abs(scale$mean_field$precision_mean-1.5)<1e-9,
    max(abs(scale$prior_cdf-scale$mean_field_cdf))>.005,
    abs(scale$reference$exact_scale_mean-scale$reference$mf_scale_mean)>.01)
  # Exact Normal conditional normalization is checked independently in response
  # coordinates, not by comparing two copies of the same algebraic formula.
  stopifnot(all(checks$error[grepl("normalized_future",checks$test_id)]<1e-8))
  reject<-function(expr)stopifnot(inherits(try(force(expr),silent=TRUE),"try-error"))
  reject(gfir_normal_contract(3))
  reject(gfir_al_cdf(0,0))
  reject(gfir_al_scale_reference(.5,a=1))
  # Mutation control: reverse an AR transition sign in the full-block oracle;
  # its conditional density no longer matches the structural transition.
  c<-gfir_normal_contract(2L);wrong<-c;wrong$M[1,2]<-wrong$M[2,1]<- -wrong$M[1,2]
  gap<-gfir_conditional_log_gap(c(.2,.6),c(.3,-.2),.8,wrong)
  stopifnot(abs(gap)>1e-3)
  cat(sprintf("GLOFAS_FUTURE_INFORMATION_REFERENCE_PASS checks=%d approximation_failures=%d original_reads=0 scientific_runs=0\n",
    nrow(checks),sum(checks$approximation_accuracy=="FAIL")))
})
