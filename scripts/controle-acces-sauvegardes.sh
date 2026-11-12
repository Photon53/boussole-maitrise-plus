#!/usr/bin/env bash
# Contrôle en LECTURE SEULE des accès au bucket de déploiement, à faire AVANT la première sauvegarde dans
# backups/ (ticket #65). DEV uniquement. À lancer dans Cloud Shell :
#
#   set -o pipefail
#   bash scripts/controle-acces-sauvegardes.sh 2>&1 | tee ~/controle-acces.txt
#
# Mode diagnostic (UN seul appel à Policy Troubleshooter, API déjà activée par décision séparée) :
#   bash scripts/controle-acces-sauvegardes.sh --diagnostic-troubleshooter
# Il conserve dans ~/diagnostic-troubleshooter.json (mode 600) la réponse JSON brute, les erreurs, le code de
# sortie de l'appel, la version de gcloud et la structure de la réponse ; jetons masqués. Codes de sortie :
#   0 réponse compatible, accès accordé (attendu)   7 réponse compatible : VÉRITABLE REFUS d'accès
#   8 réponse compatible, non concluante           5 FORMAT INATTENDU (le script doit être adapté)
#   6 ERREUR D'API (appel en échec)                 4 API non activée : aucun appel effectué
#   9 ÉVALUATION INCOMPLÈTE : la réponse contient des erreurs (champ « errors ») ; l'état annoncé n'est pas un verdict
#
# 1. Analyse des politiques : politiques IAM d'autorisation (bucket, projet, dossiers et organisation parents),
#    politiques de REFUS à tous ces niveaux, permissions de chaque rôle ; évaluation de 15 accès sur des objets
#    témoins de backups/ et releases/ et sur le bucket.
# 2. Confirmation par Policy Troubleshooter, SEULEMENT si son API est déjà activée (jamais d'activation) : chaque
#    contrôle est soumis ; son résultat entre dans le verdict (contradiction ou erreur = non conforme).
#
# Aucune API activée (invites désactivées), aucune politique modifiée, aucun objet lu ni créé.
# Réponses brutes de Troubleshooter (diagnostic) : ~/controle-acces-troubleshooter.jsonl, réécrit à chaque
# exécution (contient des explications de politiques IAM, dont des adresses : ne pas le publier).
# Verdicts par contrôle : ACCORDÉ, REFUSÉ, INDÉTERMINÉ (jamais compté comme un refus). Troubleshooter peut aussi
# répondre INCOMPATIBLE (format inattendu), ERREUR (appel en échec) ou INCOMPLET (réponse avec erreurs) : écart,
# jamais un refus (classement commun
# avec le diagnostic : scripts/troubleshooter_iam.py).
#
# EXCEPTION D5 (décision du propriétaire, ticket #65, DEV) : boussole-dev-tf-plan peut LISTER les objets du
# bucket et leurs métadonnées (storage.objects.list, via roles/iam.securityReviewer au niveau du projet). Il ne
# doit JAMAIS pouvoir lire leur contenu : les contrôles de lecture (storage.objects.get) restent stricts et
# l'exception n'est valable que si ces contrôles sont conformes. L'exception tolère la liste sans l'exiger :
# une réduction ultérieure des droits (option B, ticket #74) reste conforme.
# Codes de sortie :
#   0  conforme, confirmé par Policy Troubleshooter pour les 16 contrôles
#   3  conforme selon l'analyse des politiques SEULEMENT (Troubleshooter non activé) : pas une preuve d'accès
#   1  non conforme, indéterminé, lecture incomplète, ou erreur / contradiction de Troubleshooter
#   2  projet illisible
set -uo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
P="${PROJECT:-mer-boussole-dev}"
B="${P}-deploiement"
ICI="$(cd "$(dirname "$0")" && pwd)"

