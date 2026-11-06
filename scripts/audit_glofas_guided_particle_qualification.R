#!/usr/bin/env Rscript
# Generated affine H2 audit only. Never reads retained application payloads.
gpgqa_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("Guided-particle qualification: ", why), call. = FALSE)
  invisible(TRUE)
}
gpgqa_sources <- function() c(
  "scripts/audit_glofas_guided_particle_qualification.R",
  "scripts/diagnostics/glofas_guided_collapsed_particle.R",
  "scripts/diagnostics/glofas_al_affine_guided_proposal.R",
  "scripts/diagnostics/glofas_variance_particle_reference.R",
  "scripts/diagnostics/glofas_al_future_score_projection.R",
  "scripts/diagnostics/glofas_collapsed_al_target.R",
  "scripts/diagnostics/glofas_collapsed_particle_vi.R",
  "scripts/diagnostics/glofas_innovation_coordinates.R",
  "scripts/diagnostics/glofas_collapsed_particle_reference.R",
  "scripts/audit_glofas_variance_auxiliary_references.R")

gpgqa_summarize <- function(records) {
  groups <- split(records,interaction(records$context,records$point,records$method,
    records$particles,drop=TRUE))
  summaries <- lapply(groups,function(x) {
    complete <- all(x$complete) && all(is.finite(x$relative_evidence))
    value <- if(complete)x$relative_evidence else rep(NA_real_,nrow(x))
    logvalue <- if(complete)x$estimated_log_evidence else rep(NA_real_,nrow(x))
    data.frame(context=x$context[1L],point=x$point[1L],method=x$method[1L],
      particles=x$particles[1L],replicates=nrow(x),all_complete=complete,
      diagnostic_reviews=sum(!x$diagnostic_thresholds_passed),
      maximum_absolute_log_error=if(complete)max(abs(x$log_error))else NA_real_,
      mean_relative_evidence=mean(value),relative_evidence_MCSE=sd(value)/sqrt(nrow(x)),
      single_log_estimate_SD=sd(logvalue),mean_log_estimate_MCSE=sd(logvalue)/sqrt(nrow(x)),
      empirical_Jensen_gap=x$exact_log_evidence[1L]-mean(logvalue),
      exact_affine_gate_passed=complete && max(abs(x$log_error))<=1e-8,
      production_qualified=FALSE)
  })
  summary <- do.call(rbind,summaries); rownames(summary) <- NULL; summary
}

