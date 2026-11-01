#!/usr/bin/env Rscript
# Immutable preparation only. This script cannot launch a production fit.
script_file <- sub("^--file=", "", grep("^--file=",commandArgs(FALSE),value=TRUE)[1L])
repo <- normalizePath(file.path(dirname(script_file),"..",".."),mustWork=TRUE)
setwd(repo)
source("application/scripts/_glofas_unit_member_bootstrap.R")
source("application/R/glofas_family_transition.R")
app_qdesn_engine_function <- function(...) app_gft_stop(
  "Transition preparation must not load a moving external feature engine.")
args <- app_parse_args(list(source_runtime="", evidence_manifest="", evidence_manifest_sha256="",
  source_manifest="", source_manifest_sha256="", output_root="", plan_sha256="",
  root_initializer=""))
for (key in names(args)[grepl("-",names(args),fixed=TRUE)]) {
  args[[gsub("-","_",key,fixed=TRUE)]] <- args[[key]]
}
required <- c("source_runtime","evidence_manifest","evidence_manifest_sha256",
  "source_manifest","source_manifest_sha256","output_root","plan_sha256","root_initializer")
if (any(!vapply(args[required],function(x) is.character(x)&&length(x)==1L&&nzchar(x),logical(1L)))) {
  app_gft_stop("Preparation requires explicit frozen source/evidence/plan identities and a new output root.")
}
if (!grepl("^[0-9a-f]{64}$",args$plan_sha256)) app_gft_stop("Plan identity must be an exact SHA256.")
source_runtime <- normalizePath(args$source_runtime,mustWork=TRUE)
source_manifest <- normalizePath(args$source_manifest,mustWork=TRUE)
source_files <- app_gft_verify_source_manifest(source_manifest,args$source_manifest_sha256,repo)
evidence <- app_gft_verify_manifest(args$evidence_manifest,args$evidence_manifest_sha256,
  root=source_runtime)
