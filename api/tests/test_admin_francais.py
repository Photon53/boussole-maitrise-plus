"""Page « Français » de l'administration (#231) : synthèse en lecture seule, réservée à l'administrateur."""
# Issue #231 — Espace administrateur Français (Claude)

import json

from sqlalchemy import select

from app import francais, permissions
from app.config import settings
from app.db import models
from app.referentiel import StatutValidation
from tests.conftest import connecter_admin, connecter_eleve, connecter_enseignant, inscrire_eleves

URL = "/admin/francais/synthese"


def _activer(client, admin) -> None:
    r = client.post("/admin/domaines/francais-college", headers=admin, json={"actif": True, "public": False})
    assert r.status_code == 200, r.text


def _synthese(client, admin) -> dict:
    r = client.get(URL, headers=admin)
    assert r.status_code == 200, r.text
    assert r.headers["cache-control"] == "private, no-store"
    return r.json()


def test_reservee_a_l_administrateur(client):
    assert client.get(URL).status_code == 401
    assert client.get(URL, headers=connecter_enseignant(client)).status_code == 401
    assert client.get(URL, headers=connecter_eleve(client)).status_code == 401


def test_domaine_inactif_signale_en_premier(client):
    s = _synthese(client, connecter_admin(client))
    college = next(d for d in s["domaines"] if d["code"] == "francais-college")
    assert college == {"code": "francais-college", "libelle": "Français collège", "actif": False, "public": False}
    assert s["alertes"][0]["gravite"] == "bloquant"
    assert s["alertes"][0]["action"] == "domaines"


def test_chapitres_et_dossiers_presentes_ensemble(client, fabrique):
    with fabrique() as session:
        francais.importer(session, francais.charger(francais.DOSSIER_PAR_DEFAUT))
    admin = connecter_admin(client)
    _activer(client, admin)
    s = _synthese(client, admin)
    chapitres = [c for c in s["cours"] if c["type"] == "chapitre"]
    dossiers = [c for c in s["cours"] if c["type"] == "dossier"]
    # Les cours du dépôt (#177) : six cours, quatre sujets de rédaction, deux chapitres associés aux dossiers de 3e.
    assert {c["niveau"] for c in chapitres} == {"6e", "5e", "4e", "3e"}
    assert {c["rubrique"] for c in chapitres} >= {"grammaire", "conjugaison", "redaction"}
    assert dossiers and all(d["rubrique"] == "lire" and d["niveau"] == "3e" for d in dossiers)
    # Rien n'est validé dans le dépôt : tout est à valider, et l'alerte le dit.
    assert all(c["statut"] in ("a_valider", "vide") for c in chapitres)
    assert any(a["action"] == "validation-questions" for a in s["alertes"])
    assert [n["niveau"] for n in s["niveaux"]] == ["6e", "5e", "4e", "3e"]
    assert s["chiffres"]["cours"] == len(s["cours"])
    assert s["chiffres"]["questions_validees"] == 0


def test_cours_pret_et_ouvert_a_une_classe_pilote(client, session):
    admin = connecter_admin(client)
    _activer(client, admin)
    chapitre = session.scalar(select(models.Chapitre).where(models.Chapitre.code == "FR5-FONCTIONS"))
    for competence in chapitre.competences:
        for q in competence.questions:
            q.statut_validation = StatutValidation.VALIDEE
    prof = session.scalar(select(models.Enseignant).where(models.Enseignant.email == "demo@pkp.test"))
    permissions.appliquer(session, prof, [*permissions.portees(prof),
                                          permissions.Portee(permissions.PROFESSEUR, "francais-college"),
                                          permissions.Portee(permissions.VALIDATEUR, "francais-college", "5e")], None)
    session.commit()
    r = client.post("/admin/classes-pilotes", headers=admin,
                    json={"matiere": "francais", "niveau": "5e", "enseignant_id": prof.id, "motif": "Pilote de janvier 2027"})
    assert r.status_code == 201, r.text
    classe = r.json()
    # Une nouvelle classe reçoit tout le programme de son niveau : le retirer pour tester l'alerte.
    r = client.put(f"/admin/classes/{classe['classe_id']}/chapitres", headers=admin, json={"chapitre_ids": []})
    assert r.status_code == 200, r.text

    s = _synthese(client, admin)
    pilote = next(c for c in s["classes"] if c["code"] == classe["code"])
    assert pilote["pilote"] and pilote["cours_ouverts"] == 0 and pilote["eleves"] == 0
    assert any(classe["code"] in a["message"] and "aucun cours ouvert" in a["message"] for a in s["alertes"])

    inscrire_eleves(client, classe["code"], ["Lina"])
    r = client.put(f"/admin/classes/{classe['classe_id']}/chapitres", headers=admin, json={"chapitre_ids": [chapitre.id]})
    assert r.status_code == 200, r.text
    s = _synthese(client, admin)
    cours = next(c for c in s["cours"] if c["code"] == "FR5-FONCTIONS")
    assert cours["statut"] == "pret" and cours["classes"] == [classe["code"]]
    assert cours["questions"]["validees"] == cours["questions"]["total"] > 0
    cinquieme = next(n for n in s["niveaux"] if n["niveau"] == "5e")
    assert cinquieme["validateurs"] == [prof.nom] and cinquieme["classes_pilotes"] == [classe["code"]]
    assert not any(classe["code"] in a["message"] for a in s["alertes"])
    assert any("Aucun professeur validateur en 6e" in a["message"] for a in s["alertes"])
    # Effectifs seulement : aucun prénom, identifiant ni code d'élève dans la réponse.
    texte = json.dumps(s, ensure_ascii=False)
    assert "Lina" not in texte and "prenom" not in texte


def test_fonctions_sensibles_en_lecture_seule(client, monkeypatch):
    monkeypatch.setattr(settings, "redaction_active", False)
    monkeypatch.setattr(settings, "pdf_francais_ouvert", False)
    s = _synthese(client, connecter_admin(client))
    assert {f["reglage"]: f["active"] for f in s["fonctions"]} == {
        "PKP_REDACTION_ACTIVE": False, "PKP_PDF_FRANCAIS_OUVERT": False,
    }
    # Aucune route d'écriture : la page ne change ni les drapeaux ni les données.
    assert client.post(URL, headers=connecter_admin(client)).status_code == 405
