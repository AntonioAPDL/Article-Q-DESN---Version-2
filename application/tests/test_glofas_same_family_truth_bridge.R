# Pure/generated fixtures only. Never read the retained 862-byte truth RDS.
local({
source("scripts/glofas_same_family_truth_bridge.R")
source("scripts/build_glofas_same_family_article_projection.R")
checks<-0L
ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L;invisible(TRUE)}
reject<-function(x,pattern=NULL) {
  e<-tryCatch({force(x);NULL},error=identity)
  ok(inherits(e,"error"))
  if(!is.null(pattern)) {
    if(!grepl(pattern,conditionMessage(e),fixed=TRUE))
      stop("Check ",checks," expected '",pattern,"'; received '",conditionMessage(e),"'.")
    ok(TRUE)
  }
}
clone<-function(x)unserialize(serialize(x,NULL))
pin<-function(p)list(path=normalizePath(p,mustWork=TRUE),size_bytes=as.numeric(file.info(p)$size),
  sha256=unname(tools::sha256sum(p)))
json<-function(x,p)jsonlite::write_json(x,p,auto_unbox=TRUE,pretty=TRUE,digits=17,null="null")
tmp<-tempfile("gsc_truth_bridge_SYNTHETIC_");dir.create(tmp)
on.exit(unlink(tmp,recursive=TRUE),add=TRUE)
truth<-list(panel=data.frame(target_date=gsc_dates(),y_transformed=seq(1,2,length.out=28)),
  role="post_fit_scoring_sidecar",future_truth_used_in_fit=FALSE,future_truth_rows=28L)
rows<-gst_truth_rows(truth)
ok(identical(names(rows),c("target_date","horizon","y_transformed"))&&nrow(rows)==28L)
long<-truth;long$panel<-data.frame(target_date=as.Date("2022-12-25")+1:30,
  y_transformed=seq(1,2,length.out=30));long$future_truth_rows<-30L
ok(identical(gst_truth_rows(long)$y_transformed,long$panel$y_transformed[1:28]))
shuffled<-long;shuffled$panel<-shuffled$panel[30:1,]
ok(identical(gst_truth_rows(shuffled),gst_truth_rows(long)))
for(mut in list(function(z){z$role<-"training";z},function(z){z$future_truth_used_in_fit<-TRUE;z},
  function(z){z$future_truth_rows<-30L;z},function(z){z$panel$y_transformed[1]<-NA_real_;z},
  function(z){z$panel$target_date[1]<-z$panel$target_date[2];z},
  function(z){z$panel$target_date[1]<-as.Date("2022-12-25");z},
  function(z){z$panel$horizon<-1:28;z},function(z){z$extra<-1;z},
  function(z){z$panel<-z$panel[-28L,];z},function(z){z$panel$target_date<-as.numeric(z$panel$target_date);z},
  function(z){class(z$panel)<-c("custom","data.frame");z},
  function(z){attr(z$panel,"callback")<-function()stop("must not run");z}))reject(gst_truth_rows(mut(truth)))
ok(identical(gst_truth_interface(list()),"legacy_pinned_csv_v1"))
ok(identical(gst_truth_interface(list(truth_interface_version="legacy_pinned_csv_v1")),"legacy_pinned_csv_v1"))
reject(gst_truth_interface(list(truth_interface_version="unknown")),"interface")
fixed<-gst_truth_identity()
truth_pin<-list(path=file.path(tmp,"part4_scoring_panel_sidecar.rds"),size_bytes=fixed$size_bytes,sha256=fixed$sha256)
ok(gst_truth_pin_identity(truth_pin));ok(!file.exists(truth_pin$path))
bad<-truth_pin;bad$sha256<-strrep("0",64L);reject(gst_truth_pin_identity(bad),"frozen original")
purpose<-list(schema_version="glofas_same_family_truth_bridge_contract_v1",mode="extract_scoring_truth_after_forecast_seal",
  allow_truth_read=TRUE,allow_refit=FALSE,allow_retuning=FALSE,allow_forecast_changes=FALSE,
  allow_publication=FALSE,truth_role="post_fit_scoring_only",truth_rds=truth_pin,
  limits=list(cpu_seconds=60L,wall_seconds=60L,memory_bytes=1024^3,output_bytes=4*1024^2,logical_cpu=28L))
ok(gst_scope(purpose))
reject(gst_scope(c(purpose,list(allow_truth_read=FALSE))),"duplicate")
bad<-purpose;bad$limits<-c(bad$limits,list(cpu_seconds=120L));reject(gst_scope(bad),"duplicate")
for(k in c("allow_refit","allow_retuning","allow_forecast_changes","allow_publication")) {
  bad<-purpose;bad[[k]]<-TRUE;reject(gst_scope(bad),"authority")
}
for(b in list(list(cpu_seconds=1L,wall_seconds=1L),list(logical_cpu=24L),list(wall_seconds=61L),
  list(cpu_seconds=Inf),list(memory_bytes=3*1024^3))) {
  bad<-purpose;for(k in names(b))bad$limits[[k]]<-b[[k]];reject(gst_scope(bad),"budget")
}
argv<-c("/usr/bin/timeout","--signal=TERM","--kill-after=1s","59s","Rscript")
ok(gst_timeout_argv(argv,60L))
bad<-argv;bad[4L]<-"0s";reject(gst_timeout_argv(bad,60L))
bad<-argv;bad[5L]<-"--foreground";reject(gst_timeout_argv(bad,60L))
stat<-function(pid,ppid,pgid,sid)sprintf("%d (generated R) R %d %d %d 0 0 0",pid,ppid,pgid,sid)
ok(gst_group(stat(202,201,201,100),stat(201,200,201,100)))
reject(gst_group(stat(202,201,202,100),stat(201,200,201,100)),"group/session")
reject(gst_group(stat(202,201,201,202),stat(201,200,201,100)),"group/session")
reject(gst_group(stat(202,201,201,100),stat(201,200,200,100)),"group/session")

# An isolated temporary Git fixture authenticates actual source bytes, not
# stubs. It performs no network access or actual bridge/payload execution.
source_root<-file.path(tmp,"source");dir.create(source_root)
relative<-c("scripts/glofas_same_family_truth_bridge.R","scripts/glofas_same_family_closeout.R",
  "application/scripts/386_run_glofas_part4_latent_family_job.R")
for(f in relative) {dir.create(dirname(file.path(source_root,f)),recursive=TRUE,showWarnings=FALSE)
  ok(file.copy(f,file.path(source_root,f)))}
git<-function(args) {
  v<-system2("/usr/bin/git",c("-C",shQuote(source_root),"-c","core.hooksPath=/dev/null",
    "-c","commit.gpgSign=false",args),stdout=TRUE,stderr=TRUE)
  if(!is.null(attr(v,"status")))stop(paste(v,collapse="\n"));unname(v)
}
git("init");git(c("add","--all"));git(c("-c","user.name=GeneratedFixture","-c",
  "user.email=generated@example.invalid","commit","-m","Generated_source_fixture"))
purpose$source_commit<-git(c("rev-parse","HEAD"));purpose$source_tree<-git(c("rev-parse","HEAD^{tree}"))
purpose$source_files<-lapply(file.path(source_root,relative),pin)
ok(gst_source(purpose,source_root))
producer<-function(id)list(task_id=id,state="accepted",numerical_gates_pass=TRUE,
  identity=c(list(task_id=id),gsc_identity(),list(rng_namespace=id,routing_id=paste0("route-",id))),
  claim_nonce=paste0("generated-",id),output_manifest_sha256=strrep("a",64L),
  terminal=list(exit_code=0L,accounting_complete=TRUE,owner_terminated=TRUE,worker_terminated=TRUE,timed_out=FALSE),
  artifacts=lapply(c("fit.rds","forecast_quantiles.csv","raw_crossings.csv","target_receipt.json","progress.csv","artifact_manifest.csv"),
    function(n)list(relative_path=n,path=paste0("/generated/",n),size_bytes=1L,sha256=strrep("b",64L))))
collection<-list(schema_version="glofas_same_family_accepted_collection_v1",status="SIXTEEN_ACCEPTED_PRODUCERS_REVERIFIED",
  producers=lapply(gsc_tasks(),producer),ledger_mutations=0L,fit_objects_loaded=0L,future_truth_read=FALSE,
  article_publication_authorized=FALSE)
forecast<-expand.grid(family=gsc_families(),horizon=1:28,tau=gsc_tau(),stringsAsFactors=FALSE)
forecast$target_date<-as.character(gsc_dates()[forecast$horizon]);forecast$quantile_transformed<-2+qnorm(forecast$tau)
forecast$quantile<-expm1(forecast$quantile_transformed)
bindings<-setNames(lapply(c("normal_manifest","normal_receipt","normal_quantiles","raw_member_derivation","raw_members"),function(n) {
  f<-file.path(tmp,paste0(n,".txt"));writeLines("generated non-truth metadata",f);pin(f)
}),c("normal_manifest","normal_receipt","normal_quantiles","raw_member_derivation","raw_members"))
manifest<-function(root) {
  files<-list.files(root,full.names=TRUE);files<-files[basename(files)!="artifact_manifest.csv"]
  write.csv(data.frame(relative_path=basename(files),size_bytes=as.numeric(file.info(files)$size),
    sha256=unname(tools::sha256sum(files))),file.path(root,"artifact_manifest.csv"),row.names=FALSE)
  pin(file.path(root,"artifact_manifest.csv"))
}
assembly<-function(root) {
  dir.create(root);write.csv(forecast,file.path(root,"quantile_paths.csv"),row.names=FALSE)
  write.csv(gsc_crossings(forecast),file.path(root,"raw_crossings.csv"),row.names=FALSE)
  json(collection,file.path(root,"accepted_producers.json"))
  json(gsc_make_forecast_seal(root,bindings,strrep("d",64L)),file.path(root,"FORECAST_SEAL.json"))
  seal<-pin(file.path(root,"FORECAST_SEAL.json"))
  json(list(schema_version="glofas_same_family_closeout_receipt_v1",status="ASSEMBLED_COMPLETE_GRID_NO_TRUTH_READ",
    mode="assemble",future_truth_read=FALSE,model_selection_or_retuning=FALSE,new_fits=0L,
    article_publication_authorized=FALSE,forecast_seal_sha256=seal$sha256),file.path(root,"DECISION.json"))
  json(list(status="generated assembly"),file.path(root,"progress.json"))
  list(root=root,manifest=manifest(root),seal=seal)
}
a<-assembly(file.path(tmp,"assembly_A"));b<-assembly(file.path(tmp,"assembly_B"))
aa<-gst_assembly(a$root,a$manifest,a$seal);bb<-gst_assembly(b$root,b$manifest,b$seal)
ok(gst_forecasts_equal(aa$seal,bb$seal))
bad<-bb$seal;bad$artifacts[[1L]]$sha256<-strrep("0",64L);reject(gst_forecasts_equal(aa$seal,bad),"changed")
purpose$assembly_root<-a$root;purpose$assembly_manifest<-a$manifest;purpose$assembly_forecast_seal<-a$seal
purpose$output_root<-file.path(tmp,"truth_output");dir.create(purpose$output_root)
provenance<-file.path(tmp,"recorded_source_manifest.csv")
write.csv(data.frame(path="/frozen/source/part4_scoring_panel_sidecar.rds",size_bytes=862,
  sha256=fixed$sha256),provenance,row.names=FALSE)
purpose$truth_provenance_manifest<-pin(provenance)
json(purpose,file.path(tmp,"truth_purpose.json"));purpose_pin<-pin(file.path(tmp,"truth_purpose.json"))
csv<-file.path(purpose$output_root,"scoring_truth.csv");write.csv(rows,csv,row.names=FALSE)
derivation<-list(schema_version="glofas_same_family_scoring_truth_derivation_v1",
  status="SCORING_TRUTH_EXTRACTED_AFTER_COMPLETE_FORECAST_SEAL",source_commit=purpose$source_commit,
  source_tree=purpose$source_tree,contract_sha256=purpose_pin$sha256,source_files=purpose$source_files,
  truth_rds=truth_pin,truth_provenance_manifest=pin(provenance),
  original_materialization=gst_provenance_row(pin(provenance),truth_pin),assembly_root=a$root,
  assembly_manifest=a$manifest,assembly_forecast_seal=a$seal,sealed_forecast_artifacts=aa$seal$artifacts,
  sealed_forecast_input_bindings=aa$seal$input_bindings,csv=pin(csv),original_RDS_deserializations=1L,
  source_panel_rows=28L,retained_rows=28L,retained_dates=as.character(gsc_dates()),horizons=1:28,
  transform="log1p",new_transform_applied=FALSE,
  selection_rule="exact_match_to_all_28_sealed_issued_dates_not_blind_truncation",model_calls=0L,new_fits=0L,
  model_selection_or_retuning=FALSE,forecast_changes=FALSE,publication_authorized=FALSE)
df<-file.path(purpose$output_root,"TRUTH_DERIVATION.json");json(derivation,df)
s<-c(purpose,list(truth_interface_version="authenticated_truth_bridge_v2",truth=pin(csv),
  truth_derivation=pin(df),truth_adapter_purpose=purpose_pin))
ok(is.list(gst_validate_score_truth(s,bb$seal)));ok(!file.exists(truth_pin$path))
for(field in c("source_commit","contract_sha256","selection_rule","transform")) {
  bad<-clone(derivation);bad[[field]]<-"wrong";json(bad,df)
  ss<-s;ss$truth_derivation<-pin(df);reject(gst_validate_score_truth(ss,bb$seal))
}
json(derivation,df);s$truth_derivation<-pin(df)
changed<-forecast;changed$quantile_transformed[1]<-changed$quantile_transformed[1]+.01
changed$quantile[1]<-expm1(changed$quantile_transformed[1]);write.csv(changed,file.path(b$root,"quantile_paths.csv"),row.names=FALSE)
json(gsc_make_forecast_seal(b$root,bindings,strrep("d",64L)),file.path(b$root,"FORECAST_SEAL.json"))
reject(gst_validate_score_truth(s,gsc_verify_forecast_seal(b$root,pin(file.path(b$root,"FORECAST_SEAL.json"))$sha256)),"changed after")
write.csv(forecast,file.path(b$root,"quantile_paths.csv"),row.names=FALSE)
json(gsc_make_forecast_seal(b$root,bindings,strrep("d",64L)),file.path(b$root,"FORECAST_SEAL.json"))
writeLines("changed after adapter",file.path(a$root,"raw_crossings.csv"))
reject(gst_validate_score_truth(s,gsc_verify_forecast_seal(b$root,pin(file.path(b$root,"FORECAST_SEAL.json"))$sha256)),"pinned regular input")
write.csv(gsc_crossings(forecast),file.path(a$root,"raw_crossings.csv"),row.names=FALSE)
ok(is.list(gst_validate_score_truth(s,gsc_verify_forecast_seal(b$root,pin(file.path(b$root,"FORECAST_SEAL.json"))$sha256))))

# Complete synthetic v2 scored packet: independent checker verifies score
# algebra AND retained truth/adapter/seal provenance, not a resealed marker.
score<-gsc_score(forecast,rows)
write.csv(score$summary,file.path(b$root,"family_scores.csv"),row.names=FALSE)
write.csv(score$by_date,file.path(b$root,"scores_by_date.csv"),row.names=FALSE)
write.csv(score$calibration,file.path(b$root,"quantile_calibration.csv"),row.names=FALSE)
file.copy(csv,file.path(b$root,"scoring_truth.csv"));file.copy(df,file.path(b$root,"TRUTH_DERIVATION.json"))
file.copy(purpose_pin$path,file.path(b$root,"TRUTH_PURPOSE.json"))
json(score$score_contract,file.path(b$root,"score_contract.json"))
seal_b<-pin(file.path(b$root,"FORECAST_SEAL.json"))
decision<-list(schema_version="glofas_same_family_closeout_receipt_v1",status="READY_FOR_SCIENTIFIC_REVIEW_NOT_AUTOMATIC_PUBLICATION",
  mode="score",future_truth_read=TRUE,model_selection_or_retuning=FALSE,new_fits=0L,
  article_publication_authorized=FALSE,forecast_seal_sha256=seal_b$sha256,expected_identity=gsc_identity(),
  source_commit=s$source_commit,source_tree=s$source_tree,truth_interface_version=s$truth_interface_version,
  input_bindings=s[c("truth","truth_rds","truth_provenance_manifest","assembly_root","assembly_manifest",
    "assembly_forecast_seal","truth_derivation","truth_adapter_purpose")])
json(decision,file.path(b$root,"DECISION.json"));bm<-manifest(b$root)
ok(is.list(gsc_check_packet(b$root,bm$sha256)))
modified<-rows;modified$y_transformed<-modified$y_transformed+.1
write.csv(modified,file.path(b$root,"scoring_truth.csv"),row.names=FALSE)
bm<-manifest(b$root);reject(gsc_check_packet(b$root,bm$sha256),"retained scoring truth differs")
file.copy(csv,file.path(b$root,"scoring_truth.csv"),overwrite=TRUE)
bad<-derivation;bad$forecast_changes<-TRUE;json(bad,file.path(b$root,"TRUTH_DERIVATION.json"))
bm<-manifest(b$root);reject(gsc_check_packet(b$root,bm$sha256),"retained truth provenance differs")
ok(!file.exists(truth_pin$path))
help<-capture.output(gst_bridge_main("--help"));ok(length(help)==1L&&grepl("--execute",help,fixed=TRUE))
reject(gst_bridge_main(character()),"exact separate truth")
cat("GLOFAS_TRUTH_BRIDGE_SYNTHETIC_CHECKS=",checks," PASS; original_truth_RDS_reads=0 scientific_runs=0 publication=FALSE\n",sep="")
})
