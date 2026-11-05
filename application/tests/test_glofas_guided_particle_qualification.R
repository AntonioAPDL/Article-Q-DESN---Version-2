# Reduced generated audit plus immutable text-only Git receipt fixture.
local({
  source("scripts/audit_glofas_guided_particle_qualification.R",local=TRUE)
  checks <- 0L
  ok <- function(value) {stopifnot(isTRUE(value));checks<<-checks+1L}
  reject <- function(expr) ok(inherits(try(force(expr),silent=TRUE),"try-error"))
  paths <- gpgqa_sources(); hashes <- tools::sha256sum(paths)
  ok(length(paths)==10L&&!anyDuplicated(paths)&&all(grepl("\\.R$",paths)))
  result <- gpgqa_compute(hashes,counts=c(1L,4L),replicates=2L)
  rows <- result$tables$particle_records.csv; summary <- result$tables$particle_summary.csv
  guided <- rows$method=="guided"
  ok(nrow(rows)==36L&&sum(guided)==24L&&sum(!guided)==12L&&nrow(summary)==18L)
  ok(all(rows$complete)&&all(is.finite(rows$log_error))&&all(nzchar(rows$failure)==FALSE))
  ok(all(abs(rows$log_error[guided])<=1e-8)&&result$exact_affine_reference_passed)
  ok(any(abs(rows$log_error[!guided])>1e-8))
  ok(all(rows$minimum_member_stage_ESS>=1)&&all(rows$minimum_initial_ancestors>=1)&&
    all(rows$elapsed_seconds>=0)&&all(rows$CPU_seconds>=0)&&all(rows$callback_calls>0))
  ok(all(rows$declared_minimum_ESS==pmin(2,rows$particles))&&
    all(rows$declared_minimum_ancestors==pmin(2,rows$particles))&&
    all(is.finite(rows$minimum_post_correction_ESS[guided]))&&
    all(is.na(rows$minimum_post_correction_ESS[!guided])))
  ok(all(rows$seed==2026111000L+100L*rows$point+rows$replicate)&&
    identical(sort(unique(rows$context)),c("strong","weak")))
  ok(result$controls$expected_guided_runs==24L&&result$controls$expected_bootstrap_runs==12L&&
    result$controls$registered_test_reduced_budget&&result$controls$absolute_affine_log_evidence_error==1e-8)
  ok(identical(result$controls$sigma_Y,c(.2,.5,1))&&identical(result$controls$sigma_G,c(.8,1,1.2)))
  ok(all(result$tables$generated_members.csv$member%in%1:51)&&
    nrow(result$tables$generated_members.csv)==102L)
  ok(!result$flags$application_qualified&&!result$flags$native_launch_authorized&&
    !result$flags$publication_authorized&&!result$flags$production_launch_authorized&&
    !result$flags$full_posterior_accuracy_qualified&&!result$flags$existing_results_changed&&
    result$flags$application_fits==0L&&result$flags$future_truth_reads==0L&&
    result$flags$original_RDS_reads==0L&&result$flags$original_RDS_hashes==0L&&result$flags$original_RDS_stats==0L)
  reject(gpgqa_compute(hashes,counts=c(1L,1L),replicates=2L))
  reject(gpgqa_compute(hashes,counts=0L,replicates=2L))
  reject(gpgqa_compute(hashes,counts=257L,replicates=2L))
  reject(gpgqa_compute(hashes,counts=4L,replicates=1L))
  bad <- hashes; bad[1L] <- paste(rep("0",64),collapse="")
  reject(gpgqa_compute(bad,counts=4L,replicates=2L))
  reject(gpgqa_main(c("--output")))

  original <- normalizePath(".",mustWork=TRUE)
  fixture <- tempfile("gpgqa_text_git_fixture_"); dir.create(fixture)
  on.exit({setwd(original);unlink(fixture,recursive=TRUE)},add=TRUE)
  for(path in paths) {
    dir.create(dirname(file.path(fixture,path)),recursive=TRUE,showWarnings=FALSE)
    ok(file.copy(file.path(original,path),file.path(fixture,path)))
  }
  writeLines("local_trackers/",file.path(fixture,".gitignore"))
  dir.create(file.path(fixture,"local_trackers"))
  git <- function(args) {
    x <- system2("git",c("-C",shQuote(fixture),args),stdout=TRUE,stderr=TRUE)
    stopifnot(is.null(attr(x,"status")));invisible(x)
  }
  git(c("init","-q"));git(c("add","--all"))
  git(c("-c",shQuote("user.name=Generated fixture"),"-c","user.email=fixture@example.invalid",
    "commit","-q","-m",shQuote("Generated text-only guide audit fixture")))
  setwd(fixture); before <- gpgqa_state()
  ok(identical(before$sha256,hashes)&&grepl("^[a-f0-9]{40}$",before$commit))
  source("scripts/audit_glofas_variance_auxiliary_references.R",local=TRUE)
  destination <- file.path(fixture,"local_trackers","guided")
  reject(gvaa_fresh_output(file.path(fixture,"not_ignored")))
  reject(gvaa_fresh_output(file.path(fixture,"local_trackers","..","escape")))
  link <- file.path(fixture,"local_trackers","linked")
  ok(file.symlink(file.path(fixture,"local_trackers"),link))
  reject(gvaa_fresh_output(file.path(link,"guided")))
  changed <- paths[1L]
  writeLines(c(readLines(changed,warn=FALSE),"# generated dirty-source negative"),changed)
  reject(gpgqa_main(c("--output",destination)))
  ok(!file.exists(destination))
  ok(file.copy(file.path(original,changed),changed,overwrite=TRUE))
  ok(identical(before,gpgqa_state()))
  inconsistent <- result; inconsistent$tables$particle_records.csv$complete[1L] <- FALSE
  reject(gpgqa_write(inconsistent,destination,before))
  ok(!file.exists(destination))
  receipt <- gpgqa_write(result,destination,before)
  ok(receipt$exact_affine_reference_passed&&receipt$source_commit==before$commit&&
    receipt$source_tree==before$tree&&receipt$source_unchanged_before_after&&
    !receipt$native_launch_authorized&&!receipt$publication_authorized)
  manifest <- read.csv(file.path(destination,"artifact_manifest.csv"),stringsAsFactors=FALSE)
  ok(nrow(manifest)==9L&&all(grepl("\\.(csv|json)$",manifest$relative_path)))
  ok(identical(manifest$sha256,unname(tools::sha256sum(file.path(destination,manifest$relative_path)))))
  written <- read.csv(file.path(destination,"particle_records.csv"),stringsAsFactors=FALSE)
  ok(nrow(written)==36L&&all(written$complete)&&all(!written$production_qualified))
  reject(gpgqa_write(result,destination,before))
  ok(identical(before,gpgqa_state()))
  # Failure receipts are retained, not overwritten or silently dropped.
  failed <- result; failed$exact_affine_reference_passed <- FALSE
  failed$tables$particle_records.csv$complete[1L] <- FALSE
  failed$tables$particle_records.csv$failure[1L] <- "generated deliberate failure"
  failed$tables$particle_summary.csv <- gpgqa_summarize(failed$tables$particle_records.csv)
  failed_output <- file.path(fixture,"local_trackers","failed")
  failed_receipt <- gpgqa_write(failed,failed_output,before)
  ok(!failed_receipt$exact_affine_reference_passed&&
    failed_receipt$status=="AFFINE_H2_REFERENCE_FAILED_NATIVE_NOT_QUALIFIED")
  saved <- read.csv(file.path(failed_output,"particle_records.csv"),stringsAsFactors=FALSE)
  ok(!saved$complete[1L]&&saved$failure[1L]=="generated deliberate failure")
  cat(sprintf("GLOFAS_GUIDED_PARTICLE_QUALIFICATION_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
