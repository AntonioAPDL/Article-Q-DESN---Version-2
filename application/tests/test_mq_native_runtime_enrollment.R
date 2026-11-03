#!/usr/bin/env Rscript
source("scripts/enroll_mq_native_runtime.R",local=TRUE)
checks<-0L
ok<-function(x){stopifnot(isTRUE(x));checks<<-checks+1L}
reject<-function(x)ok(inherits(tryCatch({force(x);NULL},error=identity),"error"))
names<-c("schema_version","purpose","actor_nonce","expires_utc","source_commit","source_tree",
  "origin_remote_url","published_ref","source_files","source_manifest","retained_build_receipt",
  "retained_build_terminal","output_root","limits","allow_runtime_inventory","allow_qualification",
  "allow_refit","allow_scoring","allow_prepared_read","allow_future_truth","allow_production","allow_article")
s<-setNames(vector("list",length(names)),names)
s$schema_version<-"mq_native_runtime_enrollment_purpose_v1";s$purpose<-"RETAINED_DLL_AND_RUNTIME_INVENTORY_ONLY"
s$actor_nonce<-strrep("a",32);s$expires_utc<-"2100-01-01T00:00:00Z"
s$source_commit<-strrep("b",40);s$source_tree<-strrep("c",40)
s$origin_remote_url<-"git@github.com:AntonioAPDL/Article-Q-DESN---Version-2.git"
s$published_ref<-"refs/heads/work/generated-runtime-scope"
s$allow_runtime_inventory<-TRUE
for(k in c("allow_qualification","allow_refit","allow_scoring","allow_prepared_read","allow_future_truth","allow_production","allow_article"))s[[k]]<-FALSE
s$limits<-list(cpu_seconds=120,wall_term_seconds=119,wall_kill_after_seconds=1,
  address_space_bytes=2*1024^3,output_bytes=64*1024^2,logical_cpu=27)
ok(mqnr_scope(s))
for(k in c("allow_qualification","allow_refit","allow_scoring","allow_prepared_read","allow_future_truth","allow_production","allow_article")) {
  bad<-s;bad[[k]]<-TRUE;reject(mqnr_scope(bad))
}
for(k in c("cpu_seconds","wall_term_seconds","address_space_bytes","output_bytes","logical_cpu")) {
  bad<-s;bad$limits[[k]]<-bad$limits[[k]]+1;reject(mqnr_scope(bad))
}
bad<-s;bad$input_model<-"forbidden";reject(mqnr_scope(bad))
bad<-s;bad$allow_runtime_inventory<-FALSE;reject(mqnr_scope(bad))
bad<-s;bad$actor_nonce<-"spent";reject(mqnr_scope(bad))
for(ref in c("--upload-pack=wrong","refs/heads/work/../bad","refs/heads/work//bad")) {
  bad<-s;bad$published_ref<-ref;reject(mqnr_scope(bad))
}
bad<-s;bad$origin_remote_url<-"https://wrong.example/repo";reject(mqnr_scope(bad))
reject(mqnr_main(character()));reject(mqnr_main(c("--execute")))
ok(is.null(mqnr_main("--help")))
cat(sprintf("MQ_NATIVE_RUNTIME_ENROLLMENT_GUARDS_PASS checks=%d scientific_reads=0 DLL_loads=0\n",checks))
