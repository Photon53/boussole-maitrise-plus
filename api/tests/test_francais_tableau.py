"""Tableau de bord d'une classe de français pour son professeur (#231) : lecture seule, sans texte d'élève."""
# Issue #231 — Tableau de bord du professeur de français (Claude)

import json

from sqlalchemy import select

from app import permissions
from app.db import models
from app.referentiel import StatutValidation
from tests.conftest import connecter_enseignant
from tests.test_classes_pilotes import _classe_pilote, _preparer, _repondre


def _tableau(client, h, classe_id) -> dict:
    r = client.get(f"/francais/classes/{classe_id}/tableau", headers=h)
    assert r.status_code == 200, r.text
    assert r.headers["cache-control"] == "private, no-store"
    return r.json()


def test_etat_des_eleves_par_cours_et_presentation_par_defaut(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    classe, lina = _classe_pilote(client, ctx, "Lina")
    seance = client.post("/seances", headers=lina).json()["id"]
    _repondre(client, lina, seance)
    prof = connecter_enseignant(client)

    t = _tableau(client, prof, classe)
    assert t["presentation"] == {"mode": "guide", "origine": "defaut"}  # FR-01 de #111
    assert t["classe"]["pilote"] and t["classe"]["acces_eleves"]
    assert [c["cle"] for c in t["cours"]] == [f"chapitre-{ctx['chapitre']}"]
    assert t["cours"][0]["rubrique"] == "conjugaison"
    (eleve,) = t["eleves"]
    etat = eleve["cours"][f"chapitre-{ctx['chapitre']}"]
    assert etat["reponses"] == 1 and etat["etat"] in ("en_cours", "maitrise")
    assert eleve["actif_7j"] and eleve["derniere_activite"]
    assert t["indicateurs"]["eleves"] == 1 and t["indicateurs"]["actifs_7j"] == 1
    assert t["redaction_ouverte"] is False


def test_reserve_au_professeur_de_la_classe(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    classe, lina = _classe_pilote(client, ctx, "Lina")
    assert client.get(f"/francais/classes/{classe}/tableau", headers=lina).status_code == 401
    assert client.get(f"/francais/classes/{classe}/tableau").status_code == 401
    # Un autre professeur habilité en français ne voit pas la classe : même réponse qu'une classe inexistante.
    autre = session.scalar(select(models.Enseignant).where(models.Enseignant.email == "anglais@pkp.test"))
    permissions.appliquer(session, autre, [*permissions.portees(autre), permissions.Portee(permissions.PROFESSEUR, "francais-college")], None)
    session.commit()
    h = connecter_enseignant(client, "anglais@pkp.test")
    assert client.get(f"/francais/classes/{classe}/tableau", headers=h).status_code == 404


def test_questions_a_valider_dans_le_perimetre_sauf_les_siennes(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    classe, _ = _classe_pilote(client, ctx, "Lina")
    prof = session.get(models.Enseignant, ctx["prof_id"])
    # Le chapitre « Les fonctions » du dépôt (#177), démasqué : ses 9 questions sont à valider.
    chapitre = session.scalar(select(models.Chapitre).where(models.Chapitre.code == "FR5-FONCTIONS"))
    chapitre.masque = False
    questions = [q for c in chapitre.competences for q in c.questions if not q.archivee]
    for q in questions:
        q.statut_validation = StatutValidation.A_VALIDER
    questions[0].auteur = prof.nom  # le professeur ne valide pas ce qu'il a écrit (V2-D15)
    session.commit()
    h = connecter_enseignant(client)
    assert _tableau(client, h, classe)["a_valider"] == []  # pas validateur

    permissions.appliquer(session, prof, [*permissions.portees(prof), permissions.Portee(permissions.VALIDATEUR, "francais-college", "5e")], None)
    session.commit()
    (ligne,) = _tableau(client, h, classe)["a_valider"]
    assert ligne["chapitre_id"] == chapitre.id and ligne["questions"] == len(questions) - 1


def test_aucun_texte_d_eleve_ni_corrige(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    classe, lina = _classe_pilote(client, ctx, "Lina")
    seance = client.post("/seances", headers=lina).json()["id"]
    _repondre(client, lina, seance)
    texte = json.dumps(_tableau(client, connecter_enseignant(client), classe), ensure_ascii=False)
    assert "finissent" not in texte  # ni la réponse donnée, ni la solution
    assert "reponse_donnee" not in texte and "solution" not in texte
