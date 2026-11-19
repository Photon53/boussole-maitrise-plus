"""Rubriques des chapitres de français (issue #177) : conjugaison, grammaire, redaction, mon_cours ; obligatoires en
français, interdites en maths, filtrables sur tous les niveaux à la fois."""
# Issue #177 — Rubriques de l'espace Français (Claude)

import pytest
from sqlalchemy import select

from app.contenu import charger, importer
from app.db import models
from app.referentiel import RubriqueFrancais
from tests.conftest import connecter_admin, connecter_enseignant
from tests.test_classes_pilotes import _classe_pilote, _preparer
from tests.test_contenu import ecrire, erreurs


def _chapitre_fr(code: str, niveau: str, rubrique: str | None, ordre: int = 2) -> str:
    champ = f"rubrique: {rubrique}, " if rubrique else ""
    return f"""
chapitre: {{code: {code}, matiere: francais, {champ}niveau: {niveau}, parcours: tronc-commun, ordre: {ordre}, titre: Chapitre {code}}}
competences:
  - code: {code}-C
    libelle: Compétence {code}
    questions:
      - {{code: {code}-C-01, difficulte: 1, type: qcm, enonce: "Choisir. A) un B) deux", solution: A}}
"""


def test_rubrique_obligatoire_en_francais_et_interdite_en_maths(tmp_path):
    ecrire(tmp_path, _chapitre_fr("FR6-SANS", "6e", None), "francais/6e/tronc-commun/02-sans.yaml")
    assert "`rubrique` obligatoire pour un chapitre de français" in erreurs(tmp_path)

    autre = tmp_path / "inconnue"
    ecrire(autre, _chapitre_fr("FR6-X", "6e", "lecture"), "francais/6e/tronc-commun/02-x.yaml")
    assert "rubrique" in erreurs(autre)

    maths = tmp_path / "maths"
    ecrire(maths, """
chapitre: {code: M2-RUB, rubrique: grammaire, niveau: 2nde, parcours: tronc-commun, ordre: 7, titre: Test}
competences:
  - code: M2-RUB-C
    libelle: Test
    questions:
      - {code: M2-RUB-01, difficulte: 1, type: numerique, enonce: "1+1 ?", solution: "2"}
""")
    assert "`rubrique` ne concerne que les chapitres de français" in erreurs(maths)


def test_import_puis_changement_de_rubrique(session, tmp_path):
    ecrire(tmp_path, _chapitre_fr("FR6-RUB", "6e", "conjugaison"), "francais/6e/tronc-commun/02-rub.yaml")
    importer(session, charger(tmp_path), archiver_absentes=False)
    session.commit()
    chapitre = session.scalar(select(models.Chapitre).where(models.Chapitre.code == "FR6-RUB"))
    assert chapitre.rubrique is RubriqueFrancais.CONJUGAISON
    ecrire(tmp_path, _chapitre_fr("FR6-RUB", "6e", "grammaire"), "francais/6e/tronc-commun/02-rub.yaml")
    rapport = importer(session, charger(tmp_path), archiver_absentes=False)
    session.commit()
    session.refresh(chapitre)
    assert chapitre.rubrique is RubriqueFrancais.GRAMMAIRE and rapport.modifies["chapitres"] == 1


def test_filtre_par_rubrique_sur_tous_les_niveaux(client, session, tmp_path):
    """Un adulte consulte la conjugaison de la 6e à la 3e sans changer de niveau ; les maths ne sont pas mêlées."""
    for code, niveau, rubrique, chemin in (
        ("FR6-CONJ", "6e", "conjugaison", "francais/6e/tronc-commun/02-conj.yaml"),
        ("FR3-CONJ", "3e", "conjugaison", "francais/3e/tronc-commun/02-conj.yaml"),
        ("FR6-GRAM", "6e", "grammaire", "francais/6e/tronc-commun/03-gram.yaml"),
    ):
        ecrire(tmp_path, _chapitre_fr(code, niveau, rubrique, ordre=3 if code.endswith("GRAM") else 2), chemin)
    importer(session, charger(tmp_path), archiver_absentes=False)
    session.commit()
    for h in (connecter_enseignant(client), connecter_admin(client)):
        conjugaison = client.get("/pkp-math/catalogue?rubrique=conjugaison", headers=h).json()
        assert {c["code"] for c in conjugaison} == {"FR6-CONJ", "FR3-CONJ"}
        assert all(c["rubrique"] == "conjugaison" for c in conjugaison)
        tout = client.get("/pkp-math/catalogue", headers=h).json()
        assert {c["rubrique"] for c in tout} == {None, "conjugaison", "grammaire"}
        doc = client.get(f"/pkp-math/chapitres/{conjugaison[0]['id']}", headers=h).json()
        assert doc["rubrique"] == "conjugaison"
        assert client.get("/pkp-math/catalogue?rubrique=lecture", headers=h).status_code == 422


def test_rubrique_visible_par_l_eleve_et_le_professeur(client, pilote_rubrique):
    h, classe = pilote_rubrique
    assert [c["rubrique"] for c in client.get("/eleves/moi/chapitres", headers=h).json()] == ["conjugaison"]
    assert [c["rubrique"] for c in client.get("/cours", headers=h).json()] == ["conjugaison"]
    programme = client.get(f"/enseignants/classes/{classe}/chapitres", headers=connecter_enseignant(client)).json()
    assert [c["rubrique"] for c in programme] == ["conjugaison"]



@pytest.fixture
def pilote_rubrique(client, session, tmp_path):
    ctx = _preparer(client, session, tmp_path)
    classe, h = _classe_pilote(client, ctx, "Lina")
    return h, classe
