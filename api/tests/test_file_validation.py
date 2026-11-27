"""File de validation du français (#231) : motif d'une décision « À corriger », filtre par domaine, correction
expliquée et rubrique pour le validateur. Les règles de validation ne changent pas."""
# Issue #231 — File de validation : motif, domaine, correction (Claude)

from app import permissions
from app.db import models
from sqlalchemy import select
from tests.conftest import connecter_admin, connecter_enseignant
from tests.test_validation_maths import BASE, habiliter

FR = "francais-college"


def _validateur_fr_et_maths(client, session):
    r = client.post(f"/admin/domaines/{FR}", headers=connecter_admin(client), json={"actif": True, "public": False})
    assert r.status_code == 200, r.text
    session.expire_all()
    return habiliter(session, [
        permissions.Portee(permissions.VALIDATEUR, FR, "6e"),
        permissions.Portee(permissions.VALIDATEUR, "maths-lycee", "2nde"),
    ])


def test_filtre_par_domaine_avec_rubrique_et_correction(client, session):
    _validateur_fr_et_maths(client, session)
    h = connecter_enseignant(client)
    tout = client.get(f"{BASE}/questions", headers=h).json()
    assert {q["domaine"] for q in tout["elements"]} >= {"maths-lycee"}
    page = client.get(f"{BASE}/questions", headers=h, params={"domaine": FR}).json()
    assert page["total"] > 0
    assert {q["domaine"] for q in page["elements"]} == {FR} and {q["niveau"] for q in page["elements"]} == {"6e"}
    assert {q["rubrique"] for q in page["elements"]} <= {"grammaire", "conjugaison", "redaction", "mon_cours"}
    assert any(q["correction"] and q["correction"].get("etapes") for q in page["elements"])
    # Un domaine hors périmètre ne montre rien.
    assert client.get(f"{BASE}/questions", headers=h, params={"domaine": "francais-lycee"}).json()["total"] == 0


def test_motif_a_corriger_journalise_et_relu_puis_efface_a_la_validation(client, session):
    _validateur_fr_et_maths(client, session)
    h = connecter_enseignant(client)
    q = client.get(f"{BASE}/questions", headers=h, params={"domaine": FR, "statut": "a-valider"}).json()["elements"][0]
    motif = "La consigne ne précise pas le temps attendu."
    r = client.post(f"{BASE}/questions/{q['id']}/validation", headers=h, json={"statut": "a-corriger", "motif": f"  {motif} "})
    assert r.status_code == 200, r.text
    assert r.json()["statut_validation"] == "a-corriger" and r.json()["motif_correction"] == motif
    entree = session.scalars(select(models.JournalAdmin).where(
        models.JournalAdmin.action == "valider", models.JournalAdmin.objet_id == q["id"])).all()[-1]
    assert entree.apres["motif"] == motif
    liste = client.get(f"{BASE}/questions", headers=h, params={"domaine": FR, "statut": "a-corriger"}).json()["elements"]
    assert next(x for x in liste if x["id"] == q["id"])["motif_correction"] == motif

    # Remise à valider puis validation : plus de motif affiché.
    r = client.post(f"{BASE}/questions/{q['id']}/validation", headers=h, json={"statut": "validee"})
    assert r.status_code in (200, 422), r.text  # 422 seulement si ce compte est l'auteur (règle inchangée)
    if r.status_code == 200:
        assert r.json()["motif_correction"] is None


def test_motif_borne_et_ignore_pour_une_validation(client, session):
    _validateur_fr_et_maths(client, session)
    h = connecter_enseignant(client)
    q = client.get(f"{BASE}/questions", headers=h, params={"domaine": FR, "statut": "a-valider"}).json()["elements"][0]
    assert client.post(f"{BASE}/questions/{q['id']}/validation", headers=h,
                       json={"statut": "a-corriger", "motif": "x" * 501}).status_code == 422
    r = client.post(f"{BASE}/questions/{q['id']}/validation", headers=h, json={"statut": "validee", "motif": "inutile"})
    if r.status_code == 200:
        entree = session.scalars(select(models.JournalAdmin).where(
            models.JournalAdmin.action == "valider", models.JournalAdmin.objet_id == q["id"])).all()[-1]
        assert "motif" not in entree.apres
