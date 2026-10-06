#!/usr/bin/env Rscript
args <- commandArgs(TRUE)
if (length(args) != 2L) stop("Usage: CAPACITY.R CPU_LIST_OR_auto OUTPUT_CSV")
topology <- read.csv(text = paste(system2("lscpu", "-p=CPU,CORE,SOCKET", stdout = TRUE), collapse = "\n"),
  comment.char = "#", header = FALSE, col.names = c("cpu", "core", "socket"))
topology$key <- paste(topology$socket, topology$core, sep = ":")
stat <- function() {
  lines <- readLines("/proc/stat"); lines <- lines[grepl("^cpu[0-9]+ ", lines)]
  do.call(rbind, lapply(strsplit(trimws(lines), " +"), function(p) {
    n <- as.numeric(p[-1L]); data.frame(cpu = as.integer(sub("cpu", "", p[[1L]])),
      total = sum(n[seq_len(min(8L, length(n)))]), idle = sum(n[c(4L, 5L)]))
  }))
}
before <- stat(); Sys.sleep(3); after <- stat()
topology$busy <- (1 - (after$idle - before$idle) / (after$total - before$total))[match(topology$cpu, after$cpu)]
expand <- function(spec) unlist(lapply(strsplit(spec, ",", fixed = TRUE)[[1L]], function(x) {
  v <- as.integer(strsplit(x, "-", fixed = TRUE)[[1L]])
  if (length(v) == 2L) seq.int(v[[1L]], v[[2L]]) else v
}), use.names = FALSE)
restricted <- character()
for (pid in list.files("/proc", pattern = "^[0-9]+$")) {
  command <- tryCatch(readBin(file.path("/proc", pid, "cmdline"), "raw", n = 1L), error = function(e) raw())
  if (!length(command)) next
  lines <- tryCatch(readLines(file.path("/proc", pid, "status"), warn = FALSE), error = function(e) character())
  line <- lines[grepl("^Cpus_allowed_list:", lines)]
  if (!length(line)) next
  keys <- unique(topology$key[match(expand(trimws(sub("^Cpus_allowed_list:", "", line[[1L]]))), topology$cpu)])
  if (length(keys) < length(unique(topology$key))) restricted <- union(restricted, keys)
}
physical <- do.call(rbind, lapply(split(topology, topology$key), function(x) data.frame(
  cpu = min(x$cpu), physical_core = x$key[1L], measured_busy_fraction = max(x$busy),
  restricted_process_conflict = x$key[1L] %in% restricted)))
physical$pass <- is.finite(physical$measured_busy_fraction) & physical$measured_busy_fraction < .15 & !physical$restricted_process_conflict
if (args[[1L]] == "auto") {
  out <- physical[physical$pass, ]; out <- out[order(out$cpu), ]
  out <- head(out, 15L)
} else {
  cpus <- as.integer(strsplit(args[[1L]], ",", fixed = TRUE)[[1L]])
  stopifnot(length(cpus) > 0L, length(cpus) <= 15L, !anyNA(cpus), !anyDuplicated(cpus))
  keys <- topology$key[match(cpus, topology$cpu)]; stopifnot(!anyNA(keys), !anyDuplicated(keys))
  out <- physical[match(keys, physical$physical_core), ]; out$cpu <- cpus
}
write.csv(out, args[[2L]], row.names = FALSE)
free <- system2("df", c("-Pk", "/data"), stdout = TRUE)
available <- as.numeric(strsplit(trimws(tail(free, 1L)), " +")[[1L]][[4L]]) / 1024^2
print(out, row.names = FALSE); cat("Free disk GiB:", available, "\n")
if (!nrow(out) || !all(out$pass) || !is.finite(available) || available < 50) stop("Capacity gate blocked; nothing launched.")
cat("CPU_LIST=", paste(out$cpu, collapse = ","), "\n", sep = "")
