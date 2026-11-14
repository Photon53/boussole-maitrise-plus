# Issue #116 — Verrouillage du mode production (Claude)
"""En production : ni démonstration, ni documentation interactive, ni origine non chiffrée ; la base est contrôlée
avant la mise en service (`python -m app.production verifier`)."""

import importlib

import pytest
from fastapi.testclient import TestClient

from app import production
from app.config import settings
from app.db.seed import DemoInterdite, charger_demo
from tests.test_production import PROD_VALIDE, config


@pytest.fixture
def en_production(monkeypatch):
    monkeypatch.setattr(settings, "environnement", "production")


def test_origine_non_chiffree_refusee():
    with pytest.raises(ValueError, match="https://"):
        config(**{**PROD_VALIDE, "cors_origins": ["http://maths.lycee.fr"]})


def test_la_demo_ne_se_charge_pas_en_production(en_production, session):
    with pytest.raises(DemoInterdite):
        charger_demo(session)
    assert production.problemes(session) == []  # rien n'a été écrit


def test_base_vierge_prete_pour_la_production(session):
    assert production.problemes(session) == []


def test_comptes_de_demonstration_detectes(client, fabrique):
    with fabrique() as s:
        trouves = production.problemes(s)
    assert len(trouves) == len(production.EMAILS_DEMO)
    assert all("démonstration" in t for t in trouves)


def test_commande_verifier_echoue_sur_une_base_de_demo(client, fabrique, monkeypatch, capsys):
    import app.db.session as module_session

    monkeypatch.setattr(module_session, "SessionLocale", fabrique)
    monkeypatch.setattr("sys.argv", ["app.production", "verifier"])
    with pytest.raises(SystemExit) as fin:
        production.main()
    assert fin.value.code == 1 and "REFUS" in capsys.readouterr().err


def test_documentation_interactive_fermee_en_production(en_production):
    import app.main as module_main

    try:
        prod = importlib.reload(module_main).app
        with TestClient(prod) as c:
            for chemin in ("/docs", "/openapi.json", "/redoc"):
                assert c.get(chemin).status_code == 404, chemin
            assert c.get("/health").status_code == 200
    finally:
        settings.environnement = "dev"
        importlib.reload(module_main)
