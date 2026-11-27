#!/usr/bin/env bash
# Issue #252 — Sortie résumée d'une commande longue, journal complet conservé (Claude)
#
# Usage : bash scripts/resume-commande.sh <nom> <commande> [arguments…]
# Journal complet : ${JOURNAUX:-${TMPDIR:-/tmp}/journaux}/<nom>.log
# Succès : affiche la ligne de bilan (ou la dernière ligne non vide). Échec : lignes d'erreur (au plus 40) puis les 30 dernières lignes.
# Le code de retour est toujours celui de la commande.
set -Euo pipefail
[ "$#" -ge 2 ] || { echo "usage : $0 <nom> <commande> [arguments…]" >&2; exit 64; }
nom="$1"; shift
dossier="${JOURNAUX:-${TMPDIR:-/tmp}/journaux}"
mkdir -p "$dossier"
journal="$dossier/$nom.log"

code=0
"$@" > "$journal" 2>&1 || code=$?

if [ "$code" -eq 0 ]; then
  # Ligne de bilan (pytest, vitest, vite, bancs) si elle existe, sinon dernière ligne non vide.
  bilan="$(grep -E '[0-9]+ (passed|réussi)|Tests? +[0-9]+|built in|✓' "$journal" | tail -n 1 || true)"
  [ -n "$bilan" ] || bilan="$(grep -v '^[[:space:]]*$' "$journal" | tail -n 1 || true)"
  echo "✔ $nom : $bilan"
else
  echo "✘ $nom : code $code — journal complet : $journal"
  grep -nE '(^E |Error|ERROR|FAIL|Failed|failed|✗|×|AssertionError|Traceback)' "$journal" | head -n 40 || true
  echo "--- fin du journal ---"
  tail -n 30 "$journal"
fi
exit "$code"
