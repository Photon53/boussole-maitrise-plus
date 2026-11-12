#!/usr/bin/env bash
# Contrôle en LECTURE SEULE des accès au bucket de déploiement, à faire AVANT la première sauvegarde dans
# backups/ (ticket #65). DEV uniquement. À lancer dans Cloud Shell :
#
#   bash scripts/controle-acces-sauvegardes.sh | tee ~/controle-acces.txt
#
# Méthode : lecture des politiques IAM effectives (bucket, projet, ancêtres, politiques de refus) et des
# permissions de chaque rôle, puis évaluation, pour chaque compte, des accès à un objet témoin de backups/ et de
# releases/. Aucune API n'est activée (invites désactivées) ; aucune politique n'est modifiée ; aucun objet n'est
# lu ni créé. Policy Troubleshooter n'est utilisé que si son API est DÉJÀ activée.
#
# Verdicts : ACCORDÉ, REFUSÉ, INDÉTERMINÉ (condition non évaluable, groupe, domaine, politique de refus ou
# lecture impossible). INDÉTERMINÉ n'est jamais compté comme un refus. Code de sortie 0 seulement si tout est
# conforme à l'attendu et déterminé.
set -uo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
P="${PROJECT:-mer-boussole-dev}"
B="${P}-deploiement"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
incomplet=()

lire() {   # lire <fichier> <libellé> <commande…> : 0 si lu
  local f="$1" lib="$2"; shift 2
  if "$@" > "$T/$f" 2> "$T/$f.err"; then return 0; fi
  incomplet+=("$lib : $(tail -1 "$T/$f.err")"); return 1
}

NUM="$(gcloud projects describe "$P" --format='value(projectNumber)' 2>/dev/null)"
[[ -n "$NUM" ]] || { echo "[INCOMPLET] projet $P illisible"; exit 2; }
echo "Projet $P (n° $NUM), bucket gs://$B — contrôle en lecture seule"

lire bucket.json "Politique du bucket" gcloud storage buckets get-iam-policy "gs://$B" --format=json
lire projet.json "Politique du projet" gcloud projects get-iam-policy "$P" --format=json
lire ancetres.json "Ancêtres du projet" gcloud projects get-ancestors "$P" --format=json
: > "$T/ancetres-politiques.jsonl"
if [[ -s "$T/ancetres.json" ]]; then
  while read -r type id; do
    case "$type" in
      organization) lire "anc-$id.json" "Politique de l'organisation $id" gcloud organizations get-iam-policy "$id" --format=json \
                      && python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$T/anc-$id.json" >> "$T/ancetres-politiques.jsonl" ;;
      folder)       lire "anc-$id.json" "Politique du dossier $id" gcloud resource-manager folders get-iam-policy "$id" --format=json \
                      && python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))))' "$T/anc-$id.json" >> "$T/ancetres-politiques.jsonl" ;;
    esac
  done < <(python3 -c 'import json,sys; [print(a["type"], a["id"]) for a in json.load(open(sys.argv[1])) if a["type"] != "project"]' "$T/ancetres.json")
fi
lire refus.json "Politiques de refus du projet" gcloud iam policies list \
  --attachment-point="cloudresourcemanager.googleapis.com%2Fprojects%2F$P" --kind=denypolicies --format=json

# Permissions de chaque rôle cité (prédéfini ou personnalisé).
python3 - "$T" <<'PY' > "$T/roles.txt"
import json, os, sys
t = sys.argv[1]; roles = set()
fichiers = [os.path.join(t, f) for f in ("bucket.json", "projet.json") if os.path.exists(os.path.join(t, f))]
for f in fichiers:
    try: roles |= {b["role"] for b in json.load(open(f)).get("bindings", [])}
    except ValueError: pass
for ligne in open(os.path.join(t, "ancetres-politiques.jsonl")):
    roles |= {b["role"] for b in json.loads(ligne).get("bindings", [])}