api_troubleshooter_active() {   # lecture seule : jamais d'activation
  gcloud services list --enabled --project="$P" --filter='config.name=policytroubleshooter.googleapis.com' \
    --format='value(config.name)' 2>/dev/null | grep -q policytroubleshooter
}
if [[ "${1:-}" == --diagnostic-troubleshooter ]]; then
  if ! api_troubleshooter_active; then
    echo "API Policy Troubleshooter non activée : AUCUN appel effectué (ce script ne l'active jamais)."
    echo "Décision séparée : activer l'API, relancer ce diagnostic, puis la désactiver."
    exit 4
  fi
  exec python3 "$ICI/troubleshooter_iam.py" diagnostic "$P" "projects/_/buckets/$B" "$HOME/diagnostic-troubleshooter.json"
elif [[ $# -gt 0 ]]; then
  echo "Option inconnue : $1 (seule option : --diagnostic-troubleshooter)"; exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
: > "$T/incomplet.txt"; : > "$T/autorisations.jsonl"; : > "$T/refus.jsonl"; : > "$T/permissions.jsonl"

lire() {   # lire <fichier> <libellé> <commande…> : 0 si lu ; sinon consigné comme lecture incomplète
  local f="$1" lib="$2"; shift 2
  if "$@" > "$T/$f" 2> "$T/$f.err"; then return 0; fi
  printf '%s : %s\n' "$lib" "$(tail -1 "$T/$f.err")" >> "$T/incomplet.txt"; return 1
}
ajouter() {   # ajouter <fichier JSON> <jsonl> <niveau> : une ligne {"niveau":…, "politique":…}
  python3 -c 'import json,sys
t = open(sys.argv[1]).read().strip()
print(json.dumps({"niveau": sys.argv[2], "politique": json.loads(t) if t else []}))' "$T/$1" "$3" >> "$T/$2"
}
refus_de() {   # refus_de <ressource « projects/ID » | « folders/ID » | « organizations/ID »> <libellé>
  local f; f="refus-${1//\//-}.json"
  lire "$f" "Politiques de refus ($2)" gcloud iam policies list \
    --attachment-point="cloudresourcemanager.googleapis.com%2F${1//\//%2F}" --kind=denypolicies --format=json \
    && ajouter "$f" refus.jsonl "$2"
}

NUM="$(gcloud projects describe "$P" --format='value(projectNumber)' 2>/dev/null)"
[[ -n "$NUM" ]] || { echo "[INCOMPLET] projet $P illisible"; exit 2; }
echo "Projet $P (n° $NUM), bucket gs://$B — contrôle en lecture seule"

lire bucket.json "Politique du bucket" gcloud storage buckets get-iam-policy "gs://$B" --format=json \
  && ajouter bucket.json autorisations.jsonl bucket
lire projet.json "Politique du projet" gcloud projects get-iam-policy "$P" --format=json \
  && ajouter projet.json autorisations.jsonl projet
refus_de "projects/$P" "projet"
if lire ancetres.json "Ancêtres du projet" gcloud projects get-ancestors "$P" --format=json; then
  while read -r type id; do
    case "$type" in
      organization)
        lire "anc-$id.json" "Politique de l'organisation $id" gcloud organizations get-iam-policy "$id" --format=json \
          && ajouter "anc-$id.json" autorisations.jsonl "organisation $id"
        refus_de "organizations/$id" "organisation $id" ;;
      folder)
        lire "anc-$id.json" "Politique du dossier $id" gcloud resource-manager folders get-iam-policy "$id" --format=json \
          && ajouter "anc-$id.json" autorisations.jsonl "dossier $id"
        refus_de "folders/$id" "dossier $id" ;;
    esac
  done < <(python3 -c 'import json,sys; [print(a["type"], a["id"]) for a in json.load(open(sys.argv[1])) if a["type"] != "project"]' "$T/ancetres.json")
fi

# Permissions de chaque rôle cité (prédéfini ou personnalisé).
python3 -c 'import json,sys
roles = set()
for l in open(sys.argv[1]):
    roles |= {b["role"] for b in json.loads(l)["politique"].get("bindings", [])}