out <- normalizePath(args$output_root,mustWork=FALSE)
if (startsWith(out,paste0(source_runtime,"/")) || identical(out,source_runtime)) {
  app_gft_stop("Preparation cannot write into the frozen scientific source runtime.")
}
if (dir.exists(out) && length(list.files(out,all.files=TRUE,no..=TRUE))) app_gft_stop("Prepared runtime already exists and is not empty.")
ignored <- system2("git",c("check-ignore","--quiet",shQuote(out)),stdout=FALSE,stderr=FALSE)
if (ignored!=0L) app_gft_stop("Prepared runtime must be ignored by Git.")
frozen_design_path <- app_gft_bind_path(file.path(source_runtime,"objects/part4_shared_design_truth_free.rds"),evidence)
old_manifest_path <- app_gft_bind_path(file.path(source_runtime,"configs/part4_model_manifest.csv"),evidence)
frozen_design_sha256 <- app_sha256_file(frozen_design_path)
frozen <- readRDS(frozen_design_path)
design <- app_glofas_family_transition_design(frozen)
root_source <- app_gft_bind_path(args$root_initializer,evidence)
root_original <- readRDS(root_source)
root_core <- app_glofas_part4_extract_fit(root_original)
if (!identical(root_core$likelihood_family,"normal") ||
    !identical(root_original$state_contract_hash,app_glofas_part4_state_contract_hash(frozen)) ||
    !identical(root_original$shared_design_reference$sha256,frozen_design_sha256)) {
  app_gft_stop("Normal median initializer lacks matching authenticated frozen design/coordinate provenance.")
}
root_moments <- app_gft_moment_initializer(root_original,design)
old <- app_read_csv(old_manifest_path)
if (nrow(old)!=18L || anyDuplicated(old$run_id)) app_gft_stop("Frozen source must contain exactly 18 distinct initial family units.")
tasks <- app_glofas_family_transition_tasks()
configs <- vector("list",nrow(tasks))
resolve_source <- function(path) {
  candidates <- unique(c(path,file.path(source_runtime,path),file.path(repo,path)))
  candidates <- candidates[file.exists(candidates)]
  hit <- candidates[normalizePath(candidates,mustWork=TRUE) %in% normalizePath(evidence$path,mustWork=TRUE)]
  if (length(hit)!=1L) app_gft_stop("Frozen config input is missing or ambiguous: ",path)
  normalizePath(hit,mustWork=TRUE)
}
read_quantile_models <- function(path) {
  grid <- app_read_csv(path)
  if (!"model_family" %in% names(grid)) app_gft_stop("Source model grid has no family labels.")
  grid[grid$model_family=="qdesn_glofas_discrepancy",,drop=FALSE]
}
for (i in seq_len(nrow(tasks))) {
  task <- tasks[i,,drop=FALSE]
  family <- if (task$model_class=="multiquantile") paste0("joint_",task$likelihood,"_rhs_vb") else
    paste0("independent_",task$likelihood,"_rhs_vb")
  selected <- which(old$part4_family==family)
  if (task$model_class=="independent") {
    selected <- selected[vapply(selected,function(j) {
      grid <- read_quantile_models(resolve_source(old$model_grid_path[j]))
      nrow(grid)==1L && abs(as.numeric(grid$quantile_level)-task$tau)<1e-12
    },logical(1L))]
  }
  if (length(selected)!=1L) app_gft_stop("No unique frozen source configuration for ",task$task_id)
  j <- selected[1L]
  cfg_path <- resolve_source(old$config_path[j])
  grid_path <- resolve_source(old$model_grid_path[j])
  cfg <- app_read_config(cfg_path)
  grid <- read_quantile_models(grid_path)
  if (any(tolower(grid$likelihood_family)!=task$likelihood) ||
      any(!vapply(grid$coefficient_prior,app_map_qdesn_prior,character(1L)) %in% c("rhs","rhs_ns"))) app_gft_stop("Source family/prior mismatch.")
  if (task$model_class=="multiquantile" && !identical(sort(as.numeric(grid$quantile_level)),
      app_glofas_family_transition_contract()$tau)) app_gft_stop("Source MQ grid differs from the frozen seven levels.")
  seed <- as.integer(grid$reservoir_seed[1L])
  base_args <- app_make_qdesn_discrepancy_vb_args(cfg,"rhs_ns",seed,task$likelihood)
  controls <- cfg$unit_member_execution %||% app_glofas_unit_member_default_controls()
  fresh_args <- app_glofas_family_transition_controls(base_args,controls)
  configs[[i]] <- list(task_id=task$task_id,seed=seed,vb_args=fresh_args,controls=controls,
    historical_source_job_id=old$run_id[j],source_config_sha256=app_sha256_file(cfg_path),
    source_model_grid_sha256=app_sha256_file(grid_path),
    prior_sha256=app_gft_hash(fresh_args[c("beta_rhs","alpha_rhs","beta_ridge","prior_sigma")]),
    source_evidence_manifest_sha256=args$evidence_manifest_sha256,
    source_design_sha256=frozen_design_sha256)
}
source_head <- system2("git",c("rev-parse","HEAD"),stdout=TRUE)
source_tree <- system2("git",c("rev-parse","HEAD^{tree}"),stdout=TRUE)
# Target identity excludes operational host, claim nonce, retries and output paths.
target_sha <- app_gft_hash(list(contract=app_glofas_family_transition_contract(),
  source_design_sha256=frozen_design_sha256,
  task_models=lapply(configs,function(x) x[c("task_id","prior_sha256","source_model_grid_sha256")]),
  source_manifest_sha256=args$source_manifest_sha256))
