"""Accueil Français de l'élève (#231) et mentions internes retirées des dossiers lus par l'élève (constat N2)."""
# Issue #231 — Accueil Français de l'élève (Claude)

import json

from tests.test_francais import CODE, circuit, prepare  # noqa: F401 (fixtures)


def _ouvrir_dossier(client, circuit):  # noqa: F811
    assert client.post(f"/francais/validation/{CODE}/valider", headers=circuit["admin"]).status_code == 200
    classe_id, _ = circuit["pilote"]
    r = client.put(f"/francais/dossiers/{CODE}/classes/{classe_id}", headers=circuit["prof"])
    assert r.status_code == 200, r.text


def _accueil(client, h) -> dict:
    r = client.get("/francais/eleve/accueil", headers=h)
    assert r.status_code == 200, r.text
    assert r.headers["cache-control"] == "private, no-store"
    return r.json()


def test_chapitres_et_dossiers_ensemble_avec_rubrique_etat_et_etape(client, circuit):  # noqa: F811
    _ouvrir_dossier(client, circuit)
    _, lina = circuit["pilote"]
    a = _accueil(client, lina)
    assert a["acces"] is True and a["eleve"]["niveau"] == "3e"
    assert a["presentation"] == {"mode": "guide", "origine": "defaut"}
    assert len(a["etapes"]) == 7 and a["etapes"][0] == "Découvrir" and a["etapes"][-1] == "Consolider"
    dossier = next(c for c in a["cours"] if c["type"] == "dossier")
    assert (dossier["code"], dossier["rubrique"], dossier["etat"], dossier["etape"]) == (CODE, "lire", "pas_commence", 1)
    chapitres = [c for c in a["cours"] if c["type"] == "chapitre"]
    assert chapitres and all(c["rubrique"] in ("grammaire", "conjugaison", "redaction") for c in chapitres)
    assert a["rubriques"]["lire"] == 1
    # Rien n'est commencé : la reprise propose le premier cours à commencer.
    assert a["reprise"] == a["cours"][0]["cle"]
    assert a["redaction_ouverte"] is False


def test_classe_sans_acces_ne_voit_aucun_cours(client, circuit):  # noqa: F811
    _ouvrir_dossier(client, circuit)
    _, noe = circuit["hors_pilote"]
    a = _accueil(client, noe)
    assert a["acces"] is False and a["cours"] == [] and a["reprise"] is None


def test_aucun_corrige_dans_l_accueil(client, circuit):  # noqa: F811
    _ouvrir_dossier(client, circuit)
    texte = json.dumps(_accueil(client, circuit["pilote"][1]), ensure_ascii=False)
    assert "solution" not in texte and "corrige" not in texte and "explication" not in texte


def test_mentions_internes_du_dossier_retirees_pour_l_eleve(client, circuit):  # noqa: F811
    """Constat N2 : « Issue #55 — rédaction originale par Codex » et « Brouillon à relire » ne sont plus montrés à
    l'élève ; l'aperçu des adultes garde la présentation."""
    _ouvrir_dossier(client, circuit)
    _, lina = circuit["pilote"]
    r = client.get(f"/francais/eleve/dossiers/{CODE}", headers=lina)
    assert r.status_code == 200, r.text
    assert r.json()["eleve"]["presentation"] == []
    texte = json.dumps(r.json(), ensure_ascii=False)
    assert "Codex" not in texte and "Brouillon à relire" not in texte
    adulte = client.get(f"/francais/dossiers/{CODE}/eleve", headers=circuit["prof"]).json()
    assert adulte["eleve"]["presentation"]