print("\n".join(sorted(roles)))
PY
: > "$T/permissions.jsonl"
while read -r role; do
  [[ -n "$role" ]] || continue
  if [[ "$role" == projects/*/roles/* ]]; then args=("${role##*/}" --project "$(cut -d/ -f2 <<<"$role")")
  elif [[ "$role" == organizations/*/roles/* ]]; then args=("${role##*/}" --organization "$(cut -d/ -f2 <<<"$role")")
  else args=("$role"); fi
  if gcloud iam roles describe "${args[@]}" --format=json > "$T/role.json" 2> "$T/role.err"; then
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps({"role": sys.argv[2], "permissions": r.get("includedPermissions", [])}))' "$T/role.json" "$role" >> "$T/permissions.jsonl"
  else
    incomplet+=("Rôle $role illisible : $(tail -1 "$T/role.err")")
  fi
done < "$T/roles.txt"
printf '%s\n' "${incomplet[@]+"${incomplet[@]}"}" > "$T/incomplet.txt"

python3 - "$T" "$P" "$NUM" "$B" <<'PY'
import json, os, re, sys
t, P, NUM, B = sys.argv[1:]
def charger(f, defaut):
    try: return json.load(open(os.path.join(t, f)))
    except (OSError, ValueError): return defaut
bucket = charger("bucket.json", None); projet = charger("projet.json", None)
ancetres = [json.loads(l) for l in open(os.path.join(t, "ancetres-politiques.jsonl")) if l.strip()]
refus = charger("refus.json", None)
if refus is None and os.path.exists(os.path.join(t, "refus.json")) and not open(os.path.join(t, "refus.json")).read().strip():
    refus = []   # liste vide : aucune politique de refus
perms = {}
for l in open(os.path.join(t, "permissions.jsonl")):
    if l.strip():
        d = json.loads(l); perms[d["role"]] = set(d["permissions"])
incomplets = [l for l in open(os.path.join(t, "incomplet.txt")).read().splitlines() if l]

COMPTES = {
    "compte Compute par défaut": f"{NUM}-compute@developer.gserviceaccount.com",
    "boussole-dev-tf-plan": f"boussole-dev-tf-plan@{P}.iam.gserviceaccount.com",
    "boussole-dev-vm": f"boussole-dev-vm@{P}.iam.gserviceaccount.com",
    "boussole-dev-deployer": f"boussole-dev-deployer@{P}.iam.gserviceaccount.com",
}
OBJ = lambda nom: f"projects/_/buckets/{B}/objects/{nom}"
CONTROLES = [  # (compte, permission, ressource, libellé, attendu)
    ("compte Compute par défaut", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("compte Compute par défaut", "storage.objects.delete", OBJ("backups/temoin"), "supprimer une sauvegarde", "REFUSÉ"),
    ("compte Compute par défaut", "storage.objects.list", f"projects/_/buckets/{B}", "lister le bucket", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.objects.list", f"projects/_/buckets/{B}", "lister le bucket", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.buckets.get", f"projects/_/buckets/{B}", "lire le bucket (PLAN)", "ACCORDÉ"),
    ("boussole-dev-tf-plan", "storage.buckets.getIamPolicy", f"projects/_/buckets/{B}", "lire la politique (PLAN)", "ACCORDÉ"),
    ("boussole-dev-deployer", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("boussole-dev-deployer", "storage.objects.create", OBJ("backups/temoin"), "créer une sauvegarde", "REFUSÉ"),
    ("boussole-dev-deployer", "storage.objects.create", OBJ("releases/temoin.json"), "publier dans releases/", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde (restauration)", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.create", OBJ("backups/temoin"), "créer une sauvegarde", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.delete", OBJ("backups/temoin"), "supprimer une sauvegarde", "REFUSÉ"),
    ("boussole-dev-vm", "storage.objects.get", OBJ("releases/desired.json"), "lire la version publiée", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.list", f"projects/_/buckets/{B}", "lister le bucket", "REFUSÉ"),
]

def condition(expr, ressource):
    """True / False / None (non évaluable). Seule forme évaluée : disjonction de resource.name.startsWith("…")."""
    if not expr:
        return True
    termes = [x.strip() for x in expr.split("||")]
    valeurs = []
    for x in termes:
        m = re.fullmatch(r'resource\.name\.startsWith\("([^"]*)"\)', x)
        if not m:
            return None
        valeurs.append(ressource.startswith(m.group(1)))
    return any(valeurs)

def roles_projet(email, politique):
    return {b["role"] for b in (politique or {}).get("bindings", []) if f"serviceAccount:{email}" in b["members"] and not b.get("condition")}

def evaluer(email, permission, ressource):
    if bucket is None or projet is None:
        return "INDÉTERMINÉ", ["politique du bucket ou du projet illisible"]
    base = roles_projet(email, projet)
    for a in ancetres:
        base |= roles_projet(email, a)
    jetons = {f"serviceAccount:{email}", "allUsers", "allAuthenticatedUsers"}
    for role, conv in (("roles/viewer", "projectViewer"), ("roles/editor", "projectEditor"), ("roles/owner", "projectOwner")):
        if role in base:
            jetons.add(f"{conv}:{P}"); jetons.add(f"{conv}:{NUM}")
    accordes, doutes = [], []
    sources = [("bucket", bucket)] + [("projet", projet)] + [("ancêtre", a) for a in ancetres]
    for origine, pol in sources:
        for b in pol.get("bindings", []):
            if b["role"] not in perms:
                if any(m in jetons for m in b["members"]):
                    doutes.append(f"rôle {b['role']} illisible ({origine})")
                continue
            if permission not in perms[b["role"]]:
                continue
            cond = (b.get("condition") or {}).get("expression", "")
            for m in b["members"]:
                if m in jetons:
                    v = condition(cond, ressource)
                    if v is True: accordes.append(f"{b['role']} ({origine}{', condition ' + b['condition'].get('title', '') if cond else ''})")
                    elif v is None: doutes.append(f"{b['role']} ({origine}) : condition non évaluable")
                elif m.split(":", 1)[0] in ("group", "domain", "principalSet", "principal"):
                    doutes.append(f"{b['role']} ({origine}) accordé à {m} : appartenance non vérifiable")
    if accordes:
        # Une politique de refus ne peut que retirer un accès : elle ne rend douteux qu'un accès accordé.
        if refus is None:
            return "INDÉTERMINÉ", accordes + ["politiques de refus illisibles"]
        if refus:
            return "INDÉTERMINÉ", accordes + [f"{len(refus)} politique(s) de refus présente(s) : à examiner"]
        return "ACCORDÉ", accordes
    if doutes:
        return "INDÉTERMINÉ", doutes
    return "REFUSÉ", []

conformes = 0; ecarts = 0
print()
print(f"{'Compte':<26} {'Action':<36} {'Attendu':<9} {'Constaté':<12} Détail")
for compte, perm, res, lib, attendu in CONTROLES:
    v, detail = evaluer(COMPTES[compte], perm, res)
    ok = v == attendu
    conformes += ok; ecarts += not ok
    print(f"{compte:<26} {lib:<36} {attendu:<9} {v:<12} {'OK ' if ok else 'ÉCART '}{'; '.join(detail)}")
print()
for l in incomplets:
    print(f"[INCOMPLET] {l}")
if ecarts or incomplets:
    print(f"RÉSULTAT : NON CONFORME ou INCOMPLET ({conformes} conformes, {ecarts} écarts, {len(incomplets)} lecture(s) incomplète(s))")
    print("Ne pas écrire de sauvegarde avant d'avoir compris chaque écart.")
    sys.exit(1)
print(f"RÉSULTAT : CONFORME ({conformes}/{conformes} contrôles). Limites : appartenance aux groupes et conditions")
print("complexes non évaluées (signalées si présentes) ; contrôle fondé sur les politiques, pas sur un accès réel.")
PY
rc=$?

echo
if gcloud services list --enabled --project="$P" --filter='config.name=policytroubleshooter.googleapis.com' --format='value(config.name)' 2>/dev/null | grep -q .; then
  echo "Policy Troubleshooter déjà activé : contrôle complémentaire de la lecture d'une sauvegarde."
  for email in "$NUM-compute@developer.gserviceaccount.com" "boussole-dev-tf-plan@$P.iam.gserviceaccount.com" "boussole-dev-vm@$P.iam.gserviceaccount.com"; do
    echo "== $email"
    gcloud policy-troubleshoot iam "//storage.googleapis.com/projects/_/buckets/$B" --principal-email="$email" \
      --permission=storage.objects.get --resource-name="projects/_/buckets/$B/objects/backups/temoin" \
      --resource-service=storage.googleapis.com --resource-type=storage.googleapis.com/Object \
      --format='value(overallAccessState)' 2>&1 | tail -3
  done
else
  echo "Policy Troubleshooter non activé : contrôle complémentaire NON effectué (aucune activation automatique)."
  echo "Pour le faire, décision séparée : activer l'API, relancer ce script, puis la désactiver."
fi
exit "$rc"
