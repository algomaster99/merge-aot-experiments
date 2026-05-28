#!/usr/bin/env bash
#
# setup-forks.sh — bootstrap the dependency forks for the FOP and BioJava
# distributed-AOT experiments.
#
# WHY THIS IS A SCRIPT (and not done by the agent): creating forks requires
# write access to repos outside this one, which the agent environment does not
# have. Run this locally, where your own `gh` CLI + git are authenticated.
#
# WHAT IT AUTOMATES (safe, idempotent):
#   • forks each upstream repo to your account
#   • creates the per-experiment `aotcache-setup-*` branch at the correct tag
#   • scans each fork for module-info (source + MR-JAR) and reports it
#   • extracts the proven `tree-merge` Maven profile from an existing fork and
#     injects it into the target module POMs in the LOCAL clone
#   • commits those edits locally (does NOT push them — see checkpoints)
#   • prints the exact `git submodule add` lines for both experiments
#
# WHAT YOU STILL DO BY HAND (flagged as ⚑ CHECKPOINT):
#   • review + push the profile/module-info edits on each fork branch
#   • strip module-info where the scan reports it (varies per repo)
#   • confirm version retargeting for reused forks (e.g. batik 1.18 vs 1.19)
#
set -euo pipefail

# ── config ───────────────────────────────────────────────────────────────────
GH_USER="${GH_USER:-algomaster99}"
# An existing fork whose `tree-merge` profile is the reference to copy.
REF_FORK="${REF_FORK:-$GH_USER/commons-io}"
REF_BRANCH="${REF_BRANCH:-aotcache-setup}"
STAGING="${STAGING:-$PWD/.fork-staging}"

