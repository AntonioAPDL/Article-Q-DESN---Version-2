#!/usr/bin/env Rscript
# Source-frozen generated references only; never accesses model payloads.
gvaa_require <- function(ok, why) {
  if (!isTRUE(ok)) stop(paste0("GloFAS variance auxiliary audit: ", why), call. = FALSE)
  invisible(TRUE)
}
gvaa_sources <- function() c("scripts/audit_glofas_variance_auxiliary_references.R",
  "scripts/diagnostics/glofas_variance_particle_reference.R",
  "scripts/diagnostics/glofas_al_future_score_projection.R",
  "scripts/diagnostics/glofas_collapsed_al_target.R",
  "scripts/diagnostics/glofas_collapsed_particle_vi.R",
  "scripts/diagnostics/glofas_innovation_coordinates.R",
  "scripts/diagnostics/glofas_optimizer_predictive_reference.R",
  "scripts/diagnostics/glofas_collapsed_optimizer_reference.R",
  "scripts/diagnostics/glofas_collapsed_particle_reference.R")
gvaa_compute <- function(part, source_hashes, counts = c(16L,64L,256L), replicates = 16L) {
  gvaa_require(is.character(part) && length(part)==1L && part %in% c("predictive","particle") &&
    is.character(source_hashes) && identical(names(source_hashes),gvaa_sources()) &&
    all(grepl("^[a-f0-9]{64}$",source_hashes)), "explicit part and complete source hashes required")
  e <- new.env(parent=environment(gvaa_compute))
  for(path in rev(gvaa_sources()[-1L])) sys.source(path,envir=e,keep.source=FALSE)
  flags <- list(application_qualified=FALSE,production_qualified=FALSE,native_launch_authorized=FALSE,
    full_application_parameter_accuracy_qualified=FALSE,
    full_posterior_accuracy_qualified=FALSE,native_backend_qualified=FALSE,
    production_launch_authorized=FALSE,publication_authorized=FALSE,
    original_RDS_reads=0L,original_RDS_stats=0L,original_RDS_hashes=0L,
    application_fits=0L,future_truth_reads=0L,forecast_score_selection=FALSE,
    existing_results_changed=FALSE)
  started <- proc.time()
  tables <- list()
  if(part=="predictive") {
    fixtures <- list(no_members=numeric(),moderate_51=seq(-.3,.7,length.out=51L),concentrated_51=rep(.2,51L))
    rows <- list(); gates <- NULL
    for(name in names(fixtures)) {
      a <- e$gopr_assess_h1(fixtures[[name]])
      for(kind in c("quantiles","CDF","parameter_mean","parameter_variance"))
        tables[[paste0(name,"_",kind,".csv")]] <- a[[kind]]
      gates <- a$gates
      rows[[name]] <- data.frame(fixture=name,members=length(fixtures[[name]]),status=a$status,
        primary_quantile_absolute_error=a$primary_quantile_absolute_error,
        maximum_grid_CDF_error=a$maximum_grid_CDF_error,
        GH_maximum_CDF_difference=a$GH_maximum_CDF_difference,
        GH_maximum_quantile_difference=a$GH_maximum_quantile_difference,
        predictive_gates_passed=a$predictive_gates_passed,
        quadrature_comparison_passed=a$quadrature_comparison_passed,
        theta_log_sigma_covariance_exact=a$theta_log_sigma_covariance_exact,
        theta_log_sigma_covariance_q=a$theta_log_sigma_covariance_q,
        theta_sigma_covariance_exact=a$theta_sigma_covariance_exact,
        theta_sigma_covariance_q=a$theta_sigma_covariance_q,
        Gaussian_family_ELBO=a$Gaussian_family_ELBO,exact_log_evidence=a$exact_log_evidence,
        reference_family_KL=a$reference_family_KL,full_posterior_accuracy_qualified=FALSE,
        production_qualified=FALSE,native_launch_authorized=FALSE)
    }
    tables[["predictive_summary.csv"]] <- do.call(rbind,rows)
    tables[["prespecified_gates.csv"]] <- data.frame(gate=names(gates),threshold=unlist(gates,use.names=FALSE))
    controls <- list(fixtures=names(fixtures),model_probability=.2,
      reported_probabilities=c(.05,.2,.5,.8,.95),Gaussian_reference="independent deterministic variational optimum",
      quadrature_nodes=c(32L,64L),gates=gates,
      assessment_grid="Exact/q five-level quantile knots and adjacent midpoints; not a global CDF supremum")
    scope <- "Controlled H1 coefficient/shared AL scale; not native Y/G-specific scales or RHS"
  } else {
    gvaa_require(is.numeric(counts) && length(counts)>=1L && length(counts)<=3L && !anyDuplicated(counts) &&
      all(is.finite(counts)) && all(counts==floor(counts)) && all(counts>=2L & counts<=256L) &&
      is.numeric(replicates) && length(replicates)==1L && is.finite(replicates) &&
      replicates==floor(replicates) && replicates>=4L && replicates<=16L,
      "bounded generated reference counts and replicates required")
    block <- function(ix) list(index=ix,intercept_index=ix[1L],tau0=.3,
      intercept_prec=.2,slab_shape=2,slab_rate=4,zeta2_fixed=NULL)
    spec <- e$gcat_spec(6L,list(beta=block(1:3),alpha=block(4:6)),.2,
      list(Y=c(shape=2,rate=1),G=c(shape=2,rate=1)))
    F <- rbind(c(1,.2,-.1),c(1,.25,-.15)); D <- rbind(c(1,-.1,.3),c(1,-.05,.35))
    members <- rbind(seq(.08,.22,length.out=51L),seq(.1,.24,length.out=51L))
    sigmaY <- c(.2,.5,1);sigmaG <- c(.8,1,1.2)
    points <- lapply(1:3,function(i){x<-numeric(spec$dimension);x[1:6]<-.1;
      x[spec$scales]<-log(c(sigmaY[i],sigmaG[i]));x})
    contexts <- list(weak=c(reference=.03,discrepancy=-.01),strong=c(reference=.35,discrepancy=0))
    records <- summaries <- times <- list()
    for(name in names(contexts)) {
      clock <- proc.time(); lag <- contexts[[name]]
      x <- e$gvar_compare_h2(spec,F,D,members,points,counts=counts,replicates=replicates,
        reference_lag=unname(lag["reference"]),discrepancy_lag=unname(lag["discrepancy"]),
        known_baseline=c(.07,.08))
      elapsed <- proc.time()-clock
      records[[name]] <- cbind(context=name,x$records)
      summaries[[name]] <- cbind(context=name,x$summary)
      times[[name]] <- data.frame(context=name,elapsed_seconds=unname(elapsed["elapsed"]),
        CPU_seconds=unname(elapsed["user.self"]+elapsed["sys.self"]),conditional_runs=nrow(x$records))
    }
    tables[["particle_records.csv"]] <- do.call(rbind,records)
    tables[["particle_summary.csv"]] <- do.call(rbind,summaries)
    tables[["particle_context_timing.csv"]] <- do.call(rbind,times)
    tables[["prespecified_scale_points.csv"]] <- data.frame(point=1:3,sigma_Y=sigmaY,sigma_G=sigmaG)
    tables[["parameter_coordinates.csv"]] <- do.call(rbind,lapply(1:3,function(i)
      data.frame(point=i,coordinate=spec$coordinate_names,transformed_value=points[[i]])))
    tables[["generated_reference_features.csv"]] <- data.frame(horizon=1:2,F)
    tables[["generated_discrepancy_features.csv"]] <- data.frame(horizon=1:2,D)
    tables[["generated_members.csv"]] <- data.frame(horizon=rep(1:2,each=51),member=rep(1:51,2),value=as.vector(t(members)))
    controls <- list(probability=.2,parameter_dimensions=spec$dimension,
      coefficients=rep(.1,6),log_RHS_coordinates=0,scale_Y=sigmaY,scale_G=sigmaG,
      counts=counts,replicates=replicates,contexts=contexts,known_baseline=c(.07,.08),
      seeds="2026111000 + 100*point + replicate; common across particle counts and contexts",
      expected_runs=2L*3L*length(counts)*replicates,
      registered_test_reduced_budget=!identical(as.integer(counts),c(16L,64L,256L))||replicates!=16L)
    scope <- "Generated affine H2 conditional points, both source scales and all 102 member factors; not parameter-marginal or native accuracy"
  }
  elapsed <- proc.time()-started
  list(part=part,tables=tables,controls=controls,flags=flags,scope=scope,
    elapsed_seconds=unname(elapsed["elapsed"]),CPU_seconds=unname(elapsed["user.self"]+elapsed["sys.self"]))
}
gvaa_git <- function(args) {
  x <- system2("git",c("--no-replace-objects","-c","core.fsmonitor=false",args),stdout=TRUE,stderr=TRUE)
  gvaa_require(is.null(attr(x,"status")),paste("Git check failed:",paste(args,collapse=" ")))
  unname(x)
}
gvaa_fresh_output <- function(output,root=normalizePath(".",mustWork=TRUE)) {
  q <- gvaa_require
  q(is.character(output)&&length(output)==1L&&!is.na(output)&&nzchar(output),"one output path required")
  if(!startsWith(output,"/"))output<-file.path(root,output)
  q(startsWith(output,paste0(root,"/local_trackers/")),"output must be in this worktree's ignored local_trackers")
  tail <- substring(output,nchar(root)+2L);components<-strsplit(tail,"/",fixed=TRUE)[[1L]]
  q(length(components)<=24L&&all(nzchar(components))&&!any(components%in%c(".","..")),"ambiguous output path")
  cursor<-root
  for(component in components){cursor<-file.path(cursor,component);link<-Sys.readlink(cursor)
    q(is.na(link)||!nzchar(link),"symlink output component is forbidden")}
  parent<-normalizePath(dirname(output),mustWork=TRUE);output<-file.path(parent,basename(output))
  q(!file.exists(output)&&!dir.exists(output),"output must be fresh; existing evidence is never overwritten")
  q(system2("git",c("check-ignore","--quiet","--",shQuote(output)))==0L,"output is not ignored")
  output
}
gvaa_source_state <- function() {
  q<-gvaa_require
  q(!length(gvaa_git(c("status","--porcelain","--untracked-files=all"))),"source worktree is not clean")
  commit<-gvaa_git(c("rev-parse","HEAD"));tree<-gvaa_git(c("rev-parse","HEAD^{tree}"))
  paths<-gvaa_sources();hashes<-tools::sha256sum(paths)
  for(path in paths)q(identical(gvaa_git(c("hash-object","--no-filters","--",shQuote(path))),
    gvaa_git(c("rev-parse",shQuote(paste0(commit,":",path))))),"source blob differs from its clean commit")
  list(commit=commit,tree=tree,paths=paths,sha256=hashes)
}
gvaa_main <- function(args=commandArgs(TRUE)) {
  q<-gvaa_require
  q(length(args)==4L&&identical(args[1L],"--part")&&args[2L]%in%c("predictive","particle")&&
    identical(args[3L],"--output"),"usage: --part {predictive,particle} --output FRESH_IGNORED_DIRECTORY")
  output<-gvaa_fresh_output(args[4L]);before<-gvaa_source_state()
  result<-gvaa_compute(args[2L],before$sha256)
  after<-gvaa_source_state();q(identical(before,after),"source changed during computation")
  q(identical(gvaa_fresh_output(output),output)&&dir.create(output,mode="0700"),"fresh output creation failed")
  for(name in names(result$tables))write.csv(result$tables[[name]],file.path(output,name),row.names=FALSE)
  source_manifest<-data.frame(relative_path=before$paths,size_bytes=as.numeric(file.info(before$paths)$size),
    sha256=unname(before$sha256))
  write.csv(source_manifest,file.path(output,"source_manifest.csv"),row.names=FALSE)
  receipt<-c(list(schema_version="glofas_generated_variance_auxiliary_audit_v1",
    status="GENERATED_REFERENCE_AUDIT_COMPLETE_NOT_NATIVE_QUALIFICATION",part=result$part,
    source_commit=before$commit,source_tree=before$tree,source_sha256=as.list(before$sha256),
    R_version=R.version.string,controls=result$controls,scope=result$scope,
    elapsed_seconds=result$elapsed_seconds,CPU_seconds=result$CPU_seconds,
    unfavorable_outcomes_retained=TRUE,source_unchanged_before_after=TRUE,
    manifest_scope="Every generated artifact except the manifest itself"),result$flags)
  jsonlite::write_json(receipt,file.path(output,"DECISION.json"),auto_unbox=TRUE,pretty=TRUE,null="null",digits=17)
  files<-sort(c(names(result$tables),"source_manifest.csv","DECISION.json"))
  q(all(grepl("^[A-Za-z0-9_]+\\.(csv|json)$",files))&&
    identical(sort(list.files(output,all.files=FALSE)),files),"unexpected output role; no unknown payload is statted or hashed")
  paths<-file.path(output,files)
  manifest<-data.frame(relative_path=files,size_bytes=as.numeric(file.info(paths)$size),sha256=unname(tools::sha256sum(paths)))
  write.csv(manifest,file.path(output,"artifact_manifest.csv"),row.names=FALSE)
  check<-read.csv(file.path(output,"artifact_manifest.csv"),stringsAsFactors=FALSE)
  q(identical(check$relative_path,manifest$relative_path),"manifest roles changed; refusing unknown payload access")
  q(identical(as.character(check$sha256),unname(tools::sha256sum(file.path(output,check$relative_path))))&&
    identical(as.numeric(check$size_bytes),as.numeric(file.info(file.path(output,check$relative_path))$size)),"output manifest failed")
  q(identical(before,gvaa_source_state()),"source changed while writing the ignored receipt")
  cat("GLOFAS_GENERATED_VARIANCE_AUXILIARY_AUDIT_COMPLETE_NOT_NATIVE_QUALIFICATION\n")
  invisible(receipt)
}
if(sys.nframe()==0L)gvaa_main()
