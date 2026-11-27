"""Atelier de rédaction de l'écran de cours (#231) : la consigne du sujet, même quand la rédaction en ligne est
fermée, sans jamais lire ni enregistrer de texte d'élève, ni montrer le guide du professeur."""
# Issue #231 — Atelier de rédaction : consigne du sujet (Claude)

import json

import pytest
from app.config import settings
from app.contenu import charger, importer
from app.db import models
from sqlalchemy import select
from tests.test_classes_pilotes import _classe_pilote, _preparer
from tests.test_contenu import ecrire
from tests.test_redactions import SUJET_REDACTION


@pytest.fixture
def atelier(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    ecrire(tmp_path, SUJET_REDACTION, "francais/5e/tronc-commun/02-raconter.yaml")
    importer(session, charger(tmp_path), archiver_absentes=False)
    session.commit()
    ctx["classe"], ctx["lina"] = _classe_pilote(client, ctx, "Lina")
    ctx["autre"], ctx["noe"] = _classe_pilote(client, ctx, "Noé")
    assert client.delete(f"/admin/classes-pilotes/{ctx['autre']}", headers=ctx["admin"]).status_code == 204
    q = session.scalar(select(models.Question).where(models.Question.code == "FR5-RED-C-01"))
    ctx["sujet"], ctx["competence"] = q.id, q.competence_id
    return ctx


def test_consigne_servie_quand_la_redaction_est_fermee(client, atelier):
    assert settings.redaction_active is False
    r = client.get(f"/francais/eleve/redaction/{atelier['competence']}", headers=atelier["lina"])
    assert r.status_code == 200, r.text
    assert r.headers["cache-control"] == "private, no-store"
    corps = r.json()
    assert corps["ouverte"] is False
    assert corps["sujets"] == [{"question_id": atelier["sujet"], "enonce": corps["sujets"][0]["enonce"]}]
    assert corps["sujets"][0]["enonce"].startswith("Raconte en quinze lignes")
    # Ni solution, ni guide du professeur (ARCH-4) ; la rédaction en ligne reste fermée (RGPD-2).
    texte = json.dumps(corps, ensure_ascii=False)
    assert "Récit au passé" not in texte and "Vérifier le temps" not in texte
    assert client.get("/eleves/moi/redactions", headers=atelier["lina"]).status_code == 403


def test_indique_l_ouverture(client, atelier, monkeypatch):
    monkeypatch.setattr(settings, "redaction_active", True)
    corps = client.get(f"/francais/eleve/redaction/{atelier['competence']}", headers=atelier["lina"]).json()
    assert corps["ouverte"] is True and len(corps["sujets"]) == 1


def test_rien_sans_acces_ni_pour_une_autre_competence(client, atelier):
    # Classe révoquée (SEC-D6) : aucun sujet.
    r = client.get(f"/francais/eleve/redaction/{atelier['competence']}", headers=atelier["noe"])
    assert r.status_code == 200 and r.json()["sujets"] == []
    # Compétence sans sujet de rédaction.
    assert client.get("/francais/eleve/redaction/999999", headers=atelier["lina"]).json()["sujets"] == []
    assert client.get(f"/francais/eleve/redaction/{atelier['competence']}").status_code == 401
