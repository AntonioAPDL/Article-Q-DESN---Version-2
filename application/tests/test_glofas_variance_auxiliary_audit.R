# Fast registered fixture: reduced particle budget and text-only Git fixture.
local({
  source("scripts/audit_glofas_variance_auxiliary_references.R",local=TRUE)
  checks<-0L
  ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L}
  reject<-function(expr)ok(inherits(try(force(expr),silent=TRUE),"try-error"))
  paths<-gvaa_sources();hashes<-tools::sha256sum(paths)
  ok(length(paths)==9L&&!anyDuplicated(paths)&&all(grepl("\\.R$",paths)))
  small<-gvaa_compute("particle",hashes,counts=8L,replicates=4L)
  records<-small$tables$particle_records.csv;summary<-small$tables$particle_summary.csv
  ok(nrow(records)==24L&&nrow(summary)==6L&&identical(sort(unique(records$context)),c("strong","weak")))
  ok(all(records$particles==8L)&&length(unique(records$point))==3L&&
    all(records$seed==2026111000L+100L*records$point+records$replicate))
  ok(all(records$complete)&&all(is.finite(records$exact_log_evidence))&&
    all(is.finite(records$estimated_log_evidence))&&all(records$elapsed_seconds>=0))
  ok(all(c("empirical_Jensen_gap","mean_log_estimate_MCSE","minimum_ESS")%in%c(names(summary),names(records))))
  ok(small$controls$registered_test_reduced_budget&&small$controls$expected_runs==24L&&
    !small$flags$application_qualified&&!small$flags$full_posterior_accuracy_qualified&&
    !small$flags$native_launch_authorized&&!small$flags$production_launch_authorized&&
    !small$flags$publication_authorized&&small$flags$original_RDS_reads==0L&&small$flags$original_RDS_stats==0L)
  ok(identical(small$controls$scale_Y,c(.2,.5,1))&&identical(small$controls$scale_G,c(.8,1,1.2)))
  ok(small$elapsed_seconds>=0&&all(small$tables$particle_context_timing.csv$conditional_runs==12L))
  reject(gvaa_compute("unknown",hashes,counts=8L,replicates=4L))
  reject(gvaa_compute("particle",hashes,counts=8L,replicates=3L))
  reject(gvaa_compute("particle",hashes,counts=c(8L,8L),replicates=4L))
  bad<-hashes;names(bad)[1L]<-"unknown";reject(gvaa_compute("particle",bad,counts=8L,replicates=4L))

  # A source-frozen entrypoint test in a disposable local text-only repository.
  # No large/default particle campaign is repeated in this test.
  original_root<-normalizePath(".",mustWork=TRUE)
  fixture<-tempfile("gvaa_text_git_fixture_");dir.create(fixture)
  on.exit({setwd(original_root);unlink(fixture,recursive=TRUE)},add=TRUE)
  for(path in paths){dir.create(dirname(file.path(fixture,path)),recursive=TRUE,showWarnings=FALSE)
    ok(file.copy(file.path(original_root,path),file.path(fixture,path)))}
  writeLines("local_trackers/",file.path(fixture,".gitignore"))
  dir.create(file.path(fixture,"local_trackers"))
  run_git<-function(args){out<-system2("git",c("-C",shQuote(fixture),args),stdout=TRUE,stderr=TRUE)
    stopifnot(is.null(attr(out,"status")));invisible(out)}
  run_git(c("init","-q"));run_git(c("add","--all"))
  run_git(c("-c",shQuote("user.name=Generated fixture"),"-c","user.email=fixture@example.invalid",
    "commit","-q","-m",shQuote("Generated text-only audit fixture")))
  setwd(fixture)
  before<-gvaa_source_state()
  ok(identical(before$sha256,hashes)&&nzchar(before$commit)&&nzchar(before$tree))
  destination<-file.path(fixture,"local_trackers","predictive")
  ok(identical(gvaa_fresh_output(destination),destination)&&!file.exists(destination))
  reject(gvaa_fresh_output(file.path(fixture,"not_ignored")))
  reject(gvaa_fresh_output(file.path(fixture,"local_trackers","..","escape")))
  reject(gvaa_main(c("--part","particle","--output")))
  dir.create(file.path(fixture,"local_trackers","existing"))
  reject(gvaa_main(c("--part","particle","--output",file.path(fixture,"local_trackers","existing"))))
  target<-file.path(fixture,"local_trackers","existing")
  linked<-file.path(fixture,"local_trackers","linked")
  ok(file.symlink(target,linked));reject(gvaa_fresh_output(linked))
  reject(gvaa_fresh_output(file.path(linked,"child")))
  changed<-paths[1L]
  writeLines(c(readLines(changed,warn=FALSE),"# generated dirty-source negative fixture"),changed)
  reject(gvaa_main(c("--part","particle","--output",file.path(fixture,"local_trackers","dirty"))))
  ok(!file.exists(file.path(fixture,"local_trackers","dirty")))
  ok(file.copy(file.path(original_root,changed),changed,overwrite=TRUE))
  ok(identical(before,gvaa_source_state()))
  receipt<-gvaa_main(c("--part","predictive","--output",destination))
  ok(receipt$source_commit==before$commit&&receipt$source_tree==before$tree&&
    receipt$part=="predictive"&&!receipt$application_qualified&&!receipt$native_backend_qualified&&
    !receipt$full_posterior_accuracy_qualified&&!receipt$publication_authorized)
  result<-read.csv(file.path(destination,"predictive_summary.csv"),stringsAsFactors=FALSE)
  ok(identical(result$fixture,c("no_members","moderate_51","concentrated_51"))&&nrow(result)==3L&&
    all(c("primary_quantile_absolute_error","maximum_grid_CDF_error","reference_family_KL")%in%names(result)))
  gates<-read.csv(file.path(destination,"prespecified_gates.csv"),stringsAsFactors=FALSE)
  ok(gates$threshold[gates$gate=="primary_quantile_absolute_error"]==.001&&
    gates$threshold[gates$gate=="maximum_grid_CDF_error"]==.01)
  manifest<-read.csv(file.path(destination,"artifact_manifest.csv"),stringsAsFactors=FALSE)
  ok(all(grepl("\\.(csv|json)$",manifest$relative_path))&&
    identical(manifest$sha256,unname(tools::sha256sum(file.path(destination,manifest$relative_path)))))
  reject(gvaa_main(c("--part","predictive","--output",destination)))
  ok(identical(before,gvaa_source_state()))
  cat(sprintf("GLOFAS_VARIANCE_AUXILIARY_AUDIT_PASS checks=%d original_reads=0 application_fits=0\n",checks))
})
