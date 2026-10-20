#!/usr/bin/env Rscript
options(stringsAsFactors = FALSE, digits = 17)
script <- normalizePath(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1L]))
root <- normalizePath(file.path(dirname(script), "..")); setwd(root)
args <- commandArgs(TRUE)
arg <- function(flag) { i <- match(flag, args); if(is.na(i)) NULL else args[i + 1L] }
sha <- function(path) unname(tools::sha256sum(path)[[1L]])
checks <- list()
check <- function(label, ok) {
  checks[[length(checks) + 1L]] <<- data.frame(check = label, pass = isTRUE(ok))
  if(!isTRUE(ok)) stop(label, call. = FALSE)
}
manifest <- jsonlite::read_json("tables/independent_forecast_300_500_article_manifest_v1.json", simplifyVector = TRUE)
for (group in c("sources", "outputs")) {
  x <- unlist(manifest[[group]])
  check(paste(group, "hashes"), identical(unname(vapply(names(x), sha, character(1))), unname(x)))
}
policy <- jsonlite::read_json("application/config/independent_forecast_300_500_v1.json", simplifyVector = TRUE)
d <- read.csv("tables/independent_forecast_300_500_v1.csv")
fit <- read.csv("tables/independent_fit_preserved_300_500_v1.csv")
old <- read.csv("tables/qdesn_validation_500obs_dgp_oracle_figure_data_v14.csv")
key <- function(x, window = TRUE) do.call(paste,c(x[c("inference", "family", "tau", "model_variant", "metric_role",if(window) "cutoff")],sep="|"))
expected <- expand.grid(inference = "mcmc",family=c("normal","laplace","gausmix"),tau=c(.05,.25,.5),
  model_variant=c("dqlm","exdqlm","qdesn_al_rhs_ns","qdesn_exal_rhs_ns"),metric_role=c("forecast_mae","forecast_check"),cutoff=c(300L,500L))
check("complete approved forecast surface", nrow(d)==144L && !anyDuplicated(key(d)) && setequal(key(d),key(expected)))
check("policy forbids inference and retains provenance", !policy$allow_refit && !policy$allow_forecast_resimulation &&
  !policy$allow_winner_reselection && policy$retain_historical_evidence && policy$retrospective_scope_change &&
  policy$primary_cutoff==300L && policy$sensitivity_cutoff==500L && policy$deprecated_status=="DEPRECATED_FOR_REPORTING")
check("exact target and origin counts", all(d$forecast_pairs==d$cutoff) && all(d$forecast_origins==ceiling(d$cutoff/30)) &&
  all(d$first_target==9001L) && all(d$last_target==9000L+d$cutoff) && all(d$last_lead==ifelse(d$cutoff==300L,30L,20L)))
check("finite balanced posterior summaries", all(is.finite(as.matrix(d[c("posterior_mean","cri_lower","posterior_median","cri_upper")])) ) &&
  all(d$n_chains==3L) && all(d$cri_lower<=d$posterior_median) && all(d$posterior_median<=d$cri_upper))
source_groups <- split(d$replay_id,key(d,FALSE))
check("same selected source across windows", all(vapply(source_groups,function(x) length(unique(x))==1L,logical(1))))
oldfit <- old[match(key(fit,FALSE),key(old,FALSE)), ]
fields <- c("posterior_mean","cri_lower","posterior_median","cri_upper","n_draws","n_chains")
check("all MCMC and VB fit summaries unchanged",nrow(fit)==72L && all(fit$metric_role=="fit_rmse") &&
  identical(unname(as.matrix(fit[fields])),unname(as.matrix(oldfit[fields]))) && identical(fit$replay_id,oldfit$replay_id))
vb <- read.csv("tables/independent_forecast_300_500_vb_coverage.csv")
check("VB forecast omission explicit and complete", nrow(vb)==72L && length(unique(vb$replay_id))==36L &&
  all(vb$status=="OMITTED_NO_AUTHENTIC_PREFIX_DRAWS"))
