# Lossless storage blocks for the original draw/origin forecast members.
# Blocking changes storage only: no thinning, averaging or new draw coupling.
app_iqf_member_key <- function(shard) paste0("draw:", shard$draw_id, "|origin:", shard$origin_id)
app_iqf_same_geometry <- function(left, right) {
  identical(left$quantiles[c("horizon", "probability")], right$quantiles[c("horizon", "probability")])
}

app_iqf_receipt_pack <- function(receipts) {
  first <- receipts[[1L]]
  if (is.null(first)) {
    app_iqf_require(all(vapply(receipts, is.null, logical(1L))), "Mixed absent/present numerical receipts.")
    return(NULL)
  }
  app_iqf_require(is.data.frame(first) && all(c("horizon", "probability") %in% names(first)),
    "Blocked numerical receipts require explicit geometry.")
  varying <- setdiff(names(first)[vapply(first, is.numeric, logical(1L))], c("horizon", "probability"))
  fixed <- setdiff(names(first), varying)
  app_iqf_require(all(vapply(receipts, function(x) is.data.frame(x) &&
    identical(names(x), names(first)) && identical(x[fixed], first[fixed]) &&
    identical(vapply(x, typeof, ""), vapply(first, typeof, "")), logical(1L))),
    "Numerical receipt geometry/schema changed inside a storage block.")
  list(template = first, values = setNames(lapply(varying, function(name)
    do.call(cbind, lapply(receipts, `[[`, name))), varying))
}

app_iqf_receipt_unpack <- function(packed, index, n_members) {
  if (is.null(packed)) return(NULL)
  out <- packed$template
  app_iqf_require(is.data.frame(out) && is.list(packed$values), "Malformed blocked numerical receipt.")
  for (name in names(packed$values)) {
    value <- packed$values[[name]]
    app_iqf_require(name %in% names(out) && is.matrix(value) &&
      identical(dim(value), c(nrow(out), as.integer(n_members))), "Blocked numerical receipt dimensions differ.")
    out[[name]] <- value[, index]
  }
  out
}

app_iqf_pack_block <- function(shards) {
  app_iqf_require(is.list(shards) && length(shards) > 0L && length(shards) <= 1000L,
    "A storage block must contain 1–1000 complete original draw/origin members.")
  first <- shards[[1L]]
  app_iqf_require(identical(first$schema_version, "integrated_quantile_forecast_shard_v1") &&
    is.data.frame(first$quantiles), "Only complete forecast members may be packed.")
  dynamic <- intersect(c("draw_id", "origin_id", "original_draw", "integration_status",
    "cdf_components", "paths"), names(first))
  static <- function(x) {
    x[c(dynamic, "quantiles", "integration_diagnostic", "integration_dkw")] <- NULL
    x
  }
  qfixed <- setdiff(names(first$quantiles), c("draw_id", "origin_id", "quantile"))
  app_iqf_require(all(c("draw_id", "origin_id", "quantile") %in% names(first$quantiles)) &&
    all(vapply(shards, function(x) identical(names(x), names(first)) &&
      identical(static(x), static(first)) && is.data.frame(x$quantiles) &&
      identical(names(x$quantiles), names(first$quantiles)) &&
      identical(x$quantiles[qfixed], first$quantiles[qfixed]) &&
      all(x$quantiles$draw_id == x$draw_id) && all(x$quantiles$origin_id == x$origin_id), logical(1L))),
    "Storage blocks cannot mix geometry, models, targets, integration contracts or task identities.")
  keys <- unname(vapply(shards, app_iqf_member_key, ""))
  app_iqf_require(!anyDuplicated(keys), "Duplicate original draw/origin member in storage block.")
  list(schema_version = "integrated_quantile_forecast_block_v1", n_members = length(shards),
    member_keys = keys, template = first, dynamic_fields = dynamic,
    metadata = lapply(shards, function(x) x[dynamic]),
    quantile_values = do.call(cbind, lapply(shards, function(x) x$quantiles$quantile)),
    diagnostic = app_iqf_receipt_pack(lapply(shards, `[[`, "integration_diagnostic")),
    dkw = app_iqf_receipt_pack(lapply(shards, `[[`, "integration_dkw")),
    storage_interpretation = "lossless_complete_original_members_no_thinning_or_averaging")
}

