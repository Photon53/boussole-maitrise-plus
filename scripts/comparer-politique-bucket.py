#!/usr/bin/env python3
# Compare la politique IAM réelle du bucket de déploiement à celle prévue par un plan Terraform (PR 3a, #65).
# Le plan affiche une simple création : il ne montre pas les liaisons retirées. Ce script les liste.
# Usage : python3 scripts/comparer-politique-bucket.py <politique-actuelle.json> <plan.json (terraform show -json)> [projet]
# Rend un verdict CONFORME / NON CONFORME par rapport au résultat attendu de la PR 3a (décision du 12/11 :
# option A, seule projectOwner -> legacyBucketOwner est conservée parmi les liaisons historiques).
# Lecture seule.
import json, sys
avant = json.load(open(sys.argv[1]))
plan = json.load(open(sys.argv[2]))
rc = [r for r in plan.get("resource_changes", []) if r["address"] == "google_storage_bucket_iam_policy.deploiement"]
if not rc:
    sys.exit("[INCOMPLET] google_storage_bucket_iam_policy.deploiement absent du plan")
apres_brut = rc[0]["change"]["after"].get("policy_data") if rc[0]["change"]["after"] else None
if not apres_brut:
    sys.exit("[INCOMPLET] policy_data inconnue au moment du plan (known after apply)")
apres = json.loads(apres_brut)
def liaisons(p):
    s = set()
    for b in p.get("bindings", []):
        c = b.get("condition") or {}
        for m in b["members"]:
            s.add((b["role"], m, c.get("title", ""), c.get("expression", "")))
    return s
A, B = liaisons(avant), liaisons(apres)
print("Actions du plan :", rc[0]["change"]["actions"])
for titre, ens in (("RETIRÉES par l'apply", A - B), ("AJOUTÉES par l'apply", B - A), ("CONSERVÉES", A & B)):
    print(f"\n== {titre} ({len(ens)})")
    for role, m, t, e in sorted(ens):
        print(f"  {role:42} {m}" + (f"   [condition : {t}]" if t else ""))
# --- Résultat attendu (rôle, membre) ; les conditions des liaisons conservées doivent être identiques.
P = sys.argv[3] if len(sys.argv) > 3 else "mer-boussole-dev"
TFPLAN = f"serviceAccount:boussole-dev-tf-plan@{P}.iam.gserviceaccount.com"
ATTENDU_RETIREES = {
    ("roles/storage.legacyBucketOwner", f"projectEditor:{P}"),
    ("roles/storage.legacyBucketReader", f"projectViewer:{P}"),
    ("roles/storage.legacyObjectOwner", f"projectEditor:{P}"),
    ("roles/storage.legacyObjectOwner", f"projectOwner:{P}"),
    ("roles/storage.legacyObjectReader", f"projectViewer:{P}"),
}
ATTENDU_AJOUTEES = {("roles/storage.bucketViewer", TFPLAN)}
ATTENDU_CONSERVEES = {
    ("roles/storage.legacyBucketOwner", f"projectOwner:{P}"),
    ("roles/storage.objectUser", f"serviceAccount:boussole-dev-deployer@{P}.iam.gserviceaccount.com"),
    ("roles/storage.objectViewer", f"serviceAccount:boussole-dev-vm@{P}.iam.gserviceaccount.com"),
    ("roles/storage.objectCreator", f"serviceAccount:boussole-dev-vm@{P}.iam.gserviceaccount.com"),
}
deux = lambda e: {(r, m) for r, m, _, _ in e}
ecarts = []
for nom, obtenu, attendu in (("retirées", deux(A - B), ATTENDU_RETIREES), ("ajoutées", deux(B - A), ATTENDU_AJOUTEES),
                             ("conservées", deux(A & B), ATTENDU_CONSERVEES)):
    if obtenu != attendu:
        ecarts.append(f"{nom} : en trop {sorted(obtenu - attendu)} ; manquantes {sorted(attendu - obtenu)}")
print()
if ecarts:
    print("[NON CONFORME] ne pas appliquer :")
    for e in ecarts: print("  -", e)
    sys.exit(2)
print("[CONFORME] 5 liaisons historiques retirées, projectOwner -> legacyBucketOwner conservée,")
print("           3 liaisons conditionnelles conservées à l'identique, seule liaison ajoutée : bucketViewer pour tf-plan.")
