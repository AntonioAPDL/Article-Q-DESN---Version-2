# Candidate table projection only. No historical asset or manuscript is edited.
source("scripts/glofas_same_family_closeout.R")
gsc_check_packet <- function(root,manifest_sha256) {
  q <- gsc_require;root <- normalizePath(root,mustWork=TRUE)
  path <- file.path(root,"artifact_manifest.csv")
  q(identical(unname(tools::sha256sum(path)),manifest_sha256),"closeout manifest differs")
  manifest <- read.csv(path,stringsAsFactors=FALSE)
  required <- c("accepted_producers.json","DECISION.json","FORECAST_SEAL.json","family_scores.csv","progress.json",
    "quantile_paths.csv","raw_crossings.csv","score_contract.json","scores_by_date.csv",
    "scoring_truth.csv","quantile_calibration.csv")
  q(identical(names(manifest),c("relative_path","size_bytes","sha256"))&&!anyDuplicated(manifest$relative_path)&&
    all(!grepl("[/\\\\]|^\\.",manifest$relative_path))&&setequal(manifest$relative_path,required),
    "bounded exact scored-packet inventory required")
  q(setequal(list.files(root,all.files=TRUE,no..=TRUE),c(manifest$relative_path,"artifact_manifest.csv")),"packet membership differs")
  for(i in seq_len(nrow(manifest)))gsc_pin(list(path=file.path(root,manifest$relative_path[i]),
    size_bytes=manifest$size_bytes[i],sha256=manifest$sha256[i]),8*1024^2)
  decision <- jsonlite::read_json(file.path(root,"DECISION.json"),simplifyVector=FALSE)
  q(identical(decision$schema_version,"glofas_same_family_closeout_receipt_v1")&&
    identical(decision$status,"READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION")&&
    identical(decision$mode,"score")&&isTRUE(decision$future_truth_read)&&
    identical(decision$model_selection_or_retuning,FALSE)&&decision$new_fits==0&&
    identical(decision$article_publication_authorized,FALSE),"complete scored packet required, not article approval")
  collection <- jsonlite::read_json(file.path(root,"accepted_producers.json"),simplifyVector=FALSE)
  gsc_validate_collection(collection,decision$expected_identity)
  gsc_verify_forecast_seal(root,decision$forecast_seal_sha256)
  contract <- jsonlite::read_json(file.path(root,"score_contract.json"),simplifyVector=FALSE)
  q(identical(contract$name,"realized_finite_grid_acrps")&&identical(contract$scale,"log1p")&&
    contract$factor==2&&max(abs(as.numeric(unlist(contract$weights))-c(.075,rep(.15,5L),.075)))<1e-15&&
    identical(contract$weights_renormalized,FALSE)&&isTRUE(contract$truth_used_only_after_assembly)&&
    identical(contract$model_selection_or_retuning,FALSE)&&identical(contract$article_publication_authorized,FALSE),
    "score definition or protected-truth role differs")
  rows <- read.csv(file.path(root,"quantile_paths.csv"),stringsAsFactors=FALSE)
  truth <- read.csv(file.path(root,"scoring_truth.csv"),stringsAsFactors=FALSE)
  gsc_validate_grid(rows)
  q(nrow(truth)==28L&&setequal(truth$horizon,1:28)&&!anyDuplicated(truth$horizon)&&
    all(as.Date(truth$target_date)==gsc_dates()[truth$horizon])&&all(is.finite(truth$y_transformed)),
    "complete and finite protected scoring truth required")
  # Separate literal scalar calculation, not the producer's aggregate scorer.
  score <- function(f,h) {
    b <- rows[rows$family==f&rows$horizon==h,];b <- b[order(b$tau),]
    y <- truth$y_transformed[match(h,truth$horizon)]
    loss <- vapply(seq_len(7L),function(k)if(y>=b$quantile_transformed[k])
      b$tau[k]*(y-b$quantile_transformed[k]) else (1-b$tau[k])*(b$quantile_transformed[k]-y),numeric(1L))
    sum(diff(gsc_tau())*(head(loss,-1L)+tail(loss,-1L)))
  }
  expected <- vapply(gsc_families(),function(f)mean(vapply(1:28,function(h)score(f,h),numeric(1L))),numeric(1L))
  summary <- read.csv(file.path(root,"family_scores.csv"),stringsAsFactors=FALSE)
  q(nrow(summary)==7L&&!anyDuplicated(summary$family)&&setequal(summary$family,gsc_families())&&
    all(abs(summary$grid_acrps_log1p-expected[summary$family])<2e-12),"independent score recomputation differs")
  scores <- read.csv(file.path(root,"scores_by_date.csv"),stringsAsFactors=FALSE)
  q(nrow(scores)==196L&&!anyDuplicated(paste(scores$family,scores$horizon))&&
    setequal(paste(scores$family,scores$horizon),paste(rep(gsc_families(),each=28L),rep(1:28,7L)))&&
    all(as.Date(scores$target_date)==gsc_dates()[scores$horizon])&&
    all(abs(scores$grid_acrps_log1p-mapply(score,scores$family,scores$horizon))<2e-12),"by-date score recomputation differs")
  for(i in seq_len(nrow(scores))) {
    b <- rows[rows$family==scores$family[i]&rows$horizon==scores$horizon[i],];b <- b[order(b$tau),]
    y <- truth$y_transformed[match(scores$horizon[i],truth$horizon)]
    check <- mean(ifelse(y>=b$quantile_transformed,b$tau*(y-b$quantile_transformed),
      (1-b$tau)*(b$quantile_transformed-y)))
    q(abs(scores$mean_check_loss[i]-check)<2e-12&&
      identical(scores$covered90[i],y>=b$quantile_transformed[1L]&&y<=b$quantile_transformed[7L])&&
      identical(scores$inverted90[i],b$quantile_transformed[1L]>b$quantile_transformed[7L]),
      "by-date coverage, inversion or check loss differs")
  }
  for(f in gsc_families()) {
    b <- scores[scores$family==f,];i <- which(summary$family==f)
    q(summary$n_horizons[i]==28&&abs(summary$mean_check_loss[i]-mean(b$mean_check_loss))<2e-12&&
      abs(summary$coverage90[i]-mean(b$covered90))<2e-12&&summary$inverted_intervals[i]==sum(b$inverted90),
      "summary check loss or coverage differs")
  }
  crossings <- read.csv(file.path(root,"raw_crossings.csv"),stringsAsFactors=FALSE)
  q(isTRUE(all.equal(crossings,gsc_crossings(rows),tolerance=1e-14,check.attributes=FALSE)),
    "crossing disclosure differs")
  calibration <- read.csv(file.path(root,"quantile_calibration.csv"),stringsAsFactors=FALSE)
  q(nrow(calibration)==49L&&!anyDuplicated(paste(calibration$family,calibration$tau))&&
    setequal(paste(calibration$family,calibration$tau),paste(rep(gsc_families(),each=7L),rep(gsc_tau(),7L))),
    "complete probability-specific calibration required")
  for(i in seq_len(49L)) {
    b <- rows[rows$family==calibration$family[i]&rows$tau==calibration$tau[i],]
    e <- truth$y_transformed[match(b$horizon,truth$horizon)]-b$quantile_transformed
    q(calibration$n_horizons[i]==28&&abs(calibration$empirical_coverage[i]-mean(e<=0))<2e-12&&
      abs(calibration$coverage_error[i]-(mean(e<=0)-calibration$tau[i]))<2e-12&&
      abs(calibration$mean_check_loss[i]-mean(ifelse(e>=0,b$tau*e,(b$tau-1)*e)))<2e-12,
      "probability-specific calibration values differ")
  }
  list(rows=rows,truth=truth,summary=summary,decision=decision,manifest_sha256=manifest_sha256)
}

