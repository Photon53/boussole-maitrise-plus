# Issue #114 — Compte parent hors de portée d'un professeur (Claude)
"""Un professeur ne prend pas la main sur un compte parent qui ne relève pas de lui (#114) : scénario de l'audit
global de develop (C-1), rejoué en non-régression."""

import pytest
from sqlalchemy import select

from app.db import models
from app.security import hacher_mot_de_passe
from tests.conftest import connecter_admin, connecter_enseignant
from tests.test_parents import EMAIL, NOUVEAU_MDP, connecter_parent

LINA = 1  # 2NDE-A-DEMO, professeur de démo


@pytest.fixture
def malveillant(client, fabrique):
    """Un autre professeur de maths, avec une classe de 2nde et un élève à lui."""
    with fabrique() as s:
        prof = models.Enseignant(nom="Autre", email="autre@pkp.test", mot_de_passe_hash=hacher_mot_de_passe("autre-mdp"))
        s.add(prof)
        s.commit()
    h = connecter_enseignant(client, "autre@pkp.test", "autre-mdp")
    classe = client.post("/enseignants/classes", headers=h, json={"niveau": "2nde", "parcours": "excellence"}).json()
    client.post(f"/enseignants/classes/{classe['id']}/eleves", headers=h, json={"prenoms": ["Leurre"]})
    eleve = client.get(f"/enseignants/classes/{classe['id']}/eleves", headers=h).json()[0]
    return {"h": h, "classe": classe, "eleve_id": eleve["id"]}


def _famille(client, email="famille@x.test", niveau="2nde") -> dict:
    r = client.post("/admin/familles", headers=connecter_admin(client),
                    json={"email": email, "enfants": [{"prenom": "Zélie", "niveau": niveau}]})
    assert r.status_code == 201, r.text
    return r.json()


# --- #114 : compte parent ---------------------------------------------------------------------------------


class TestReinitialisationParent:
    def test_rattacher_puis_reinitialiser_le_parent_d_un_autre_eleve_refuse(self, client, malveillant):
        connecter_parent(client)  # parent de Lina, mot de passe choisi
        r = client.post(f"/enseignants/eleves/{malveillant['eleve_id']}/parents", headers=malveillant["h"], json={"email": EMAIL})
        parent_id = r.json()["parent"]["id"]
        r = client.post(f"/enseignants/parents/{parent_id}/mot-de-passe", headers=malveillant["h"])
        assert r.status_code == 403 and "administrateur" in r.json()["detail"]
        # Le mot de passe du parent n'a pas changé.
        assert client.post("/parents/connexion", json={"email": EMAIL, "mot_de_passe": NOUVEAU_MDP}).status_code == 200

    def test_le_professeur_de_tous_les_enfants_reinitialise_toujours(self, client):
        parent_id = client.post(f"/enseignants/eleves/{LINA}/parents", headers=connecter_enseignant(client),
                                json={"email": EMAIL}).json()["parent"]["id"]
        r = client.post(f"/enseignants/parents/{parent_id}/mot-de-passe", headers=connecter_enseignant(client))
        assert r.status_code == 200 and r.json()["mot_de_passe_provisoire"]

    def test_famille_dont_un_enfant_n_est_inscrit_nulle_part_refusee(self, client, malveillant, session):
        _famille(client)
        parent_id = client.post(f"/enseignants/eleves/{malveillant['eleve_id']}/parents", headers=malveillant["h"],
                                json={"email": "famille@x.test"}).json()["parent"]["id"]
        assert client.post(f"/enseignants/parents/{parent_id}/mot-de-passe", headers=malveillant["h"]).status_code == 403

    def test_famille_inscrite_seulement_chez_ce_professeur_acceptee(self, client, session):
        f = _famille(client)
        prof = connecter_enseignant(client)
        assert client.post("/enseignants/classes/1/enfants", headers=prof, json={"enfant_ids": [f["cartes"][0]["id"]]}).json()["ajoutes"]
        zelie = session.scalar(select(models.Eleve.id).where(models.Eleve.enfant_id == f["cartes"][0]["id"]))
        r = client.post(f"/enseignants/eleves/{zelie}/parents", headers=prof, json={"email": "famille@x.test"})
        parent_id = r.json()["parent"]["id"]
        assert client.post(f"/enseignants/parents/{parent_id}/mot-de-passe", headers=prof).status_code == 200
