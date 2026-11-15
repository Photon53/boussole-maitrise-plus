# Issue #93 — Comptes de test en DEV, interdits en production (Claude)
"""Trois environnements : poste local (dev), VM DEV (integration), production. L'intégration a les mêmes contrôles
que la production (configuration, documentation fermée, second facteur) ; seuls les comptes de test l'en
distinguent : autorisés en intégration, refusés en production à la création, à la connexion et au contrôle."""

import importlib

import pytest
from fastapi.testclient import TestClient

from app import admin as cli_admin
from app import production
from app.comptes_de_test import REFUS_PRODUCTION, est_compte_de_test
from app.config import settings
from app.db.seed import CODES_DEMO, MOT_DE_PASSE_DEMO_PUBLIE, DemoInterdite, charger_demo
from tests.conftest import connecter_enseignant
from tests.test_parents import EMAIL as EMAIL_PARENT
from tests.test_parents import creer_parent
from tests.test_production import PROD_VALIDE, config

INTEGRATION = {**PROD_VALIDE, "environnement": "integration"}


@pytest.fixture
def environnement(monkeypatch):
    def choisir(nom: str) -> None:
        monkeypatch.setattr(settings, "environnement", nom)

    return choisir


# --- Configuration ---------------------------------------------------------------------------------------


class TestConfiguration:
    def test_integration_valide_avec_une_configuration_de_production(self):
        c = config(**INTEGRATION)
        assert c.durci and not c.production and c.totp_requis

    @pytest.mark.parametrize(
        ("champ", "valeur"),
        [("secret_key", "trop-courte"), ("database_url", "sqlite:///./pkp.db"), ("cors_origins", ["http://dev.boussole.fr"])],
    )
    def test_integration_refuse_ce_que_la_production_refuse(self, champ, valeur):
        with pytest.raises(ValueError, match="integration invalide"):
            config(**{**INTEGRATION, champ: valeur})

    def test_le_poste_local_reste_souple(self):
        c = config()
        assert not c.durci and not c.totp_requis

    def test_environnement_inconnu_refuse(self):
        with pytest.raises(ValueError):
            config(environnement="recette")


@pytest.mark.parametrize(
    ("email", "attendu"),
    [
        ("demo@pkp.test", True), ("Prof.Essai@Boussole.TEST", True), ("a@x.example", True), ("a@x.invalid", True),
        ("a@localhost", True), ("a@example.com", True), ("a@dev.example.org", True),
        ("prof@lycee.fr", False), ("a@testlycee.fr", False), ("a@contest.fr", False), ("a@myexample.com", False),
    ],
)
def test_reconnaissance_des_comptes_de_test(email, attendu):
    assert est_compte_de_test(email) is attendu


# --- Distinguer l'environnement -------------------------------------------------------------------------


def test_sante_indique_l_environnement_hors_production(client, environnement):
    assert client.get("/health").json() == {"status": "ok", "environnement": "dev"}
    environnement("integration")
    assert client.get("/health").json()["environnement"] == "integration"
    environnement("production")
    assert client.get("/health").json() == {"status": "ok"}


def test_documentation_fermee_en_integration(environnement):
    import app.main as module_main

    environnement("integration")
    try:
        with TestClient(importlib.reload(module_main).app) as c:
            assert c.get("/docs").status_code == 404 and c.get("/openapi.json").status_code == 404
    finally:
        settings.environnement = "dev"
        importlib.reload(module_main)


# --- Comptes de test : autorisés en intégration, sans rien assouplir -------------------------------------


