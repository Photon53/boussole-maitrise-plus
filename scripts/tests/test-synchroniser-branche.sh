#!/usr/bin/env bash
# Issue #252 — Banc de scripts/synchroniser-branche.sh et resume-commande.sh, dépôts Git temporaires (Claude)
# Usage : bash scripts/tests/test-synchroniser-branche.sh
set -Euo pipefail
ICI="$(cd "$(dirname "$0")" && pwd)"
SYNCHRO="$ICI/../synchroniser-branche.sh"
RESUME="$ICI/../resume-commande.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
reussis=0; echecs=0
export GIT_AUTHOR_NAME=banc GIT_AUTHOR_EMAIL=banc@exemple.invalid GIT_COMMITTER_NAME=banc GIT_COMMITTER_EMAIL=banc@exemple.invalid
export SYNCHRO_SANS_FETCH=1 SYNCHRO_PY=python3

verif() {   # verif <libellé> <condition shell>
  if eval "$2"; then reussis=$((reussis + 1)); else echecs=$((echecs + 1)); echo "ÉCHEC : $1" >&2; fi
}

# Dépôt minimal : un « générateur » d'inventaire qui liste contenu/*.yaml, comme app.contenu.
nouveau_depot() {
  D="$T/$1"; mkdir -p "$D/api/app" "$D/contenu" "$D/docs/audit"; cd "$D"
  git init -q -b develop
  : > api/app/__init__.py
  cat > api/app/contenu.py <<'PY'
import sys
from pathlib import Path
noms = sorted(p.name for p in Path("../contenu").glob("*.yaml"))
cible = {"inventaire": "../docs/CONTENU-INVENTAIRE.md", "corrections": "../docs/audit/CORRIGES-INVENTAIRE.md"}[sys.argv[1]]
Path(cible).write_text("".join(f"- {n}\n" for n in noms), encoding="utf-8")
PY
  echo a > contenu/a.yaml; echo "- a.yaml" > docs/CONTENU-INVENTAIRE.md; echo "- a.yaml" > docs/audit/CORRIGES-INVENTAIRE.md
  printf 'l1\nl2\nl3\n' > partage.txt
  git add -A && git commit -qm initial
  git update-ref refs/remotes/origin/develop HEAD
}
avancer_develop() {   # avancer_develop <commande> : commit sur develop puis origin/develop
  git checkout -q develop && eval "$1" && git add -A && git commit -qm develop -q
  git update-ref refs/remotes/origin/develop HEAD && git checkout -q travail
}

# 1. Refus sur develop et sur arbre modifié.
nouveau_depot refus
code=0; bash "$SYNCHRO" >/dev/null 2>&1 || code=$?; verif "refus sur develop" '[ "$code" -ne 0 ]'
git checkout -q -b travail; echo x >> partage.txt
code=0; bash "$SYNCHRO" >/dev/null 2>&1 || code=$?; verif "refus si arbre modifié" '[ "$code" -ne 0 ]'

# 2. Déjà à jour.
nouveau_depot ajour; git checkout -q -b travail
sortie="$(bash "$SYNCHRO" 2>&1)"; verif "déjà à jour" 'grep -q "À jour" <<<"$sortie"'

# 3. Conflit sur l'inventaire seul : régénéré, fusion commitée, contenu des deux côtés.
nouveau_depot inventaire; git checkout -q -b travail
echo b > contenu/b.yaml; printf -- '- a.yaml\n- b.yaml\n' > docs/CONTENU-INVENTAIRE.md; git add -A; git commit -qm travail
avancer_develop 'echo c > contenu/c.yaml; printf -- "- a.yaml\n- c.yaml\n" > docs/CONTENU-INVENTAIRE.md'
code=0; bash "$SYNCHRO" >/dev/null 2>&1 || code=$?
verif "inventaire : code 0" '[ "$code" -eq 0 ]'
verif "inventaire : fusion terminée" '[ ! -f .git/MERGE_HEAD ]'
verif "inventaire régénéré" '[ "$(cat docs/CONTENU-INVENTAIRE.md)" = "$(printf -- "- a.yaml\n- b.yaml\n- c.yaml")" ]'
verif "aucun marqueur" '! grep -rq "^<<<<<<<" docs'

