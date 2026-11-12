#!/usr/bin/env python3
"""Appel et classement des réponses de Policy Troubleshooter (ticket #65, PR 3b).

Utilisé par scripts/controle-acces-sauvegardes.sh (contrôle complet) et par son mode --diagnostic-troubleshooter.
Lecture seule : n'active aucune API, ne modifie rien.

Classement d'une réponse (une seule source de vérité pour le contrôle et le diagnostic) :
  ACCORDÉ        état d'accès reconnu : CAN_ACCESS (API v3) ou GRANTED (API v1)
  REFUSÉ         état d'accès reconnu : CANNOT_ACCESS (v3) ou NOT_GRANTED (v1) — véritable refus
  INDÉTERMINÉ    état reconnu mais non concluant (UNKNOWN_CONDITIONAL, UNKNOWN_INFO…)
  INCOMPATIBLE   réponse reçue (code 0) mais format inattendu : vide, non JSON, état absent ou valeur inconnue
  ERREUR         l'appel a échoué (code de sortie non nul : API, droits, réseau, délai)
Seuls ACCORDÉ et REFUSÉ sont des verdicts ; les trois autres ne valent jamais un refus.

Jetons : toute chaîne ressemblant à un jeton OAuth (ya29.…), à un en-tête « Bearer … » ou à un champ
access_token / refresh_token / id_token est masquée avant affichage ou enregistrement.
"""
import json
import os
import re
import subprocess
import sys

ACCORDE = {"CAN_ACCESS", "GRANTED"}
REFUSE = {"CANNOT_ACCESS", "NOT_GRANTED"}
NON_CONCLUANT = {"UNKNOWN_CONDITIONAL", "UNKNOWN_INFO", "UNKNOWN_INFO_DENIED",
                 "OVERALL_ACCESS_STATE_UNSPECIFIED", "ACCESS_STATE_UNSPECIFIED"}
CHAMPS_ETAT = ("overallAccessState", "overall_access_state", "access")
MOTIFS_SECRETS = [
    (re.compile(r"ya29\.[A-Za-z0-9._\-]+"), "[JETON MASQUÉ]"),
    (re.compile(r"(?i)bearer\s+[A-Za-z0-9._\-~+/=]+"), "Bearer [JETON MASQUÉ]"),
    (re.compile(r'(?i)("?(?:access|refresh|id)_token"?\s*[:=]\s*"?)[^"\s,}]+'), r"\1[JETON MASQUÉ]"),
]


def masquer(texte):
    for motif, remplacement in MOTIFS_SECRETS:
        texte = motif.sub(remplacement, texte)
    return texte


def commande(seau, email, permission, ressource):
    objet = "/objects/" in ressource
    return ["gcloud", "policy-troubleshoot", "iam", f"//storage.googleapis.com/{seau}", f"--principal-email={email}",
            f"--permission={permission}", f"--resource-name={ressource}", "--resource-service=storage.googleapis.com",
            f"--resource-type=storage.googleapis.com/{'Object' if objet else 'Bucket'}", "--format=json"]


def interroger(seau, email, permission, ressource, delai=120):
    """Un appel ; renvoie la commande, le code de sortie, la sortie et les erreurs (masqués)."""
    cmd = commande(seau, email, permission, ressource)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=delai)
        code, sortie, erreur = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        code, sortie, erreur = 124, "", f"délai de {delai} s dépassé"
    except OSError as exc:
        code, sortie, erreur = 127, "", str(exc)
    return {"commande": cmd, "code": code, "sortie": masquer(sortie), "erreur": masquer(erreur)}


def classer(rep):
    """(classe, état brut, détail) — voir le docstring du module."""
    if rep["code"] != 0:
        derniere = (rep["erreur"].strip().splitlines() or [f"code {rep['code']}"])[-1]
        return "ERREUR", None, f"erreur d'API (code {rep['code']}) : {derniere}"
    if not rep["sortie"].strip():
        return "INCOMPATIBLE", None, "format inattendu : réponse vide"
    try:
        d = json.loads(rep["sortie"])
    except ValueError:
        return "INCOMPATIBLE", None, "format inattendu : réponse non JSON"
    if isinstance(d, list) and len(d) == 1:
        d = d[0]
    if not isinstance(d, dict):
        return "INCOMPATIBLE", None, f"format inattendu : {type(d).__name__} au lieu d'un objet"
    etat = next((d[c] for c in CHAMPS_ETAT if isinstance(d.get(c), str)), None)
    if etat is None:
        return "INCOMPATIBLE", None, f"format inattendu : état d'accès absent (clés reçues : {', '.join(sorted(d)) or 'aucune'})"
    if etat in ACCORDE:
        return "ACCORDÉ", etat, etat
    if etat in REFUSE:
        return "REFUSÉ", etat, etat
    if etat in NON_CONCLUANT:
        return "INDÉTERMINÉ", etat, f"Troubleshooter non concluant : {etat}"
    return "INCOMPATIBLE", etat, f"format inattendu : valeur d'état inconnue « {etat} »"


