#!/usr/bin/env python3
# Compare la politique IAM réelle du bucket de déploiement à celle prévue par un plan Terraform (PR 3a, #65).
# Le plan affiche une simple création : il ne montre pas les liaisons retirées. Ce script les liste.
# Usage : python3 scripts/comparer-politique-bucket.py <politique-actuelle.json> <plan.json (terraform show -json)>
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
if B - A:
    print("\n[À VÉRIFIER] liaisons ajoutées : attendu, uniquement roles/storage.bucketViewer pour boussole-dev-tf-plan.")