# Recheck once after all read-only construction. The sixteen task records use
# this same authenticated immutable design, not sixteen additional4GB reads.
if (!identical(app_sha256_file(frozen_design_path),frozen_design_sha256)) {
  app_gft_stop("Frozen source design changed during preparation; no output written.")
}
for (d in c("objects","configs","requests","control_tasks","results","manifests")) app_ensure_dir(file.path(out,d))
design_path <- file.path(out,"objects/shared_truth_free_design.rds")
app_glofas_part4_atomic_save_rds(app_latent_path_drop_runtime_cache(design,compact=FALSE),design_path)
input_paths <- design_path
input_roles <- "truth_free_shared_design"
root_path <- ""
if (nzchar(args$root_initializer)) {
  compact <- list(summary=list(theta_mean=root_moments$theta_mean,theta_cov=root_moments$theta_cov,
    y_future_mean=root_moments$y_future_mean,y_future_cov=root_moments$y_future_cov),
    likelihood_family="normal",source_sha256=app_sha256_file(root_source),
    source_design_sha256=frozen_design_sha256,
    source_state_contract_hash=root_original$state_contract_hash)
  root_path <- file.path(out,"objects/root_initializer_moments.rds")
  app_glofas_part4_atomic_save_rds(compact,root_path)
  input_paths <- c(input_paths,root_path)
  input_roles <- c(input_roles,"compact_initial_moments")
}
for (i in seq_len(nrow(tasks))) {
  configs[[i]]$posterior_target_sha256 <- target_sha
  path <- file.path(out,"configs",paste0(tasks$task_id[i],".rds"))
  app_glofas_part4_atomic_save_rds(configs[[i]],path)
  tasks$config_relative_path[i] <- paste0("configs/",tasks$task_id[i],".rds")
  input_paths <- c(input_paths,path)
  input_roles <- c(input_roles,"transition_task_configuration")
}
input_path <- file.path(out,"manifests/input_manifest.csv")
app_write_csv(app_gft_manifest(input_paths,input_roles,root=out),input_path)
input_sha <- app_sha256_file(input_path)
tasks$posterior_target_sha256 <- target_sha
tasks$input_manifest_sha256 <- input_sha
tasks$source_manifest_sha256 <- args$source_manifest_sha256
tasks$plan_sha256 <- args$plan_sha256
task_path <- file.path(out,"manifests/task_manifest.csv")
app_write_csv(tasks,task_path)
task_sha <- app_sha256_file(task_path)
for (i in seq_len(nrow(tasks))) {
  task <- tasks[i,,drop=FALSE]
  artifact_keys <- c("fit","forecast_quantiles","raw_crossings","target_receipt","artifact_manifest","progress")
  request <- list(schema_version="glofas_family_transition_request_v1",allow_launch=FALSE,
    workflow="glofas_family_transition",authorization_sha256="",
    task_id=task$task_id,routing_id="UNASSIGNED_NOT_AUTHORIZED",rng_namespace=task$rng_namespace,
    source_commit=source_head,source_tree=source_tree,source_manifest_path=source_manifest,
    source_manifest_sha256=args$source_manifest_sha256,posterior_target_sha256=target_sha,
    input_root=out,input_manifest_path=input_path,input_manifest_sha256=input_sha,
    task_manifest_path=task_path,task_manifest_sha256=task_sha,plan_sha256=args$plan_sha256,
    design_path=design_path,config_path=file.path(out,task$config_relative_path),
    root_initializer_path=if (task$task_id=="gft-al-p050") root_path else "",
    host="UNASSIGNED",resource_budget=list(max_threads=1L,max_memory_mb=NULL,max_wall_seconds=NULL,max_output_bytes=NULL),
    prerequisites=list(),ledger_path="",claim_ticket_path="",claim_ticket_sha256="",
    expected_output_keys=as.list(artifact_keys),expected_output_keys_sha256=app_gft_hash(sort(artifact_keys)),
    coordinator_source_root="",coordinator_request_path="",coordinator_ticket_path="",
    coordinator_authorization_path="",coordinator_source_manifest_path="",coordinator_ledger_path="",
    output_root=file.path(out,"results",task$task_id))
  app_write_json(request,file.path(out,"requests",paste0(task$task_id,".template.json")))
  deps <- if (nzchar(task$dependencies)) strsplit(task$dependencies,"|",fixed=TRUE)[[1L]] else character()
  control <- request[c("task_id","workflow","routing_id","rng_namespace","source_commit","source_tree",
    "source_manifest_sha256","posterior_target_sha256","input_manifest_sha256","task_manifest_sha256",
    "expected_output_keys","expected_output_keys_sha256")]
  control$schema_version <- "forecast_transition_task_v1"
  control$routing_revision <- 1L
  control$dispatch_argv_sha256 <- NULL
  control$prerequisites <- lapply(deps,function(id) list(task_id=id,
    task_manifest_sha256=task_sha,posterior_target_sha256=target_sha))
  control$status <- "TEMPLATE_NO_FROZEN_ROUTE_OR_DISPATCH_NOT_LAUNCHABLE"
  app_write_json(control,file.path(out,"control_tasks",paste0(task$task_id,".template.json")))
}
app_write_csv(data.frame(model=c("normal_ridge","normal_rhs"),
  status="blocked_pending_complete_identity_comparison",reuse_authorized=FALSE),
  file.path(out,"manifests/normal_reuse_decision.csv"))
app_write_json(list(schema_version="glofas_family_transition_preparation_v1",
  status="PREPARED_NOT_AUTHORIZED_NO_LAUNCH",allow_launch=FALSE,production_fits_launched=0L,
  new_quantile_refits=16L,normal_reuse_verified=0L,normal_reuse_blocked=2L,
  source_commit=source_head,source_tree=source_tree,source_manifest_sha256=args$source_manifest_sha256,
  input_manifest_sha256=input_sha,posterior_target_sha256=target_sha,
  task_manifest_sha256=task_sha,plan_sha256=args$plan_sha256,
  reporting=app_glofas_family_transition_contract()$response_summary,
  historical_parts_1_3_and_pricefm_changed=FALSE),file.path(out,"PREPARED_NO_LAUNCH.json"))
cat("PREPARED_NOT_AUTHORIZED_NO_LAUNCH\n",out,"\n")