gsc_candidate_tex <- function(summary) {
  labels <- c("Raw GloFAS","Normal Ridge","Normal RHS","Q--DESN (AL)","Q--DESN (exAL)",
    "MQ--DESN (AL)","MQ--DESN (exAL)")
  summary <- summary[match(gsc_families(),summary$family),]
  end <- paste0(" ",strrep("\\",2L))
  c("% CANDIDATE ONLY: scientific review and complete figure/manuscript integration still required.",
    "\\begin{tabular}{lrrr}","\\toprule",paste0("Model & Grid aCRPS & Mean check loss & 90\\% coverage",end),
    "\\midrule",vapply(1:7,function(i)paste0(sprintf("%s & %.4f & %.4f & %.3f",labels[i],
      summary$grid_acrps_log1p[i],summary$mean_check_loss[i],summary$coverage90[i]),end),character(1L)),
    "\\bottomrule","\\end{tabular}")
}

gsc_build_candidate <- function(packet_root,manifest_sha256,output_root) {
  z <- gsc_check_packet(packet_root,manifest_sha256);q <- gsc_require
  q(!file.exists(output_root)&&dir.exists(dirname(output_root)),"fresh candidate output required")
  q(dir.create(output_root),"candidate directory creation failed")
  write.csv(z$summary,file.path(output_root,"candidate_family_scores.csv"),row.names=FALSE)
  writeLines(gsc_candidate_tex(z$summary),file.path(output_root,"candidate_score_table.tex"))
  jsonlite::write_json(list(schema_version="glofas_same_family_projection_candidate_v1",
    status="CANDIDATE_NOT_ARTICLE_AUTHORITY",source_packet_manifest_sha256=manifest_sha256,
    forecast_rows=1372L,models=7L,independent_score_check=TRUE,article_publication_authorized=FALSE,
    missing_publication_inputs=c("authenticated_new_fitted_history","approved_vector_figures",
      "reviewed_manuscript_and_supplement_replacement","section_authority_publication_policy")),
    file.path(output_root,"PROJECTION_CANDIDATE.json"),pretty=TRUE,auto_unbox=TRUE)
  invisible(z)
}

if(sys.nframe()==0L) {
  args <- commandArgs(TRUE)
  gsc_require(length(args)==6L&&identical(args[c(1,3,5)],c("--packet","--manifest-sha256","--out")),
    "Usage: --packet ROOT --manifest-sha256 SHA --out NEW_IGNORED_CANDIDATE_ROOT")
  gsc_require(system2("git",c("check-ignore","--quiet","--",shQuote(args[6L])))==0L,"ignored candidate output required")
  gsc_build_candidate(args[2L],args[4L],args[6L])
  cat("GLOFAS_PROJECTION_CANDIDATE_CHECKED_NOT_PUBLICATION\n")
}
