#!/usr/bin/env bash
# Vérifie que le déploiement manuel de scripts/deployer-dev-iap.sh est REFUSÉ sur la VM dès que la
# synchronisation automatique est installée (ticket #65, PR 3b, critère obligatoire), et qu'il ne l'est pas
# sinon. Exécute le script VM extrait, avec un faux docker ; pose temporairement /etc/boussole-dev-sync/installe
# (root ou sudo -n requis : runner CI ou conteneur jetable). Usage : bash deploy/vm/tests/test-refus-deploiement-manuel.sh
set -Euo pipefail
RACINE="$(cd "$(dirname "$0")/../../.." && pwd)"
T="$(mktemp -d)"; MARQUEUR=/etc/boussole-dev-sync/installe
if [[ $EUID -eq 0 ]]; then SUDO=(); elif sudo -n true 2>/dev/null; then SUDO=(sudo -n); else echo "IGNORÉ : root ou sudo -n requis"; exit 0; fi
[[ ! -e "$MARQUEUR" ]] || { echo "IGNORÉ : $MARQUEUR existe déjà sur cette machine"; exit 0; }
# Jamais sur une machine portant un déploiement (VM) : les cas « non refusés » atteignent l'étape du code.
[[ ! -e /opt/boussole-dev ]] || { echo "IGNORÉ : /opt/boussole-dev existe (machine de déploiement)"; exit 0; }
trap '"${SUDO[@]}" rm -f "$MARQUEUR"; "${SUDO[@]}" rmdir /etc/boussole-dev-sync 2>/dev/null; rm -rf "$T"' EXIT
awk "/^cat > \"\\\$INSTALLEUR\" <<'VM_EOF'/{f=1;next} /^VM_EOF/{f=0} f" "$RACINE/scripts/deployer-dev-iap.sh" > "$T/installeur.sh"
[[ -s "$T/installeur.sh" ]] || { echo "ECHEC : script VM introuvable dans deployer-dev-iap.sh"; exit 1; }
mkdir -p "$T/bin"
printf '#!/bin/sh\ncase "$1 $2" in "compose version") echo 2.40.3;; "version --format") echo 29.1.3;; *) exit 0;; esac\n' > "$T/bin/docker"
printf '#!/bin/sh\nexit 0\n' > "$T/bin/ss"; chmod +x "$T/bin/"*; : > "$T/bundle"
lancer() { "${SUDO[@]}" env PATH="$T/bin:$PATH" bash "$T/installeur.sh" "$(printf '%040d' 0)" "$T/bundle" "" "" "$1" > "$T/sortie" 2>&1; echo $?; }
echecs=0
"${SUDO[@]}" mkdir -p /etc/boussole-dev-sync; "${SUDO[@]}" touch "$MARQUEUR"
code="$(lancer manuel)"
if [[ "$code" != 0 ]] && grep -q "déploiement manuel REFUSÉ" "$T/sortie" && ! grep -q "Code dans" "$T/sortie"; then
  echo "OK    synchronisation installée : déploiement manuel refusé avant toute modification"
else echo "ECHEC refus attendu (code $code)"; cat "$T/sortie"; echecs=$((echecs + 1)); fi
code="$(lancer synchro)"
if ! grep -q "REFUSÉ" "$T/sortie" && grep -q "Code dans" "$T/sortie"; then
  echo "OK    --installer-synchro : non refusé (mise à jour de la synchronisation possible)"
else echo "ECHEC --installer-synchro ne doit pas être refusé"; cat "$T/sortie"; echecs=$((echecs + 1)); fi
"${SUDO[@]}" rm -f "$MARQUEUR"
code="$(lancer manuel)"
if ! grep -q "REFUSÉ" "$T/sortie" && grep -q "Code dans" "$T/sortie"; then
  echo "OK    sans synchronisation : déploiement manuel non refusé"
else echo "ECHEC le déploiement manuel ne doit pas être refusé sans synchronisation"; cat "$T/sortie"; echecs=$((echecs + 1)); fi
[[ $echecs -eq 0 ]]
