"""Cours interactifs de français (#177) visibles dans l'espace Français et validables par un validateur de français
dans la page « Validation » de l'espace professeur (correctif du 27/11, #217)."""
# Issue #217 — Cours de français visibles et validables par les validateurs de français (Claude)

import pytest
from sqlalchemy import select

from app.db import models
from tests.conftest import connecter_admin, connecter_enseignant
from tests.test_lot_a_habilitations import MDP, _creer

DOMAINE = "francais-college"
BASE = "/enseignants/validation"


@pytest.fixture
def actif(client):
    admin = connecter_admin(client)
    r = client.post(f"/admin/domaines/{DOMAINE}", headers=admin, json={"actif": True, "public": False})
    assert r.status_code == 200, r.text
    return admin


def _question(session, prefixe: str) -> models.Question:
    return session.scalar(select(models.Question).where(models.Question.code.like(f"{prefixe}%"),
                                                        models.Question.archivee.is_(False)))


class TestOngletCours:
    def test_professeur_3e_voit_les_cours_de_3e_seulement(self, client, actif):
        _, prof = _creer(client, actif, "fr3c@pkp.test", [{"role": "professeur", "domaine": DOMAINE, "niveau": "3e"}])
        r = client.get("/francais/chapitres", headers=prof)
        assert r.status_code == 200 and r.headers["cache-control"] == "private, no-store"
        lignes = r.json()
        assert lignes and {c["niveau"] for c in lignes} == {"3e"}
        assert {c["rubrique"] for c in lignes} <= {"grammaire", "conjugaison", "redaction", "mon_cours"}
        ch = lignes[0]
        assert ch["nb_questions"] == ch["nb_validees"] + ch["nb_a_valider"] + ch["nb_a_corriger"] and ch["peut_valider"] is False
        detail = client.get(f"/francais/chapitres/{ch['id']}", headers=prof).json()
        assert detail["competences"] and "questions" in detail["competences"][0]

    def test_administrateur_voit_tous_les_niveaux(self, client, actif):
        admin = connecter_enseignant(client, email="admin@pkp.test")
        niveaux = {c["niveau"] for c in client.get("/francais/chapitres", headers=admin).json()}
        assert {"6e", "5e", "4e", "3e"} <= niveaux

    def test_hors_perimetre_et_jetons_refuses(self, client, actif):
        _, prof6 = _creer(client, actif, "fr6c@pkp.test", [{"role": "professeur", "domaine": DOMAINE, "niveau": "6e"}])
        admin = connecter_enseignant(client, email="admin@pkp.test")
        fr3 = next(c for c in client.get("/francais/chapitres", headers=admin).json() if c["niveau"] == "3e")
        assert client.get(f"/francais/chapitres/{fr3['id']}", headers=prof6).status_code == 404
        assert client.get("/francais/chapitres", headers=connecter_enseignant(client)).status_code == 403  # maths seul
        assert client.get("/francais/chapitres", headers={}).status_code == 401


class TestValidationParUnValidateurDeFrancais:
    def test_perimetre_questions_et_decision(self, client, session, actif):
        _, val = _creer(client, actif, "valfr3@pkp.test", [{"role": "validateur", "domaine": DOMAINE, "niveau": "3e"}])
        assert client.get(f"{BASE}/perimetre", headers=val).json() == [
            {"domaine": DOMAINE, "libelle": "Français collège", "niveau": "3e"}]
        arbre = client.get(f"{BASE}/contenu", headers=val).json()
        assert arbre and all(c["code"].startswith("FR3-") for c in arbre)
        page = client.get(f"{BASE}/questions", headers=val, params={"niveau": "3e"}).json()
        assert page["total"] > 0 and all(q["code"].startswith("FR3-") for q in page["elements"])
        q3, q6 = _question(session, "FR3-ACCORDS"), _question(session, "FR6-")
        r = client.post(f"{BASE}/questions/{q3.id}/validation", headers=val, json={"statut": "validee"})
        assert r.status_code == 200, r.text
        assert client.post(f"{BASE}/questions/{q6.id}/validation", headers=val, json={"statut": "validee"}).status_code == 404
        maths = session.scalar(select(models.Question).join(models.Competence).join(models.Chapitre)
                               .where(models.Chapitre.domaine_code == "maths-lycee"))
        assert client.post(f"{BASE}/questions/{maths.id}/validation", headers=val, json={"statut": "validee"}).status_code == 404
        # Le statut validé se voit dans l'onglet « Cours » de l'espace Français.
        ch = next(c for c in client.get("/francais/chapitres", headers=val).json() if c["code"] == "FR3-ACCORDS")
        assert ch["nb_validees"] == 1 and ch["peut_valider"] is True

    def test_la_connexion_annonce_la_page_validation(self, client, actif):
        _creer(client, actif, "valfr@pkp.test", [{"role": "validateur", "domaine": DOMAINE}])
        r = client.post("/enseignants/connexion", json={"email": "valfr@pkp.test", "mot_de_passe": MDP})
        assert r.status_code == 200 and r.json()["validateur_maths"] is True  # lien « Validation » affiché

    def test_un_validateur_de_maths_ne_voit_pas_le_francais(self, client, actif):
        _, val = _creer(client, actif, "valm@pkp.test", [{"role": "validateur", "domaine": "maths-lycee"}])
        assert all(not c["code"].startswith("FR") for c in client.get(f"{BASE}/contenu", headers=val).json())
