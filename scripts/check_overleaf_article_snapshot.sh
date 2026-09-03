#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 SNAPSHOT_DIRECTORY SOURCE_REF" >&2
  echo "Verify inventory, provenance, dependencies, and manuscript builds." >&2
}

die() {
  echo "OVERLEAF_SNAPSHOT_CHECK_ERROR: $*" >&2
  exit 1
}

if [[ $# -ne 2 ]]; then
  usage
  exit 2
fi

snapshot_dir=$1
source_ref=$2

[[ -d "$snapshot_dir" ]] || die "snapshot directory is absent: $snapshot_dir"
snapshot_dir=$(cd "$snapshot_dir" && pwd)
source_commit=$(git rev-parse --verify "${source_ref}^{commit}" 2>/dev/null) ||
  die "source ref is not a commit: $source_ref"

source_tree=$(git rev-parse "${source_commit}^{tree}")

mapfile -t article_files < <(
  git show "${source_commit}:overleaf/article_files.txt" |
    sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d'
)

[[ ${#article_files[@]} -gt 0 ]] || die "article manifest is empty"

expected_inventory=$(mktemp)
actual_inventory=$(mktemp)
compile_dir=$(mktemp -d)
cleanup() {
  rm -f "$expected_inventory" "$actual_inventory"
  rm -rf "$compile_dir"
}
trap cleanup EXIT

{
  printf '%s\n' "${article_files[@]}"
  printf '%s\n' .gitignore README.md SOURCE_AUTHORITY.txt
} | LC_ALL=C sort > "$expected_inventory"

(
  cd "$snapshot_dir"
  find . -type f -printf '%P\n' | LC_ALL=C sort
) > "$actual_inventory"

cmp -s "$expected_inventory" "$actual_inventory" || {
  diff -u "$expected_inventory" "$actual_inventory" >&2 || true
  die "snapshot inventory differs from the manifest closure"
}

for forbidden in application docs scripts local_trackers overleaf; do
  [[ ! -e "$snapshot_dir/$forbidden" ]] || die "forbidden path entered snapshot: $forbidden"
done

if find "$snapshot_dir" -type f \( \
     -name '*.rds' -o -name '*.rda' -o -name '*.RData' -o \
     -name '*.log' -o -name '*.aux' -o -name '*.blg' -o \
     -name '*.fdb_latexmk' -o -name '*.fls' -o -name '*.synctex.gz' \
   \) -print -quit | grep -q .; then
  die "generated or runtime files entered the snapshot"
fi

for path in "${article_files[@]}"; do
  git show "${source_commit}:${path}" | cmp -s - "$snapshot_dir/$path" ||
    die "snapshot blob differs from source: $path"
done
git show "${source_commit}:overleaf/overleaf.gitignore" |
  cmp -s - "$snapshot_dir/.gitignore" || die "snapshot .gitignore differs from source"
git show "${source_commit}:overleaf/README.md" |
  cmp -s - "$snapshot_dir/README.md" || die "snapshot README differs from source"

marker_value() {
  local key=$1
  local marker=$snapshot_dir/SOURCE_AUTHORITY.txt
  local value
  value=$(sed -n "s/^${key}=//p" "$marker")
  [[ -n "$value" ]] || die "SOURCE_AUTHORITY.txt lacks $key"
  [[ "$(grep -c "^${key}=" "$marker")" -eq 1 ]] ||
    die "SOURCE_AUTHORITY.txt repeats $key"
  printf '%s' "$value"
}

[[ "$(marker_value schema)" == "1" ]] || die "unsupported source-authority schema"
[[ "$(marker_value authority_policy)" == "command-line-git-only" ]] ||
  die "source-authority policy is incorrect"
[[ "$(marker_value source_remote)" == "origin" ]] || die "source remote is incorrect"
[[ "$(marker_value source_branch)" == "main" ]] || die "source branch is incorrect"
[[ "$(marker_value source_commit)" == "$source_commit" ]] || die "source commit is incorrect"
[[ "$(marker_value source_tree)" == "$source_tree" ]] || die "source tree is incorrect"
[[ "$(marker_value manifest_blob)" == "$(git rev-parse "${source_commit}:overleaf/article_files.txt")" ]] ||
  die "manifest blob is incorrect"
[[ "$(marker_value manifest_sha256)" == "$(git show "${source_commit}:overleaf/article_files.txt" | sha256sum | awk '{print $1}')" ]] ||
  die "manifest SHA-256 is incorrect"
[[ "$(marker_value main_tex_sha256)" == "$(sha256sum "$snapshot_dir/main.tex" | awk '{print $1}')" ]] ||
  die "main.tex SHA-256 is incorrect"
[[ "$(marker_value supplement_tex_sha256)" == "$(sha256sum "$snapshot_dir/qdesn-supplement.tex" | awk '{print $1}')" ]] ||
  die "supplement SHA-256 is incorrect"
[[ "$(marker_value refs_bib_sha256)" == "$(sha256sum "$snapshot_dir/refs.bib" | awk '{print $1}')" ]] ||
  die "bibliography SHA-256 is incorrect"

cp -a "$snapshot_dir/." "$compile_dir/"

build_document() {
  local stem=$1
  local tex_file=${stem}.tex
  (
    cd "$compile_dir"
    unset TEXINPUTS BIBINPUTS BSTINPUTS TEXMFHOME TEXMFCONFIG TEXMFVAR
    export openin_any=p
    export openout_any=p
    pdflatex -recorder -interaction=nonstopmode -halt-on-error "$tex_file" >/dev/null
    bibtex "$stem" >/dev/null
    pdflatex -recorder -interaction=nonstopmode -halt-on-error "$tex_file" >/dev/null
    pdflatex -recorder -interaction=nonstopmode -halt-on-error "$tex_file" >/dev/null
    pdflatex -recorder -interaction=nonstopmode -halt-on-error "$tex_file" >/dev/null
  ) || die "manuscript build failed: $tex_file"
}

build_document main
build_document qdesn-supplement

warning_pattern='(^!|LaTeX Warning|Package .* Warning|undefined references|undefined citations|multiply defined|Overfull|Underfull)'
if grep -En "$warning_pattern" "$compile_dir/main.log" "$compile_dir/qdesn-supplement.log"; then
  die "final manuscript logs contain warnings or errors"
fi

bib_warning_pattern='(^Warning--|I couldn.t open|I found no|error message|---line)'
if grep -Ein "$bib_warning_pattern" "$compile_dir/main.blg" "$compile_dir/qdesn-supplement.blg"; then
  die "bibliography logs contain warnings or errors"
fi

mapfile -t tex_system_roots < <(
  for variable in TEXMFDIST TEXMFLOCAL TEXMFSYSCONFIG TEXMFSYSVAR; do
    kpsewhich -var-value="$variable" 2>/dev/null || true
  done | awk 'NF' | while IFS= read -r root; do realpath -m "$root"; done
)

is_tex_system_path() {
  local candidate=$1
  local root
  for root in "${tex_system_roots[@]}"; do
    case "$candidate" in
      "$root"|"$root"/*) return 0 ;;
    esac
  done
  return 1
}

declare -A expected_sources=()
while IFS= read -r path; do
  expected_sources[$path]=1
done < "$expected_inventory"

for fls in "$compile_dir/main.fls" "$compile_dir/qdesn-supplement.fls"; do
  [[ -f "$fls" ]] || die "recorder output is absent: $fls"
  while IFS= read -r input_path; do
    [[ -n "$input_path" ]] || continue
    if [[ "$input_path" != /* ]]; then
      absolute_path=$(realpath -m "$compile_dir/$input_path")
    else
      absolute_path=$(realpath -m "$input_path")
    fi
    case "$absolute_path" in
      "$compile_dir"/*)
        relative_path=${absolute_path#"$compile_dir"/}
        case "$relative_path" in
          *.aux|*.bbl|*.blg|*.out|*.toc|*.lof|*.lot|*.fls|*.log) ;;
          *)
            [[ -n "${expected_sources[$relative_path]+x}" ]] ||
              die "recorder found an undeclared project input: $relative_path"
            ;;
        esac
        ;;
      *)
        case "$absolute_path" in
          *.tex|*.bib|*.bst|*.pdf|*.png|*.jpg|*.jpeg|*.eps|*.svg|\
          *.csv|*.dat|*.txt|*.json|*.yaml|*.yml|\
          *.sty|*.cls|*.cfg|*.def|*.fd|*.clo|*.ldf|*.bbx|*.cbx|*.lbx)
            is_tex_system_path "$absolute_path" ||
              die "recorder found an external project source: $absolute_path"
            ;;
        esac
        ;;
    esac
  done < <(sed -n 's/^INPUT //p' "$fls")
done

main_pages=$(pdfinfo "$compile_dir/main.pdf" | awk '/^Pages:/ {print $2}')
supplement_pages=$(pdfinfo "$compile_dir/qdesn-supplement.pdf" | awk '/^Pages:/ {print $2}')

printf 'source_commit=%s\n' "$source_commit"
printf 'snapshot_files=%d\n' "$(wc -l < "$actual_inventory")"
printf 'main_pages=%s\n' "$main_pages"
printf 'supplement_pages=%s\n' "$supplement_pages"
echo "OVERLEAF_ARTICLE_SNAPSHOT_CHECK=PASS"