c_ok()   { printf '\033[1;32m%s\033[0m\n' "$*"; }
c_info() { printf '\033[1;36m%s\033[0m\n' "$*"; }
c_warn() { printf '\033[1;33m%s\033[0m\n' "$*"; }
c_chk()  { printf '\033[1;35m⚑ CHECKPOINT: %s\033[0m\n' "$*"; }
fail()   { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

command -v gh  >/dev/null || fail "gh CLI not found"
command -v git >/dev/null || fail "git not found"
gh auth status >/dev/null 2>&1 || fail "gh is not authenticated — run: gh auth login"
mkdir -p "$STAGING"

# ── reference tree-merge profile ───────────────────────────────────────────────
PROFILE_SNIPPET="$STAGING/tree-merge-profile.xml"
extract_reference_profile() {
  c_info "Extracting reference tree-merge profile from $REF_FORK@$REF_BRANCH"
  local dir="$STAGING/_ref"
  rm -rf "$dir"
  if ! git clone --depth 1 -b "$REF_BRANCH" "https://github.com/$REF_FORK" "$dir" >/dev/null 2>&1; then
    c_warn "Could not clone $REF_FORK@$REF_BRANCH — skipping profile extraction."
    c_warn "You will need to add the tree-merge profile to the new forks by hand."
    return 1
  fi
  # Pull the <profile>…<id>tree-merge</id>…</profile> block out of the POM.
  python3 - "$dir/pom.xml" "$PROFILE_SNIPPET" <<'PY' || { c_warn "profile block not found in $REF_FORK pom"; return 1; }
import re, sys
pom, out = sys.argv[1], sys.argv[2]
xml = open(pom).read()
blocks = re.findall(r'<profile>.*?</profile>', xml, re.S)
for b in blocks:
    if 'tree-merge' in b:
        open(out, 'w').write(b.strip() + "\n")
        sys.exit(0)
sys.exit(1)
PY
  c_ok "  profile saved → $PROFILE_SNIPPET"
}

# ── helpers ────────────────────────────────────────────────────────────────────
ensure_fork() {  # <upstream_owner/repo>
  local up="$1" name="${1##*/}"
  if gh repo view "$GH_USER/$name" >/dev/null 2>&1; then
    c_ok "  fork exists: $GH_USER/$name"
  else
    c_info "  forking $up → $GH_USER/$name"
    gh repo fork "$up" --clone=false --org "" >/dev/null 2>&1 \
      || gh repo fork "$up" --clone=false >/dev/null
    c_ok "  forked: $GH_USER/$name"
  fi
}

# clone fork, create branch at tag, scan module-info, inject profile, commit (no push)
prepare_fork() {  # <name> <branch> <tag> <modules...>
  local name="$1" branch="$2" tag="$3"; shift 3
  local modules=("$@")
  local dir="$STAGING/$name"
  c_info "Preparing $GH_USER/$name (branch=$branch tag=$tag)"
  rm -rf "$dir"
  git clone "https://github.com/$GH_USER/$name" "$dir" >/dev/null 2>&1 \
    || { c_warn "  clone failed for $GH_USER/$name — fork may still be replicating; rerun later."; return 0; }
  ( cd "$dir"
    if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
      git checkout -q -b "$branch" "$tag"
    else
      c_warn "  tag '$tag' not on this mirror."
      c_chk "Fork $name from a repo that carries '$tag' (e.g. Apache gitbox), then re-run."
      git checkout -q -b "$branch"
    fi

    # module-info scan (informational)
    local mi_src mi_jar
    mi_src=$(git ls-files | grep -c 'module-info.java' || true)
    mi_jar=$(grep -rl 'Multi-Release: true' --include=MANIFEST.MF . 2>/dev/null | wc -l | tr -d ' ')
    echo "    module-info.java in source: $mi_src"
    [ "$mi_src" -gt 0 ] && c_chk "Strip the $mi_src module-info.java file(s) in $name before recording."

    # inject the reference tree-merge profile into each target module POM
    if [ -f "$PROFILE_SNIPPET" ]; then
      local m
      for m in "${modules[@]}"; do
        local pom="$m/pom.xml"
        [ -f "$pom" ] || { c_warn "    no $pom — skipping"; continue; }
        if grep -q '<id>tree-merge</id>' "$pom"; then
          echo "    $m: tree-merge profile already present"
          continue
        fi
        python3 - "$pom" "$PROFILE_SNIPPET" <<'PY'
import sys
pom, snip = sys.argv[1], sys.argv[2]
xml = open(pom).read()
block = open(snip).read().rstrip() + "\n"
if '<profiles>' in xml:
    xml = xml.replace('<profiles>', '<profiles>\n' + block, 1)
else:
    xml = xml.replace('</project>', '  <profiles>\n' + block + '  </profiles>\n</project>', 1)
open(pom, 'w').write(xml)
PY
        echo "    $m: injected tree-merge profile"
      done
    else
      c_warn "    no reference profile available — add tree-merge profiles manually."
    fi

    git add -A
    git commit -q -m "Add tree-merge AOT profile (aotcache-setup)" 2>/dev/null \
      && c_ok "  committed profile edits locally (NOT pushed)" \
      || echo "    nothing to commit"
  )
  c_chk "Review $dir, finish module-info stripping, then: (cd $dir && git push -u origin $branch)"
}

# ── run ────────────────────────────────────────────────────────────────────────
extract_reference_profile || true

c_info "== New forks (need tree-merge profile + module-info work) =="
ensure_fork apache/xmlgraphics-fop
ensure_fork biojava/biojava
# FOP 2.10 is NOT tagged on the GitHub mirror (only ≤ fop-2_8). Use the Apache
# gitbox repo if the tag is missing; the script will tell you.
prepare_fork xmlgraphics-fop aotcache-setup-fop      fop-2_10       fop-core fop-events fop-util
prepare_fork biojava         aotcache-setup-biojava  biojava-7.2.5  biojava-core biojava-alignment

c_info "== Reused forks (already set up for other experiments) =="
echo "  These exist on $GH_USER; FOP/BioJava reuse them. Two need attention:"
c_chk "batik fork is at 1.19 — FOP needs 1.18. Branch the fork at the 1.18 tag and re-apply the profile."
c_chk "xmlgraphics-commons fork must be at 2.10 to match fop-core 2.10."
echo "  No action needed for: commons-io, commons-logging, fontbox(pdfbox), commons-codec, slf4j."
echo "  forester is recorded via a custom workload module (no fork) — see orchestrate-combine.sh."

c_info "== Submodule wiring (run from the repo root after the branches are pushed) =="
cat <<EOF
# FOP experiment
git submodule add -b aotcache-setup-fop     git@github.com:$GH_USER/xmlgraphics-fop.git       fop-experiment/fop
git submodule add -b aotcache-setup-fop     git@github.com:$GH_USER/xmlgraphics-batik.git     fop-experiment/fop-deps/batik
git submodule add -b aotcache-setup-fop     git@github.com:$GH_USER/xmlgraphics-commons.git   fop-experiment/fop-deps/xmlgraphics-commons
git submodule add -b aotcache-setup         git@github.com:$GH_USER/commons-io.git            fop-experiment/fop-deps/commons-io
git submodule add -b aotcache-setup         git@github.com:$GH_USER/pdfbox.git                fop-experiment/fop-deps/fontbox
# (commons-logging-workload and fop-deps/forester are local workload modules, not submodules)

# BioJava experiment
git submodule add -b aotcache-setup-biojava git@github.com:$GH_USER/biojava.git               biojava-experiment/biojava
git submodule add -b aotcache-setup         git@github.com:$GH_USER/commons-codec.git         biojava-experiment/biojava-deps/commons-codec
git submodule add -b aotcache-setup         git@github.com:$GH_USER/slf4j.git                 biojava-experiment/biojava-deps/slf4j
EOF

c_ok "Done. Staging dir: $STAGING"