print("\n".join(sorted(roles)))' "$T/autorisations.jsonl" > "$T/roles.txt"
while read -r role; do
  [[ -n "$role" ]] || continue
  if [[ "$role" == projects/*/roles/* ]]; then args=("${role##*/}" --project "$(cut -d/ -f2 <<<"$role")")
  elif [[ "$role" == organizations/*/roles/* ]]; then args=("${role##*/}" --organization "$(cut -d/ -f2 <<<"$role")")
  else args=("$role"); fi
  if gcloud iam roles describe "${args[@]}" --format=json > "$T/role.json" 2> "$T/role.err"; then
    python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); print(json.dumps({"role": sys.argv[2], "permissions": r.get("includedPermissions", [])}))' "$T/role.json" "$role" >> "$T/permissions.jsonl"
  else
    printf 'Rôle %s illisible : %s\n' "$role" "$(tail -1 "$T/role.err")" >> "$T/incomplet.txt"
  fi
done < "$T/roles.txt"

# Policy Troubleshooter : utilisé seulement s'il est DÉJÀ activé.
TROUBLESHOOTER=non
if api_troubleshooter_active; then TROUBLESHOOTER=oui; fi

python3 - "$T" "$P" "$NUM" "$B" "$TROUBLESHOOTER" "$ICI" <<'PY'
import json, os, re, subprocess, sys
t, P, NUM, B, TS, ICI = sys.argv[1:]
sys.path.insert(0, ICI)
import troubleshooter_iam as tsi
autorisations = [json.loads(l) for l in open(os.path.join(t, "autorisations.jsonl")) if l.strip()]
refus = [json.loads(l) for l in open(os.path.join(t, "refus.jsonl")) if l.strip()]
perms = {}
for l in open(os.path.join(t, "permissions.jsonl")):
    if l.strip():
        d = json.loads(l); perms[d["role"]] = set(d["permissions"])
incomplets = [l for l in open(os.path.join(t, "incomplet.txt")).read().splitlines() if l]
niveaux_lus = {a["niveau"] for a in autorisations}
politique = {a["niveau"]: a["politique"] for a in autorisations}
politiques_refus = [(r["niveau"], p) for r in refus for p in (r["politique"] or [])]

COMPTES = {
    "compte Compute par défaut": f"{NUM}-compute@developer.gserviceaccount.com",
    "boussole-dev-tf-plan": f"boussole-dev-tf-plan@{P}.iam.gserviceaccount.com",
    "boussole-dev-vm": f"boussole-dev-vm@{P}.iam.gserviceaccount.com",
    "boussole-dev-deployer": f"boussole-dev-deployer@{P}.iam.gserviceaccount.com",
}
SEAU = f"projects/_/buckets/{B}"
OBJ = lambda nom: f"{SEAU}/objects/{nom}"
# Attendu : un verdict, ou EXCEPTION_D5 (liste tolérée : ACCORDÉ ou REFUSÉ, jamais INDÉTERMINÉ).
EXCEPTION_D5 = "D5"
CONTROLES = [  # (compte, permission, ressource, libellé, attendu)
    ("compte Compute par défaut", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("compte Compute par défaut", "storage.objects.delete", OBJ("backups/temoin"), "supprimer une sauvegarde", "REFUSÉ"),
    ("compte Compute par défaut", "storage.objects.list", SEAU, "lister le bucket", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.objects.list", SEAU, "lister objets et métadonnées", EXCEPTION_D5),
    ("boussole-dev-tf-plan", "storage.objects.get", OBJ("releases/desired.json"), "lire un objet de releases/", "REFUSÉ"),
    ("boussole-dev-tf-plan", "storage.buckets.get", SEAU, "lire le bucket (PLAN)", "ACCORDÉ"),
    ("boussole-dev-tf-plan", "storage.buckets.getIamPolicy", SEAU, "lire la politique (PLAN)", "ACCORDÉ"),
    ("boussole-dev-deployer", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde", "REFUSÉ"),
    ("boussole-dev-deployer", "storage.objects.create", OBJ("backups/temoin"), "créer une sauvegarde", "REFUSÉ"),
    ("boussole-dev-deployer", "storage.objects.create", OBJ("releases/temoin.json"), "publier dans releases/", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.get", OBJ("backups/temoin"), "lire une sauvegarde (restauration)", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.create", OBJ("backups/temoin"), "créer une sauvegarde", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.delete", OBJ("backups/temoin"), "supprimer une sauvegarde", "REFUSÉ"),
    ("boussole-dev-vm", "storage.objects.get", OBJ("releases/desired.json"), "lire la version publiée", "ACCORDÉ"),
    ("boussole-dev-vm", "storage.objects.list", SEAU, "lister le bucket", "REFUSÉ"),
]

def condition(expr, ressource):
    """True / False / None (non évaluable). Seule forme évaluée : disjonction de resource.name.startsWith("…")."""
    if not expr:
        return True
    valeurs = []
    for x in (y.strip() for y in expr.split("||")):
        m = re.fullmatch(r'resource\.name\.startsWith\("([^"]*)"\)', x)
        if not m:
            return None
        valeurs.append(ressource.startswith(m.group(1)))
    return any(valeurs)

def roles_de_base(email):
    roles = set()
    for niveau, pol in politique.items():
        if niveau != "bucket":
            roles |= {b["role"] for b in pol.get("bindings", []) if f"serviceAccount:{email}" in b["members"] and not b.get("condition")}
    return roles

def analyser(email, permission, ressource):
    if "bucket" not in niveaux_lus or "projet" not in niveaux_lus:
        return "INDÉTERMINÉ", ["politique du bucket ou du projet illisible"]
    base = roles_de_base(email)
    jetons = {f"serviceAccount:{email}", "allUsers", "allAuthenticatedUsers"}
    for role, conv in (("roles/viewer", "projectViewer"), ("roles/editor", "projectEditor"), ("roles/owner", "projectOwner")):
        if role in base:
            jetons |= {f"{conv}:{P}", f"{conv}:{NUM}"}
    accordes, doutes = [], []
    for niveau, pol in politique.items():
        for b in pol.get("bindings", []):
            concerne = [m for m in b["members"] if m in jetons]
            indirects = [m for m in b["members"] if m.split(":", 1)[0] in ("group", "domain", "principalSet", "principal")]
            if not concerne and not indirects:
                continue
            if b["role"] not in perms:
                doutes.append(f"rôle {b['role']} illisible ({niveau})")
                continue
            if permission not in perms[b["role"]]:
                continue
            cond = (b.get("condition") or {}).get("expression", "")
            if concerne:
                v = condition(cond, ressource)
                if v is True:
                    accordes.append(f"{b['role']} ({niveau}{', condition ' + b['condition'].get('title', '') if cond else ''})")
                elif v is None:
                    doutes.append(f"{b['role']} ({niveau}) : condition non évaluable")
            for m in indirects:
                doutes.append(f"{b['role']} ({niveau}) accordé à {m} : appartenance non vérifiable")
    if accordes:
        # Une politique de refus ne peut que retirer un accès : elle rend douteux un accès accordé.
        if politiques_refus:
            return "INDÉTERMINÉ", accordes + [f"politique(s) de refus présente(s) ({', '.join(sorted({n for n, _ in politiques_refus}))}) : à examiner"]
        if any(l.startswith("Politiques de refus") for l in incomplets):
            return "INDÉTERMINÉ", accordes + ["politiques de refus illisibles à au moins un niveau"]
        return "ACCORDÉ", accordes
    if doutes:
        return "INDÉTERMINÉ", doutes
    return "REFUSÉ", []

# Policy Troubleshooter : appel et classement communs avec le mode diagnostic (scripts/troubleshooter_iam.py).
JOURNAL_TS = os.path.join(os.path.expanduser("~"), "controle-acces-troubleshooter.jsonl")
if TS == "oui":
    ancien = os.umask(0o077); open(JOURNAL_TS, "w").close(); os.umask(ancien)
def troubleshooter(email, permission, ressource):
    rep = tsi.interroger(SEAU, email, permission, ressource)
    classe, etat, detail = tsi.classer(rep)
    with open(JOURNAL_TS, "a") as j:
        j.write(json.dumps({"principal": email, "permission": permission, "ressource": ressource, "code": rep["code"],
                            "classement": classe, "sortie": rep["sortie"][:20000], "erreur": rep["erreur"][-2000:]},
                           ensure_ascii=False) + "\n")
    return classe, detail

print()
print(f"Policy Troubleshooter : {'ACTIVÉ — chaque contrôle lui est soumis' if TS == 'oui' else 'non activé — analyse des politiques seulement'}")
print()
print(f"{'Compte':<26} {'Action':<36} {'Attendu':<9} {'Politiques':<12} {'Troubleshooter':<14} Détail")
ecarts = 0
exception_utilisee = False
lecture_tf_plan_refusee = True
for compte, perm, res, lib, attendu in CONTROLES:
    email = COMPTES[compte]
    v, detail = analyser(email, perm, res)
    ts, ts_detail = troubleshooter(email, perm, res) if TS == "oui" else ("—", "")
    if attendu == EXCEPTION_D5:
        admis = {"ACCORDÉ", "REFUSÉ"}
        ok = v in admis and (TS != "oui" or ts == v)
        exception_utilisee |= ok and v == "ACCORDÉ"
        affiche = "D5"
    else:
        ok = v == attendu and (TS != "oui" or ts == attendu)
        affiche = attendu
    if compte == "boussole-dev-tf-plan" and perm == "storage.objects.get":
        lecture_tf_plan_refusee &= ok
    remarques = list(detail)
    if TS == "oui" and ts in ("ACCORDÉ", "REFUSÉ") and ts != v:
        remarques.append(f"CONTRADICTION : Troubleshooter {ts}, analyse {v}")
    elif TS == "oui" and ts not in ("ACCORDÉ", "REFUSÉ"):
        remarques.append(f"Troubleshooter {ts} : {ts_detail}")
    if attendu == EXCEPTION_D5 and ok:
        remarques.insert(0, "exception D5 acceptée" if v == "ACCORDÉ" else "exception D5 non utilisée (liste refusée)")
    ecarts += not ok
    print(f"{compte:<26} {lib:<36} {affiche:<9} {v:<12} {ts:<14} {'OK ' if ok else 'ÉCART '}{'; '.join(remarques)}")
print()
if exception_utilisee:
    if lecture_tf_plan_refusee:
        print("Exception D5 acceptée : boussole-dev-tf-plan peut lister les objets du bucket et leurs métadonnées ;")
        print("la lecture de leur contenu lui est refusée (contrôles de lecture conformes).")
    else:
        print("Exception D5 INVALIDE : boussole-dev-tf-plan liste les objets ET leur lecture n'est pas refusée.")
    print()
for l in incomplets:
    print(f"[INCOMPLET] {l}")
if ecarts or incomplets:
    print(f"RÉSULTAT : NON CONFORME ou INCOMPLET ({len(CONTROLES) - ecarts} conformes, {ecarts} écarts, {len(incomplets)} lecture(s) incomplète(s))")
    print("Ne pas écrire de sauvegarde avant d'avoir compris chaque écart.")
    sys.exit(1)
if TS == "oui":
    print(f"RÉSULTAT : CONFORME ({len(CONTROLES)}/{len(CONTROLES)}), confirmé par Policy Troubleshooter pour chaque contrôle.")
    sys.exit(0)
print(f"RÉSULTAT : CONFORME SELON L'ANALYSE DES POLITIQUES ({len(CONTROLES)}/{len(CONTROLES)}) — NON CONFIRMÉ par Policy Troubleshooter.")
print("Ce n'est pas une preuve d'accès réel. Pour la confirmation : activer l'API (décision séparée), relancer, désactiver.")
sys.exit(3)
PY
