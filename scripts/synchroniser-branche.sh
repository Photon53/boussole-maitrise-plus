#!/usr/bin/env bash
# Issue #252 — Synchronisation d'une branche de travail avec develop (Claude)
#
# Fusionne origin/<base> (défaut : develop) dans la branche courante, sans rebase ni push :
#   - fichiers générés en conflit : version de la base reprise, puis régénération ;
#   - inventaires régénérés après toute fusion qui touche le contenu, commit séparé s'ils changent ;
#   - autres conflits : listés, fusion laissée en cours pour résolution (code 2).
# Usage : bash scripts/synchroniser-branche.sh [base]
# Variables : AGENT (attribution des commits), SYNCHRO_PY (interpréteur Python), SYNCHRO_SANS_FETCH=1 (tests).
set -Euo pipefail

BASE="${1:-develop}"
RACINE="$(git rev-parse --show-toplevel)"
cd "$RACINE"
AGENT="${AGENT:-script synchroniser-branche}"
if [ -n "${SYNCHRO_PY:-}" ]; then PY="$SYNCHRO_PY"
elif [ -x .venv/bin/python ]; then PY="$RACINE/.venv/bin/python"
else PY=python3; fi

GENERES=(docs/CONTENU-INVENTAIRE.md docs/audit/CORRIGES-INVENTAIRE.md web/package-lock.json)

erreur() { echo "synchroniser-branche : $*" >&2; exit 1; }

regenerer() {   # regenerer <fichier généré>
  case "$1" in
    docs/CONTENU-INVENTAIRE.md) (cd api && "$PY" -m app.contenu inventaire >/dev/null) ;;
    docs/audit/CORRIGES-INVENTAIRE.md) (cd api && "$PY" -m app.contenu corrections >/dev/null) ;;
    web/package-lock.json) (cd web && npm install --package-lock-only --no-audit --no-fund >/dev/null) ;;
  esac
}

branche="$(git branch --show-current)"
[ -n "$branche" ] || erreur "HEAD détaché : se placer sur une branche de travail"
case "$branche" in main|develop|"$BASE") erreur "refus sur la branche protégée « $branche »" ;; esac
git diff --quiet && git diff --cached --quiet || erreur "modifications non commitées : les commiter ou les mettre de côté"
[ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ] && erreur "une fusion est déjà en cours"

[ "${SYNCHRO_SANS_FETCH:-0}" = 1 ] || git fetch -q origin "$BASE" || erreur "échec de git fetch origin $BASE"
cible="origin/$BASE"
if git merge-base --is-ancestor "$cible" HEAD; then echo "À jour avec $cible."; exit 0; fi
avant="$(git rev-parse HEAD)"

if ! git merge --no-edit -q "$cible" >/dev/null 2>&1; then
  mapfile -t conflits < <(git diff --name-only --diff-filter=U)
  [ "${#conflits[@]}" -gt 0 ] || erreur "la fusion a échoué sans conflit (voir git status)"
  restants=()
  for f in "${conflits[@]}"; do
    if printf '%s\n' "${GENERES[@]}" | grep -qxF "$f"; then
      git checkout -q --theirs -- "$f" && regenerer "$f" && git add -- "$f" \
        && echo "Régénéré : $f" || restants+=("$f")
    else
      restants+=("$f")
    fi
  done
  if [ "${#restants[@]}" -gt 0 ]; then
    echo "Conflits à résoudre (fusion en cours ; git merge --abort pour annuler) :"
    printf '  %s\n' "${restants[@]}"
    exit 2
  fi
  git commit -q --no-edit
fi

# Les deux côtés ont pu ajouter du contenu sans conflit : l'inventaire fusionné peut être périmé.
if ! git diff --quiet "$avant" HEAD -- contenu api/app/contenu.py; then
  for f in docs/CONTENU-INVENTAIRE.md docs/audit/CORRIGES-INVENTAIRE.md; do
    [ -f "$f" ] && { regenerer "$f" || erreur "régénération impossible : $f"; }
  done
  if ! git diff --quiet -- docs/CONTENU-INVENTAIRE.md docs/audit/CORRIGES-INVENTAIRE.md; then
    git add -- docs/CONTENU-INVENTAIRE.md docs/audit/CORRIGES-INVENTAIRE.md
    git commit -q -m "chore(contenu): régénère les inventaires après synchronisation avec $BASE" -m "Agent: $AGENT"
    echo "Inventaires régénérés."
  fi
fi
echo "Synchronisé avec $cible : $(git rev-list --count "$avant"..HEAD) commit(s) ajouté(s), rien n'est poussé."
