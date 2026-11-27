"""Bilan Français d'un enfant pour son parent (#231) : un bilan, jamais de contenu ni de texte de l'enfant."""
# Issue #231 — Espace parent : bilan Français (Claude)

import json

from sqlalchemy import select

from app.db import models
from tests.conftest import entete
from tests.test_francais import CODE, circuit, prepare  # noqa: F401 (fixtures)
from tests.test_francais_accueil import _ouvrir_dossier

MDP = "un-mot-de-passe-solide"


def _parent_de(client, admin, eleve_id: int, email: str) -> dict:
    r = client.post("/admin/parents", headers=admin, json={"eleve_id": eleve_id, "email": email})
    assert r.status_code == 201, r.text
    provisoire = r.json()["mot_de_passe_provisoire"]
    jeton = client.post("/parents/connexion", json={"email": email, "mot_de_passe": provisoire}).json()["jeton"]
    r = client.post("/parents/mot-de-passe", headers=entete(jeton), json={"actuel": provisoire, "nouveau": MDP})
    assert r.status_code == 200, r.text
    return entete(r.json()["jeton"])


def _eleve_id(session, classe_id: int) -> int:
    return session.scalar(select(models.Eleve.id).where(models.Eleve.classe_id == classe_id))


def test_bilan_des_cours_ouverts_sans_contenu(client, session, circuit):  # noqa: F811
    _ouvrir_dossier(client, circuit)
    classe_id, lina = circuit["pilote"]
    eleve_id = _eleve_id(session, classe_id)
    # L'élève répond au quiz : le parent voit un score, jamais la question ni l'explication.
    nb = len(client.get(f"/francais/eleve/dossiers/{CODE}", headers=lina).json()["eleve"]["quiz"])
    r = client.post(f"/francais/eleve/dossiers/{CODE}/corriger", headers=lina, json={"reponses": [0] * nb})
    assert r.status_code == 200, r.text
    parent = _parent_de(client, circuit["admin"], eleve_id, "parent.lina@exemple.fr")

    r = client.get(f"/parents/enfants/{eleve_id}/francais", headers=parent)
    assert r.status_code == 200, r.text
    assert r.headers["cache-control"] == "private, no-store"
    b = r.json()
    assert b["acces"] is True and b["eleve"]["niveau"] == "3e"
    dossier = next(c for c in b["cours"] if c["type"] == "dossier")
    assert dossier["rubrique"] == "lire" and dossier["total"]
    assert set(dossier) == {"titre", "type", "rubrique", "etat", "etape", "score", "total", "derniere_activite"}
    assert b["indicateurs"]["cours"] == len(b["cours"])
    assert b["retours"] == {"remis": 0, "relus": 0}
    texte = json.dumps(b, ensure_ascii=False)
    for interdit in ("question", "choix", "explication", "solution", "corrige", "consigne", "texte"):
        assert f'"{interdit}' not in texte, interdit

    # Le résumé de l'enfant indique la matière, pour que l'écran choisisse le bon bilan.
    [resume] = client.get("/parents/enfants", headers=parent).json()
    assert resume["matiere"] == "francais"


def test_reserve_aux_parents_de_l_enfant(client, session, circuit):  # noqa: F811
    classe_id, _ = circuit["pilote"]
    autre_classe, _ = circuit["hors_pilote"]
    _parent_de(client, circuit["admin"], _eleve_id(session, autre_classe), "autre.parent@exemple.fr")
    autre = client.post("/parents/connexion", json={"email": "autre.parent@exemple.fr", "mot_de_passe": MDP}).json()
    r = client.get(f"/parents/enfants/{_eleve_id(session, classe_id)}/francais", headers=entete(autre["jeton"]))
    assert r.status_code == 404
    assert client.get(f"/parents/enfants/{_eleve_id(session, classe_id)}/francais").status_code == 401


def test_classe_sans_acces_aucun_cours(client, session, circuit):  # noqa: F811
    _ouvrir_dossier(client, circuit)
    classe_id, _ = circuit["hors_pilote"]
    eleve_id = _eleve_id(session, classe_id)
    parent = _parent_de(client, circuit["admin"], eleve_id, "parent.noe@exemple.fr")
    b = client.get(f"/parents/enfants/{eleve_id}/francais", headers=parent).json()
    assert b["acces"] is False and b["cours"] == [] and b["a_revoir"] == []


def test_classe_de_maths_refusee(client):
    from tests.test_parents import connecter_parent

    parent = connecter_parent(client)
    [enfant] = client.get("/parents/enfants", headers=parent).json()
    assert enfant["matiere"] == "maths"
    assert client.get(f"/parents/enfants/{enfant['id']}/francais", headers=parent).status_code == 404