app_iqf_unpack_member <- function(block, index) {
  n <- block$n_members
  app_iqf_require(identical(block$schema_version, "integrated_quantile_forecast_block_v1") &&
    length(n) == 1L && is.finite(n) && n >= 1L && n <= 1000L && n == as.integer(n) &&
    length(index) == 1L && is.finite(index) && index == as.integer(index) && index >= 1L && index <= n &&
    length(block$metadata) == n && length(block$member_keys) == n && !anyDuplicated(block$member_keys),
    "Malformed block or original-member index.")
  out <- block$template
  app_iqf_require(identical(out$schema_version, "integrated_quantile_forecast_shard_v1") &&
    is.matrix(block$quantile_values) && identical(dim(block$quantile_values),
      c(nrow(out$quantiles), as.integer(n))), "Blocked quantile dimensions differ.")
  meta <- block$metadata[[index]]
  app_iqf_require(identical(names(meta), block$dynamic_fields), "Original-member metadata schema changed.")
  for (name in names(meta)) out[name] <- meta[name]
  out$quantiles$draw_id <- rep(out$draw_id, nrow(out$quantiles))
  out$quantiles$origin_id <- rep(out$origin_id, nrow(out$quantiles))
  out$quantiles$quantile <- block$quantile_values[, index]
  out["integration_diagnostic"] <- list(app_iqf_receipt_unpack(block$diagnostic, index, n))
  out["integration_dkw"] <- list(app_iqf_receipt_unpack(block$dkw, index, n))
  app_iqf_require(identical(app_iqf_member_key(out), block$member_keys[index]),
    "Original draw/origin identity differs from its block index.")
  out
}

app_iqf_forecast_members <- function(object, fun) {
  if (identical(object$schema_version, "integrated_quantile_forecast_shard_v1")) return(list(fun(object)))
  app_iqf_require(identical(object$schema_version, "integrated_quantile_forecast_block_v1"),
    "Unsupported accepted forecast storage format.")
  lapply(seq_len(object$n_members), function(index) fun(app_iqf_unpack_member(object, index)))
}

app_iqf_write_output_index <- function(table, path, byte_budget, already_written) {
  lines <- character(); connection <- textConnection("lines", "w", local=TRUE)
  tryCatch(utils::write.csv(table, connection, row.names=FALSE), finally=close(connection))
  bytes <- charToRaw(paste0(paste(lines,collapse="\n"),"\n"))
  app_iqf_require(!file.exists(path) && length(bytes)+already_written <= byte_budget,
    "Output index would overwrite a file or exceed the cumulative artifact budget.")
  writeBin(bytes,path)
  invisible(length(bytes))
}

app_iqf_block_envelope <- function(request, claim, table, output_root) {
  app_iqf_require(!anyDuplicated(table$artifact_key) &&
    setequal(table$artifact_key, unlist(request$expected_output_keys, use.names = FALSE)),
    "Blocked output has missing/duplicate/unexpected original-member keys.")
  files <- unique(as.character(table$relative_path))
  artifacts <- lapply(files, function(relative) {
    rows <- table[table$relative_path == relative, , drop = FALSE]
    app_iqf_require(length(unique(rows$sha256)) == 1L && length(unique(rows$size_bytes)) == 1L,
      "One storage block cannot carry contradictory artifact hashes or sizes.")
    path <- app_iqf_safe_path(output_root, relative)
    app_iqf_require(file.info(path)$size == rows$size_bytes[1L] &&
      identical(app_iqf_hash(path, TRUE), rows$sha256[1L]), "Storage block changed before sealing.")
    object <- readRDS(path)
    app_iqf_require(identical(object$schema_version, "integrated_quantile_forecast_block_v1") &&
      all(c("member_index", "integration_status") %in% names(rows)) &&
      setequal(rows$member_index, seq_len(object$n_members)) && !anyDuplicated(rows$member_index) &&
      identical(unname(object$member_keys[rows$member_index]), as.character(rows$artifact_key)) &&
      identical(vapply(object$metadata[rows$member_index], `[[`, "", "integration_status"),
        as.character(rows$integration_status)), "Block index omits, repeats or relabels an original member.")
    list(relative_path = relative, sha256 = rows$sha256[1L], bytes = rows$size_bytes[1L])
  })
  shards <- lapply(seq_len(nrow(table)), function(i) list(key = table$artifact_key[i],
    relative_path = table$relative_path[i], sha256 = table$sha256[i], bytes = table$size_bytes[i],
    posterior_target_sha256 = request$posterior_target_sha256))
  manifest <- app_iqf_safe_path(output_root, "output_manifest.csv")
  artifacts <- c(artifacts, list(list(relative_path = "output_manifest.csv",
    sha256 = app_iqf_hash(manifest, TRUE), bytes = file.info(manifest)$size)))
  app_iqf_require(setequal(vapply(artifacts, `[[`, "", "relative_path"),
    list.files(output_root, all.files = TRUE, recursive = TRUE, no.. = TRUE)),
    "Uninventoried artifact in the blocked output directory.")
  fields <- c("task_id", "source_commit", "source_tree", "source_manifest_sha256",
    "posterior_target_sha256", "input_manifest_sha256", "task_manifest_sha256", "rng_namespace")
  app_iqf_require(isTRUE(claim$verified) && identical(claim$task_id, request$task_id) &&
    identical(claim$routing_id, request$routing_id) && all(fields %in% names(request)),
    "Blocked completion claim/request identity mismatch.")
  c(list(schema_version = "forecast_transition_output_v1", claim_nonce = claim$claim_nonce,
    routing_id = request$routing_id), request[fields],
    list(expected_output_keys_sha256 = request$expected_output_keys_sha256,
      numerical_gates_pass = all(table$integration_status == "PASS_PREDECLARED_DKW_QUANTILE_ACCURACY_GATE"),
      shards = shards, artifacts = artifacts))
}