# 4. Fusion sans conflit mais inventaire des corrigés périmé : commit de régénération séparé.
nouveau_depot perime; git checkout -q -b travail
echo b > contenu/b.yaml; git add -A; git commit -qm travail
avancer_develop 'echo c > contenu/c.yaml'
AGENT=Banc bash "$SYNCHRO" >/dev/null 2>&1
verif "corrigés régénérés" 'grep -q c.yaml docs/audit/CORRIGES-INVENTAIRE.md && grep -q b.yaml docs/audit/CORRIGES-INVENTAIRE.md'
verif "commit attribué" 'git log -1 --format=%B | grep -q "Agent: Banc"'
verif "sans issue : pas de référence" '! git log -1 --format=%B | grep -q "Refs:"'

# 4 bis. Numéro d'issue : variable ISSUE, ou déduit du nom de branche.
nouveau_depot issue_var; git checkout -q -b travail
echo b > contenu/b.yaml; git add -A; git commit -qm travail
avancer_develop 'echo c > contenu/c.yaml'
ISSUE=252 bash "$SYNCHRO" >/dev/null 2>&1
verif "ISSUE : titre avec (#252)" 'git log -1 --format=%s | grep -qF "(#252)"'
verif "ISSUE : Refs après Agent" '[ "$(git log -1 --format=%B | grep -E "^(Agent|Refs):" | tr "\n" "|")" = "Agent: script synchroniser-branche|Refs: #252|" ]'
nouveau_depot issue_branche; git checkout -q -b fix/issue-65-liste
echo b > contenu/b.yaml; git add -A; git commit -qm travail
git checkout -q develop && echo c > contenu/c.yaml && git add -A && git commit -qm develop
git update-ref refs/remotes/origin/develop HEAD && git checkout -q fix/issue-65-liste
bash "$SYNCHRO" >/dev/null 2>&1
verif "branche issue-65 : Refs #65" 'git log -1 --format=%B | grep -qx "Refs: #65"'
code=0; ISSUE=abc bash "$SYNCHRO" >/dev/null 2>&1 || code=$?
verif "ISSUE invalide refusé" '[ "$code" -ne 0 ]'

# 5. Conflit ordinaire : listé, code 2, fusion laissée en cours.
nouveau_depot ordinaire; git checkout -q -b travail
sed -i 's/l2/travail/' partage.txt; git commit -qam travail
avancer_develop 'sed -i "s/l2/develop/" partage.txt'
code=0; sortie="$(bash "$SYNCHRO" 2>&1)" || code=$?
verif "conflit ordinaire : code 2" '[ "$code" -eq 2 ]'
verif "conflit listé" 'grep -q partage.txt <<<"$sortie"'
verif "fusion en cours" '[ -f .git/MERGE_HEAD ]'

# 6. resume-commande : code de retour conservé, journal complet gardé.
export JOURNAUX="$T/journaux"
code=0; sortie="$(bash "$RESUME" ok bash -c 'echo un; echo deux')" || code=$?
verif "résumé succès" '[ "$code" -eq 0 ] && grep -q "deux" <<<"$sortie" && ! grep -q "un" <<<"$sortie"'
code=0; sortie="$(bash "$RESUME" ko bash -c 'echo FAILED test_x; exit 3')" || code=$?
verif "résumé échec : code 3" '[ "$code" -eq 3 ]'
verif "résumé échec : erreur visible" 'grep -q "FAILED test_x" <<<"$sortie"'
verif "journal conservé" '[ -s "$JOURNAUX/ko.log" ]'

echo "synchroniser-branche : $reussis réussi(s), $echecs échec(s)"
[ "$echecs" -eq 0 ]
