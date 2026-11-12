#!/usr/bin/env bash
# Audit en LECTURE SEULE des usages du compte Compute par défaut et des droits Cloud Storage des rôles de base
# (ticket #65, décision D4 et préalable à la PR 3a). Projet DEV uniquement. À lancer dans Cloud Shell.
#
#   bash scripts/audit-dev-compte-compute.sh | tee ~/audit-d4.txt
#
# Aucune API n'est activée (invites désactivées), aucun droit ni compte n'est modifié.
# Lecture des résultats :
#   [TROUVÉ]     la commande a réussi et renvoie des éléments
#   [RIEN]       la commande a réussi et ne renvoie rien
#   [INCOMPLET]  la commande a échoué (API désactivée, droit manquant…) : on ne sait PAS si le service est utilisé
# Une absence d'activité dans les journaux ne prouve pas que le compte est inutilisé.
set -uo pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
P="${PROJECT:-mer-boussole-dev}"
NUM="$(gcloud projects describe "$P" --format='value(projectNumber)' 2>/dev/null)"
SA="${NUM}-compute@developer.gserviceaccount.com"
TFPLAN="boussole-dev-tf-plan@${P}.iam.gserviceaccount.com"
BUCKET="${P}-deploiement"
[[ -n "$NUM" ]] || { echo "[INCOMPLET] projet $P illisible"; exit 1; }

controle() {   # controle <libellé> <commande...>
  local libelle="$1" sortie rc; shift
  sortie="$("$@" 2>&1)"; rc=$?
  if (( rc != 0 )); then printf '[INCOMPLET] %s\n             %s\n' "$libelle" "$(tail -1 <<<"$sortie")"
  elif [[ -z "${sortie//[[:space:]]/}" ]]; then printf '[RIEN]      %s\n' "$libelle"
  else printf '[TROUVÉ]    %s\n' "$libelle"; sed 's/^/             /' <<<"$sortie"; fi
}
permissions_storage() {   # rôle -> permissions storage.buckets.* et storage.objects.*
  gcloud iam roles describe "$1" --format=json | python3 -c 'import json,sys; print("\n".join(sorted(p for p in json.load(sys.stdin).get("includedPermissions",[]) if p.startswith(("storage.buckets.","storage.objects.")))))'
}

echo "Projet $P, compte audité $SA"
echo; echo "=== 1. Droits Cloud Storage des rôles de base (ce qui reste après le retrait des liaisons historiques)"
for r in roles/viewer roles/editor roles/owner; do controle "Permissions storage.* de $r" permissions_storage "$r"; done

echo; echo "=== 2. Droits de tf-plan nécessaires au PLAN (lire le bucket et sa politique IAM)"
controle "Rôles de tf-plan sur le projet" gcloud projects get-iam-policy "$P" --flatten=bindings --filter="bindings.members:serviceAccount:$TFPLAN" --format='value(bindings.role)'
for r in $(gcloud projects get-iam-policy "$P" --flatten=bindings --filter="bindings.members:serviceAccount:$TFPLAN" --format='value(bindings.role)' 2>/dev/null); do
  controle "$r : storage.buckets.get / getIamPolicy" bash -c "gcloud iam roles describe '$r' --format=json | python3 -c 'import json,sys; print(\"\\n\".join(p for p in json.load(sys.stdin).get(\"includedPermissions\",[]) if p in (\"storage.buckets.get\",\"storage.buckets.getIamPolicy\")))'"
done
controle "Liaisons de tf-plan sur le bucket $BUCKET" bash -c "gcloud storage buckets get-iam-policy gs://$BUCKET --format=json | grep -n '$TFPLAN' || true"

echo; echo "=== 3. Compte Compute par défaut : rôles, état, clés, emprunt"
controle "Rôles sur le projet" gcloud projects get-iam-policy "$P" --flatten=bindings --filter="bindings.members:serviceAccount:$SA" --format='value(bindings.role)'
controle "Compte désactivé ?" gcloud iam service-accounts describe "$SA" --format='value(disabled.yesno(yes=OUI,no=NON))'
controle "Clés gérées par l'utilisateur" gcloud iam service-accounts keys list --iam-account="$SA" --managed-by=user
controle "Qui peut emprunter le compte" gcloud iam service-accounts get-iam-policy "$SA" --format='value(bindings)'
controle "Liaisons IAM citant le compte (Cloud Asset)" gcloud asset search-all-iam-policies --scope="projects/$P" --query="policy:$SA" --format='table(resource,policy.bindings.role)'

echo; echo "=== 4. Ressources pouvant s'exécuter sous ce compte"
controle "APIs activées" gcloud services list --enabled --project="$P" --format='value(config.name)'
controle "VM" gcloud compute instances list --project="$P" --format='table(name,zone.basename(),serviceAccounts[].email)'
controle "Modèles d'instance" gcloud compute instance-templates list --project="$P" --format='table(name,properties.serviceAccounts[].email)'
controle "Cloud Build : compte par défaut" gcloud builds get-default-service-account --project="$P"
controle "Cloud Build : déclencheurs" gcloud builds triggers list --project="$P" --format='table(name,serviceAccount)'
controle "Cloud Run services (compte vide = compte Compute par défaut)" gcloud run services list --project="$P" --format='table(metadata.name,region,spec.template.spec.serviceAccountName)'
controle "Cloud Run jobs" gcloud run jobs list --project="$P" --format='table(metadata.name,spec.template.spec.template.spec.serviceAccountName)'
controle "Cloud Functions" gcloud functions list --project="$P" --format='table(name,serviceConfig.serviceAccountEmail)'
controle "App Engine" gcloud app describe --project="$P" --format='value(serviceAccount)'
controle "GKE" gcloud container clusters list --project="$P"
controle "Cloud Scheduler (europe-west9)" gcloud scheduler jobs list --project="$P" --location=europe-west9
controle "Dataflow" gcloud dataflow jobs list --project="$P" --status=active

echo; echo "=== 5. Activité du compte (journaux d'activité admin, 30 jours ; les accès aux données ne sont pas journalisés par défaut)"
controle "Appels authentifiés par le compte" gcloud logging read "protoPayload.authenticationInfo.principalEmail=\"$SA\"" --project="$P" --freshness=30d --limit=20 --format='table(timestamp,protoPayload.serviceName,protoPayload.methodName)'