replay <- read.csv("tables/independent_forecast_300_500_replay_checks.csv")
check("independent prefix numerical replay",nrow(replay)==144L && all(replay$pass) && max(replay$maximum_error)<=1e-6)
reference <- read.csv("tables/independent_forecast_300_500_dgp_references.csv")
check("prefix DGP references", nrow(reference)==36L && all(reference$expected_quadrature_error<=1e-6) &&
  all(reference$plot_reference_value[reference$metric_role=="forecast_mae"]==0) &&
  all(reference$expectation_time_constant))
validation <- arg("--validation-root")
if (!is.null(validation)) {
  p <- file.path(validation,"validation/fitforecast_v2/promotions/independent_forecast_300_500_v1")
  x <- read.csv(file.path(p,"forecast_metric_intervals.csv")); x <- x[match(key(d),key(x)), ]
  check("validation packet and article numbers identical", max(abs(as.matrix(d[fields])-as.matrix(x[fields])))<=1e-6 &&
    identical(d$replay_id,x$replay_id))
}
effective <- function(path, seen=character()) {
  if(path %in% seen) return(character())
  text <- readLines(path,warn=FALSE); text <- sub("(?<!\\\\)%.*$","",text,perl=TRUE)
  inputs <- unlist(regmatches(text,gregexpr("\\\\input\\{[^}]+\\}",text,perl=TRUE)))
  if (!length(inputs)) return(path)
  inputs <- sub("^\\\\input\\{(.*)\\}$","\\1",inputs)
  inputs <- inputs[!grepl("\\\\",inputs)]
  inputs <- ifelse(grepl("[.]tex$",inputs),inputs,paste0(inputs,".tex"))
  inputs <- inputs[file.exists(inputs)]
  unique(c(path,unlist(lapply(inputs,function(p) effective(p,c(seen,path))))))
}
main_files <- effective("main.tex"); supp_files <- effective("qdesn-supplement.tex")
check("main selects primary forecast wrapper", "tables/independent_train500_eval300_mcmc_figures_v1.tex" %in% main_files)
primary_wrapper <- paste(readLines("tables/independent_train500_eval300_mcmc_figures_v1.tex"), collapse = "\n")
check("main retains check loss only", grepl("eval300_mcmc_forecast_check_v1.pdf", primary_wrapper, fixed = TRUE) &&
  !grepl("eval300_mcmc_forecast_mae_v1.pdf", primary_wrapper, fixed = TRUE) &&
  !"tables/independent_train500_eval300_mcmc_mae_figure_v1.tex" %in% main_files)
check("primary recovery and calibration are supplementary only",
  all(c("tables/independent_train500_eval300_mcmc_mae_figure_v1.tex",
    "tables/independent_forecast_calibration_figure_v1.tex",
    "tables/independent_forecast_calibration_table_v1.tex") %in% supp_files) &&
  !any(c("tables/independent_forecast_calibration_figure_v1.tex",
    "tables/independent_forecast_calibration_table_v1.tex") %in% main_files))
check("sensitivity figures are supplementary only", !"tables/independent_train500_eval500_mcmc_figures_v1.tex" %in% main_files &&
  "tables/independent_train500_eval500_mcmc_figures_v1.tex" %in% supp_files)
retired <- c("tables/qdesn_validation_500obs_v14_paired_metric_interval_tables.tex",
  "tables/qdesn_validation_mcmc_five_chain_sensitivity.tex", "tables/qdesn_pro_review_mcmc_forecast_figures.tex")
check("retired forecast wrappers are inactive", !any(retired %in% c(main_files,supp_files)))
texts <- paste(unlist(lapply(unique(c(main_files,supp_files)),readLines,warn=FALSE)),collapse="\n")
check("no old IND forecast graphics are selected", !grepl("independent_simulation/(qdesn_pro_review_mcmc_forecast|qdesn_validation_500obs_v14_mcmc_forecast)",texts))
builder <- paste(readLines("scripts/build_qdesn_pro_review_presentation.R"),collapse="\n")
check("legacy builder routes to current authority",grepl("if (current_ind_policy)",builder,fixed=TRUE) &&
  grepl("scripts/build_independent_forecast_300_500_v1.R",builder,fixed=TRUE) && grepl("if (current_ind_policy && i <= 3L) next",builder,fixed=TRUE))