gpgqa_compute <- function(source_hashes, counts = c(1L,16L,64L,256L), replicates = 16L) {
  q <- gpgqa_require; paths <- gpgqa_sources()
  q(is.character(source_hashes) && identical(names(source_hashes), paths) &&
      all(grepl("^[a-f0-9]{64}$", source_hashes)), "complete explicit source hashes required")
  q(identical(source_hashes,tools::sha256sum(paths)),"source hashes do not match loaded text")
  q(is.numeric(counts) && length(counts)>=1L && length(counts)<=4L &&
      !anyDuplicated(counts) && all(is.finite(counts)) &&
      all(counts==floor(counts) & counts>=1L & counts<=256L) &&
      is.numeric(replicates) && length(replicates)==1L && is.finite(replicates) &&
      replicates==floor(replicates) && replicates>=2L && replicates<=16L,
    "bounded generated counts and replicates required")
  e <- new.env(parent=environment(gpgqa_compute))
  for (path in rev(paths[-1L])) sys.source(path, envir=e, keep.source=FALSE)
  # These constants are shared with the preceding frozen bootstrap audit.
  block <- function(ix) list(index=ix,intercept_index=ix[1L],tau0=.3,
    intercept_prec=.2,slab_shape=2,slab_rate=4,zeta2_fixed=NULL)
  spec <- e$gcat_spec(6L,list(beta=block(1:3),alpha=block(4:6)),.2,
    list(Y=c(shape=2,rate=1),G=c(shape=2,rate=1)))
  F <- rbind(c(1,.2,-.1),c(1,.25,-.15)); D <- rbind(c(1,-.1,.3),c(1,-.05,.35))
  members <- rbind(seq(.08,.22,length.out=51L),seq(.1,.24,length.out=51L))
  sigmaY <- c(.2,.5,1); sigmaG <- c(.8,1,1.2)
  points <- lapply(1:3,function(i) {
    x <- numeric(spec$dimension); x[1:6] <- .1
    x[spec$scales] <- log(c(sigmaY[i],sigmaG[i])); x
  })
  contexts <- list(weak=c(reference=.03,discrepancy=-.01),
    strong=c(reference=.35,discrepancy=0))
  records <- list(); clock <- proc.time()
  for (context in names(contexts)) for (i in seq_along(points)) for (n in counts) {
    lag <- contexts[[context]]
    b <- e$gafsp_make_generated_al_binding(spec,F,D,members,
      reference_lag=unname(lag["reference"]),discrepancy_lag=unname(lag["discrepancy"]),
      known_baseline=c(.07,.08),particles=as.integer(max(2,n)))
    exact <- e$gvar_exact_h2(b,points[[i]])$log_evidence
    for (method in c("guided","bootstrap")) {
      if (method=="bootstrap" && n==1L) next
      for (j in seq_len(replicates)) {
        seed <- 2026111000L+100L*i+j; started <- proc.time()
        x <- tryCatch(if(method=="guided")
          e$gpg_affine_h2(b,points[[i]],particles=as.integer(n),seed=seed,
            gates=list(min_ess=min(2,n),min_unique_ancestors=as.integer(min(2,n))))
          else b$evidence(points[[i]],seed),error=function(err)err)
        failed <- inherits(x,"error")
        if (failed) {
          complete <- FALSE; estimate <- ess <- post_ess <- ancestors <- calls <- NA_real_
          diagnostics_passed <- FALSE; failure <- conditionMessage(x)
        } else {
          complete <- isTRUE(x$complete)
          estimate <- if(method=="guided") x$log_normalizer_estimate else x$log_estimate
          if(method=="guided") {
            ess <- if(nrow(x$diagnostics))min(x$diagnostics$effective_sample_size)else NA_real_
            post_ess <- if(nrow(x$diagnostics))min(x$diagnostics$post_correction_ESS)else NA_real_
            ancestors <- if(nrow(x$diagnostics))min(x$diagnostics$unique_initial_ancestors)else NA_real_
            diagnostics_passed <- isTRUE(x$diagnostic_thresholds_passed)
          } else {
            ess <- x$min_ess; ancestors <- x$min_unique_ancestors
            post_ess <- NA_real_ # no proposal correction in the bootstrap adapter
            diagnostics_passed <- isTRUE(x$diagnostic_thresholds_passed)
          }
          calls <- x$callback_calls
          failure <- if(!complete && !is.null(x$failure))as.character(x$failure)else ""
          if(!is.numeric(estimate)||length(estimate)!=1L) estimate <- NA_real_
          complete <- complete && is.finite(estimate)
        }
        elapsed <- proc.time()-started
        records[[length(records)+1L]] <- data.frame(context=context,point=i,method=method,
          particles=n,replicate=j,seed=seed,complete=complete,failure=failure,
          diagnostic_thresholds_passed=diagnostics_passed,exact_log_evidence=exact,
          estimated_log_evidence=estimate,log_error=estimate-exact,
          relative_evidence=if(complete)exp(estimate-exact)else NA_real_,
          minimum_member_stage_ESS=ess,minimum_post_correction_ESS=post_ess,
          minimum_initial_ancestors=ancestors,declared_minimum_ESS=min(2,n),
          declared_minimum_ancestors=min(2,n),callback_calls=calls,
          elapsed_seconds=unname(elapsed["elapsed"]),
          CPU_seconds=unname(elapsed["user.self"]+elapsed["sys.self"]),
          production_qualified=FALSE)
      }
    }
  }
  records <- do.call(rbind,records)
  summary <- gpgqa_summarize(records)
  guided <- records$method=="guided"
  pass <- all(records$complete[guided]) && all(abs(records$log_error[guided])<=1e-8)
  elapsed <- proc.time()-clock
  list(tables=list(particle_records.csv=records,particle_summary.csv=summary,
      generated_reference_features.csv=data.frame(horizon=1:2,F),
      generated_discrepancy_features.csv=data.frame(horizon=1:2,D),
      generated_members.csv=data.frame(horizon=rep(1:2,each=51),member=rep(1:51,2),
        value=as.vector(t(members))),
      parameter_coordinates.csv=do.call(rbind,lapply(seq_along(points),function(i)
        data.frame(point=i,coordinate=spec$coordinate_names,transformed_value=points[[i]]))),
      prespecified_scale_points.csv=data.frame(point=1:3,sigma_Y=sigmaY,sigma_G=sigmaG)),
    controls=list(probability=.2,contexts=contexts,counts=counts,replicates=replicates,
      sigma_Y=sigmaY,sigma_G=sigmaG,known_baseline=c(.07,.08),
      seed_rule="2026111000 + 100*point + replicate; common across counts and methods",
      absolute_affine_log_evidence_error=1e-8,
      minimum_ESS=2,minimum_initial_ancestors=2L,N1_reference_gate_exception=1L,
      ESS_scope="member-stage ESS and separate post-correction ESS; no correction in bootstrap",
      expected_guided_runs=6L*length(counts)*replicates,
      expected_bootstrap_runs=6L*sum(counts>1L)*replicates,
      registered_test_reduced_budget=!identical(as.integer(counts),c(1L,16L,64L,256L))||replicates!=16L),
    exact_affine_reference_passed=pass,
    elapsed_seconds=unname(elapsed["elapsed"]),
    CPU_seconds=unname(elapsed["user.self"]+elapsed["sys.self"]),
    flags=list(original_RDS_reads=0L,original_RDS_hashes=0L,original_RDS_stats=0L,
      application_fits=0L,future_truth_reads=0L,forecast_score_selection=FALSE,
      application_qualified=FALSE,native_launch_authorized=FALSE,
      full_posterior_accuracy_qualified=FALSE,production_launch_authorized=FALSE,
      publication_authorized=FALSE,existing_results_changed=FALSE))
}

