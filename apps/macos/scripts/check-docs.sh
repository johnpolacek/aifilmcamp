#!/bin/bash
# Consistency gate for the planning documents.
# Catches the cross-document defects that repeatedly survive review: frozen identifiers
# drifting between plans, a plan claiming a path is both untouched and modified, stale
# plan numbers, and broken drift blocks.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
ok()  { printf 'ok   %s\n' "$1"; }

PHASE1=(docs/plans/00[2-8]-*.md)
PHASE2=(docs/plans/009-*.md docs/plans/01[0-2]-*.md)
# NOTE: these bracket ranges fail *open* at an out-of-range number — a docs/plans/019-*.md
# would enter no list, so checks 2/3/5/6 would silently skip it with a green gate. Widen
# the range in the same commit that adds a plan file.
PHASE3=(docs/plans/01[3-6]-*.md)
PHASE4=(docs/plans/017-*.md)
PHASE5=(docs/plans/01[89]-*.md docs/plans/02[0-9]-*.md docs/plans/03[0-6]-*.md)
ALLPLANS=("${PHASE1[@]}" "${PHASE2[@]}" "${PHASE3[@]}" "${PHASE4[@]}" "${PHASE5[@]}")
ALLDOCS=(docs/PHASE1_DESIGN.md docs/PHASE2_DESIGN.md docs/PHASE3_DESIGN.md docs/PHASE4_DESIGN.md docs/PHASE5_DESIGN.md docs/plans/README.md "${ALLPLANS[@]}")

# 1. Frozen identifiers: the wrong spelling must appear nowhere (Plan 001 is history, exempt).
step=0
while IFS='|' read -r wrong right desc; do
  [ -z "${wrong:-}" ] && continue
  hits=$(grep -rl -F -- "$wrong" docs/ 2>/dev/null | grep -v 'docs/plans/001-' || true)
  if [ -n "$hits" ]; then
    bad "frozen identifier: $desc — found '$wrong', expected '$right'"
    printf '       %s\n' $hits
    step=1
  fi
done <<'FROZEN'
FilmScriptVersion.current|FilmScriptVersion.parser|parser version constant
FDXReader.render|FDXRenderer.render|FDX renderer entry point
inferAssetPrompt|generateAssetPrompt|prompt-run task name (Phase 3 §8.1)
AssetPromptBuilder|AssetPromptInputBuilder|prompt input renderer (Phase 3 §8.2)
asset-prompt-v1.json|asset-prompt-v1.schema.json|prompt schema filename (Phase 3 §8.1)
inferNextActions|recommendNextActions|recommendation task name (Phase 4 §8.1)
recommend-next-actions-v1.json|recommend-next-actions-v1.schema.json|recommendation schema filename (Phase 4 §8.1)
inferScenePrompt|generateScenePrompt|scene prompt task name (Phase 5 §8.1)
scene-prompt-v1.json|scene-prompt-v1.schema.json|scene prompt schema filename (Phase 5 §8.1)
ScenePromptBuilder|ScenePromptInputBuilder|scene prompt input renderer (Phase 5 §8.2)
FROZEN
[ $step -eq 0 ] && ok "frozen identifiers consistent"

# 2. Known contradictory phrase pairs inside one plan.
step=0
while IFS='|' read -r a b desc; do
  [ -z "${a:-}" ] && continue
  for f in "${ALLPLANS[@]}"; do
    if grep -qi -F -- "$a" "$f" && grep -qi -F -- "$b" "$f"; then
      bad "$(basename "$f"): $desc ('$a' vs '$b')"; step=1
    fi
  done
done <<'PAIRS'
Delete nothing under|Delete `AnalysisJobView`|claims to delete nothing in the app yet deletes app views
edits no SwiftUI file|reduce `AppModel`|claims to touch no SwiftUI yet reduces AppModel
merges on its own|is not merged alone|claims both to merge alone and not to
PAIRS
[ $step -eq 0 ] && ok "no untouched/modified contradictions"

# 3. Every referenced plan number must exist.
step=0
for f in "${ALLDOCS[@]}"; do
  grep -o 'Plan 0[0-9][0-9]' "$f" 2>/dev/null | sort -u | while read -r _ num; do
    ls docs/plans/"${num}"-*.md >/dev/null 2>&1 || echo "FAIL $(basename "$f"): references Plan $num, which does not exist"
  done
done > /tmp/_planrefs.$$ 2>/dev/null
if [ -s /tmp/_planrefs.$$ ]; then cat /tmp/_planrefs.$$; fail=1; else ok "plan references resolve"; fi
rm -f /tmp/_planrefs.$$

# 4. Drift blocks verify.
step=0
for f in "${ALLPLANS[@]}"; do
  out=$(sed -n '/^> printf/,/shasum -a 256 -c -/p' "$f" | sed 's/^> //' | bash 2>&1)
  if echo "$out" | grep -q FAILED; then
    bad "$(basename "$f"): drift check fails"; echo "$out" | grep FAILED | sed 's/^/       /'; step=1
  fi
done
[ $step -eq 0 ] && ok "drift blocks verify"

# 5. Required sections.
step=0
for f in "${ALLPLANS[@]}"; do
  for s in "## Status" "## Contracts" "## Steps" "## Done criteria" "## STOP conditions"; do
    grep -q "^$s" "$f" || { bad "$(basename "$f"): missing '$s'"; step=1; }
  done
done
[ $step -eq 0 ] && ok "plan structure intact"

if [ $fail -eq 0 ]; then echo "check-docs: all checks passed"; else echo "check-docs: FAILED"; fi
exit $fail