def structure(obj, chemin="", lignes=None, profondeur=0):
    """Clés et types de la réponse, sans valeurs (adresses, politiques), sauf les champs d'état ou d'accès."""
    lignes = [] if lignes is None else lignes
    if profondeur > 6:
        lignes.append(f"{chemin or '.'} : … (profondeur limitée)")
        return lignes
    if isinstance(obj, dict):
        if not obj:
            lignes.append(f"{chemin or '.'} : objet vide")
        for k in sorted(obj):
            structure(obj[k], f"{chemin}.{k}" if chemin else k, lignes, profondeur + 1)
    elif isinstance(obj, list):
        lignes.append(f"{chemin or '.'} : liste de {len(obj)} élément(s)")
        if obj:
            structure(obj[0], f"{chemin}[0]", lignes, profondeur + 1)
    elif isinstance(obj, str):
        cle = chemin.rsplit(".", 1)[-1]
        if re.search(r"(?i)(access|state)", cle) and re.fullmatch(r"[A-Z_]+", obj):
            lignes.append(f"{chemin} : « {obj} »")
        else:
            lignes.append(f"{chemin} : chaîne")
    else:
        lignes.append(f"{chemin} : {type(obj).__name__}")
    return lignes


# --- Mode diagnostic : un seul appel ----------------------------------------------------------------------------
CODES_DIAGNOSTIC = {"ACCORDÉ": 0, "REFUSÉ": 7, "INDÉTERMINÉ": 8, "INCOMPATIBLE": 5, "ERREUR": 6}


def diagnostic(projet, seau, fichier):
    email = f"boussole-dev-vm@{projet}.iam.gserviceaccount.com"
    permission, ressource = "storage.objects.get", f"{seau}/objects/releases/desired.json"
    try:
        v = subprocess.run(["gcloud", "version", "--format=json"], capture_output=True, text=True, timeout=60)
        version = masquer(v.stdout.strip()) or masquer(v.stderr.strip())
    except (OSError, subprocess.TimeoutExpired) as exc:
        version = f"illisible : {exc}"
    rep = interroger(seau, email, permission, ressource)
    classe, etat, detail = classer(rep)
    try:
        lignes = structure(json.loads(rep["sortie"])) if rep["sortie"].strip() else ["(réponse vide)"]
    except ValueError:
        lignes = ["(réponse non JSON)"]
    rapport = {"objet": "diagnostic Policy Troubleshooter (un seul appel), ticket #65", "version_gcloud": version,
               "controle": {"principal": "boussole-dev-vm", "permission": permission, "ressource": ressource,
                            "attendu": "ACCORDÉ"},
               "commande": " ".join(rep["commande"]), "code_sortie": rep["code"], "classement": classe,
               "etat_brut": etat, "detail": detail, "structure": lignes,
               "reponse_json_brute": rep["sortie"], "erreurs_brutes": rep["erreur"]}
    ancien = os.umask(0o077)
    try:
        with open(fichier, "w") as f:
            json.dump(rapport, f, indent=2, ensure_ascii=False)
    finally:
        os.umask(ancien)
    print("Diagnostic Policy Troubleshooter — UN seul appel (boussole-dev-vm lit releases/desired.json, attendu ACCORDÉ)")
    print(f"Code de sortie de l'appel : {rep['code']}")
    print(f"Classement : {classe} — {detail}")
    print("Structure de la réponse (clés et types ; seules les valeurs d'état sont affichées) :")
    for l in lignes:
        print(f"  {l}")
    if rep["erreur"].strip():
        print("Erreurs (masquées) :")
        for l in rep["erreur"].strip().splitlines()[-5:]:
            print(f"  {l}")
    print(f"Rapport complet (réponse JSON brute, erreurs, version de gcloud ; jetons masqués) : {fichier}")
    print("Ce fichier contient des explications de politiques IAM (adresses comprises) : le transmettre en privé.")
    signification = {0: "réponse compatible, accès accordé comme attendu", 7: "réponse compatible : VÉRITABLE REFUS d'accès",
                     8: "réponse compatible mais non concluante", 5: "FORMAT INATTENDU : le script doit être adapté",
                     6: "ERREUR D'API : appel en échec (droits, API, réseau)"}
    print(f"Code de sortie du diagnostic : {CODES_DIAGNOSTIC[classe]} ({signification[CODES_DIAGNOSTIC[classe]]})")
    return CODES_DIAGNOSTIC[classe]


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "diagnostic":
        sys.exit(diagnostic(sys.argv[2], sys.argv[3], sys.argv[4]))
    sys.exit("usage : troubleshooter_iam.py diagnostic <projet> <projects/_/buckets/…> <fichier rapport>")