main <- paste(readLines("main.tex"),collapse="\n"); supplement <- paste(readLines("qdesn-supplement.tex"),collapse="\n")
check("retrospective scope change disclosed",grepl("adopted after exploratory assessment",main,fixed=TRUE) &&
  grepl("revised after inspecting",supplement,fixed=TRUE))
check("MAE and empirical frequencies retain distinct targets",
  grepl("rather than error in", supplement, fixed = TRUE) &&
  grepl("predicting individual responses", supplement, fixed = TRUE) &&
  grepl("model-specific cross-time draw construction", supplement, fixed = TRUE) &&
  grepl("specification used for check loss", supplement, fixed = TRUE) &&
  grepl("not widths of future-response prediction intervals", supplement, fixed = TRUE))
check("obsolete point-path sensitivity not actively claimed", !grepl("subsec:supp-independent-five-chain-sensitivity",supplement,fixed=TRUE))
# The a96e6616 statistical-language revision deliberately edits prose outside
# the independent study. Its bounded replacement for the old 53e4912 blanket
# text-equality guard freezes every scientific table CSV, all PriceFM sections
# and files, source model code, and the excluded PriceFM presentation receipts.
# Keep the independent numbers, source identities, and scope checks above;
# an editorial change must not become an unreviewed scientific replacement.
language_check <- system2(file.path(R.home("bin"), "Rscript"),
  shQuote("scripts/check_qdesn_statistical_language_revision.R"),
  stdout = TRUE, stderr = TRUE)
check("bounded editorial scope preserves scientific inputs and PriceFM authority",
  is.null(attr(language_check, "status")) && any(grepl(
    "QDESN_STATISTICAL_LANGUAGE_REVISION_CHECK=PASS", language_check, fixed = TRUE)))
upload <- readLines("overleaf/article_files.txt"); upload <- upload[nzchar(upload)&!startsWith(upload,"#")]
check("projection excludes deprecated independent numerical panels",
  !any(grepl("qdesn_validation_500obs_v14|qdesn_validation_mcmc_five_chain|qdesn_pro_review_mcmc_forecast",upload)))
build_root <- arg("--build-root")
if (!is.null(build_root)) for (doc in c("main","qdesn-supplement")) {
  fls <- readLines(file.path(build_root,doc,paste0(doc,".fls")),warn=FALSE)
  actual <- unique(sub("^INPUT ","",fls[startsWith(fls,"INPUT ")]))
  check(paste(doc,"actual TeX recorder excludes deprecated IND forecast PDFs"),
    !any(grepl("/independent_simulation/(qdesn_pro_review_mcmc_forecast|qdesn_validation_500obs_v14_mcmc_forecast)",actual)))
  asset_names <- basename(actual)
  if (doc == "main") {
    check("main recorder selects primary check loss without recovery/calibration",
      "independent_train500_eval300_mcmc_forecast_check_v1.pdf" %in% asset_names &&
      !any(c("independent_train500_eval300_mcmc_forecast_mae_v1.pdf",
        "independent_forecast_calibration_v1.pdf") %in% asset_names))
  } else {
    check("supplement recorder selects recovery sensitivity and calibration",
      all(c("independent_train500_eval300_mcmc_forecast_mae_v1.pdf",
        "independent_train500_eval500_mcmc_forecast_mae_v1.pdf",
        "independent_train500_eval500_mcmc_forecast_check_v1.pdf",
        "independent_forecast_calibration_v1.pdf") %in% asset_names))
  }
  log <- readLines(file.path(build_root,doc,paste0(doc,".log")),warn=FALSE)
  check(paste(doc,"no unresolved references or citations"),!any(grepl("undefined|multiply defined|There were undefined|Rerun to get",log)))
  check(paste(doc,"no overfull boxes"),!any(grepl("Overfull",log)))
}
out <- "local_trackers/independent_forecast_300_500_v1"
dir.create(out,recursive=TRUE,showWarnings=FALSE)
write.csv(do.call(rbind,checks),file.path(out,"article_checks.csv"),row.names=FALSE)
jsonlite::write_json(list(status="PASS",checks=length(checks),validation_packet_checked=!is.null(validation),
  manuscript_build_checked=!is.null(build_root)),file.path(out,"article_verification.json"),auto_unbox=TRUE,pretty=TRUE)
cat("PASS",length(checks),"article authority checks\n")