class TestIntegration:
    def test_compte_de_test_se_connecte(self, client, environnement):
        environnement("integration")
        assert connecter_enseignant(client)  # demo@pkp.test

    def test_administrateur_de_test_soumis_au_second_facteur(self, client, environnement):
        environnement("integration")
        r = client.post("/admin/connexion", json={"email": "admin@pkp.test", "mot_de_passe": MOT_DE_PASSE_DEMO_PUBLIE})
        assert r.status_code == 403 and "Second facteur" in r.json()["detail"]

    def test_creation_d_un_compte_de_test(self, session, environnement):
        environnement("integration")
        e = cli_admin.creer_enseignant(session, "prof.essai@boussole.test", "Prof essai", "un-mot-de-passe-long")
        assert e.id

    def test_controle_liste_sans_bloquer(self, client, fabrique, environnement, monkeypatch, capsys):
        import app.db.session as module_session

        environnement("integration")
        monkeypatch.setattr(module_session, "SessionLocale", fabrique)
        monkeypatch.setattr("sys.argv", ["app.production", "verifier"])
        production.main()  # pas de SystemExit
        assert "autorisés hors production" in capsys.readouterr().out


class TestDemoEnIntegration:
    def test_mot_de_passe_publie_ou_absent_refuse(self, session, environnement, monkeypatch):
        environnement("integration")
        for valeur in ("", MOT_DE_PASSE_DEMO_PUBLIE, "court"):
            monkeypatch.setenv("PKP_DEMO_MOT_DE_PASSE", valeur)
            with pytest.raises(DemoInterdite, match="PKP_DEMO_MOT_DE_PASSE"):
                charger_demo(session)

    def test_codes_tires_au_hasard_et_mot_de_passe_choisi(self, session, environnement, monkeypatch):
        environnement("integration")
        monkeypatch.setenv("PKP_DEMO_MOT_DE_PASSE", "mot-de-passe-equipe-dev")
        codes: dict[str, str] = {}
        assert charger_demo(session, codes)
        assert len(codes) == len(CODES_DEMO) and all(i.endswith("-demo") for i in codes)
        assert not set(codes.values()) & set(CODES_DEMO.values())  # aucun code publié dans le dépôt


# --- Production : comptes de test interdits ---------------------------------------------------------------


class TestProduction:
    def test_connexion_d_un_compte_de_test_refusee(self, client, environnement):
        environnement("production")
        r = client.post("/enseignants/connexion", json={"email": "demo@pkp.test", "mot_de_passe": MOT_DE_PASSE_DEMO_PUBLIE})
        assert r.status_code == 403 and r.json()["detail"] == REFUS_PRODUCTION

    def test_mauvais_mot_de_passe_reste_un_401(self, client, environnement):
        # Le refus n'intervient qu'après le mot de passe : il ne révèle pas l'existence d'un compte.
        environnement("production")
        assert client.post("/enseignants/connexion", json={"email": "demo@pkp.test", "mot_de_passe": "faux"}).status_code == 401

    def test_connexion_d_un_parent_de_test_refusee(self, client, environnement):
        provisoire = creer_parent(client, email="parent@famille.test")["mot_de_passe_provisoire"]
        environnement("production")
        r = client.post("/parents/connexion", json={"email": "parent@famille.test", "mot_de_passe": provisoire})
        assert r.status_code == 403 and r.json()["detail"] == REFUS_PRODUCTION

    def test_parent_a_adresse_reelle_accepte(self, client, environnement):
        provisoire = creer_parent(client)["mot_de_passe_provisoire"]  # parent.lina@exemple.fr
        environnement("production")
        assert client.post("/parents/connexion", json={"email": EMAIL_PARENT, "mot_de_passe": provisoire}).status_code == 200

    def test_creation_d_un_compte_de_test_refusee(self, session, environnement):
        environnement("production")
        with pytest.raises(cli_admin.ErreurAdmin, match="refusé en production"):
            cli_admin.creer_enseignant(session, "prof.essai@boussole.test", "Prof essai", "un-mot-de-passe-long")
        assert cli_admin.creer_enseignant(session, "prof@lycee.fr", "Prof", "un-mot-de-passe-long").id

    def test_demo_refusee(self, session, environnement):
        environnement("production")
        with pytest.raises(DemoInterdite):
            charger_demo(session)