gpgqa_state <- function() {
  q <- gpgqa_require
  if(!exists("gvaa_git",mode="function"))
    source("scripts/audit_glofas_variance_auxiliary_references.R",local=TRUE)
  q(!length(gvaa_git(c("status","--porcelain","--untracked-files=all"))),"source is not clean")
  commit <- gvaa_git(c("rev-parse","HEAD")); tree <- gvaa_git(c("rev-parse","HEAD^{tree}"))
  paths <- gpgqa_sources(); hashes <- tools::sha256sum(paths)
  for(path in paths) q(identical(gvaa_git(c("hash-object","--no-filters","--",shQuote(path))),
    gvaa_git(c("rev-parse",shQuote(paste0(commit,":",path))))),"source blob differs from commit")
  list(commit=commit,tree=tree,paths=paths,sha256=hashes)
}

gpgqa_write <- function(result,output,before) {
  q <- gpgqa_require
  source("scripts/audit_glofas_variance_auxiliary_references.R",local=TRUE)
  q(identical(before,gpgqa_state()),"source changed during computation")
  records <- result$tables$particle_records.csv; guided <- records$method=="guided"
  q(sum(guided)==result$controls$expected_guided_runs &&
    sum(!guided)==result$controls$expected_bootstrap_runs,"incomplete declared record counts")
  gate <- all(records$complete[guided]) && all(is.finite(records$log_error[guided])) &&
    all(abs(records$log_error[guided])<=1e-8)
  q(identical(gate,result$exact_affine_reference_passed),"declared affine gate contradicts saved records")
  q(identical(gpgqa_summarize(records),result$tables$particle_summary.csv),
    "saved summaries contradict retained records")
  q(identical(gvaa_fresh_output(output),output)&&dir.create(output,mode="0700"),"fresh output required")
  for(name in names(result$tables))write.csv(result$tables[[name]],file.path(output,name),row.names=FALSE)
  sources <- data.frame(relative_path=before$paths,
    size_bytes=as.numeric(file.info(before$paths)$size),sha256=unname(before$sha256))
  write.csv(sources,file.path(output,"source_manifest.csv"),row.names=FALSE)
  receipt <- c(list(schema_version="glofas_generated_guided_particle_audit_v1",
    status=if(result$exact_affine_reference_passed)"AFFINE_H2_REFERENCE_PASS_NATIVE_NOT_QUALIFIED"
      else "AFFINE_H2_REFERENCE_FAILED_NATIVE_NOT_QUALIFIED",
    source_commit=before$commit,source_tree=before$tree,source_sha256=as.list(before$sha256),
    controls=result$controls,exact_affine_reference_passed=result$exact_affine_reference_passed,
    R_version=R.version.string,elapsed_seconds=result$elapsed_seconds,CPU_seconds=result$CPU_seconds,
    scope="Conditional generated affine H2 with all102 unit factors and both scales; not nonlinearH28 or uncertain-parameter accuracy",
    unfavorable_outcomes_retained=TRUE,source_unchanged_before_after=TRUE),result$flags)
  jsonlite::write_json(receipt,file.path(output,"DECISION.json"),auto_unbox=TRUE,pretty=TRUE,digits=17,null="null")
  files <- sort(c(names(result$tables),"source_manifest.csv","DECISION.json"))
  q(all(grepl("^[A-Za-z0-9_]+\\.(csv|json)$",files))&&
    identical(sort(list.files(output)),files),"unexpected output roles; no unknown payload is accessed")
  paths <- file.path(output,files)
  manifest <- data.frame(relative_path=files,size_bytes=as.numeric(file.info(paths)$size),
    sha256=unname(tools::sha256sum(paths)))
  write.csv(manifest,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  check <- read.csv(file.path(output,"artifact_manifest.csv"),stringsAsFactors=FALSE)
  q(identical(check$relative_path,files),"manifest roles changed")
  q(identical(check$sha256,unname(tools::sha256sum(file.path(output,check$relative_path))))&&
    identical(as.numeric(check$size_bytes),as.numeric(file.info(file.path(output,check$relative_path))$size)),
    "output manifest mismatch")
  q(identical(before,gpgqa_state()),"source changed while writing receipt")
  invisible(receipt)
}
gpgqa_main <- function(args=commandArgs(TRUE)) {
  q <- gpgqa_require
  q(length(args)==2L&&identical(args[1L],"--output"),"usage: --output FRESH_IGNORED_DIRECTORY")
  source("scripts/audit_glofas_variance_auxiliary_references.R",local=TRUE)
  output <- gvaa_fresh_output(args[2L]); before <- gpgqa_state()
  result <- gpgqa_compute(before$sha256)
  receipt <- gpgqa_write(result,output,before)
  cat(receipt$status,"\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gpgqa_main()
