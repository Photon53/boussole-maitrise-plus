"""Données de démonstration. Usage, depuis `api/` : `python -m app.db.seed`

1. Importe le contenu pédagogique de `contenu/` (chapitres, cours, questions).
2. Crée, si absents, un enseignant, des classes, des élèves et un historique de réponses.
Idempotent : relancer ne duplique rien.

Selon PKP_ENVIRONNEMENT (#93) :
- dev (poste local) : mot de passe PKP_DEMO_MOT_DE_PASSE, sinon « demo-pkp-2026 » ; codes élèves fixes (CODES_DEMO) ;
- integration (VM DEV) : PKP_DEMO_MOT_DE_PASSE obligatoire (12 caractères minimum, jamais la valeur publiée) ;
  codes élèves tirés au hasard et affichés une seule fois ; l'administrateur de démo doit configurer son second
  facteur (`python -m app.admin totp --email admin@pkp.test`) comme tout administrateur ;
- production : refusé.

Comptes (adresses en @pkp.test, domaine réservé : comptes de test, voir app/comptes_de_test.py) :
    enseignant     : demo@pkp.test
    administrateur : admin@pkp.test (second facteur obligatoire hors poste local)
    anglais        : anglais@pkp.test

Codes personnels des élèves sur le poste local : voir CODES_DEMO ci-dessous,
par exemple Lina / 2NDE-A-DEMO / PKP222, ou, avec l'identifiant de connexion, lina-demo / PKP222.
"""

import os
from datetime import UTC, datetime, timedelta

from pkp_engine import Niveau, corriger
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import anglais_contenu, contenu, permissions
from app.db import models
from app.db.conversions import question_vers_domaine
from app.progression import chapitres_du_programme
from app.referentiel import Role, parcours_par_defaut
from app.security import generer_code_eleve, generer_identifiant, hacher_code_eleve, hacher_mot_de_passe

EMAIL_DEMO = "demo@pkp.test"
EMAIL_ADMIN_DEMO = "admin@pkp.test"
EMAIL_ANGLAIS_DEMO = "anglais@pkp.test"

# Codes fixes pour pouvoir tester en local ; en vrai, l'enseignant les génère (aléatoires).
CODES_DEMO = {"Lina": "PKP222", "Yanis": "PKP333", "Inès": "PKP444", "Hugo": "PKP555", "Emma": "PKP666"}


def identifiant_demo(prenom: str) -> str:
    """Identifiant de connexion des élèves de démo : « lina-demo », « ines-demo »…"""
    return generer_identifiant(prenom).rsplit("-", 1)[0] + "-demo"

CLASSES = [
    ("2NDE-A-DEMO", Niveau.SECONDE, ["Lina", "Yanis", "Inès"]),
    ("1RE-B-DEMO", Niveau.PREMIERE, ["Hugo"]),
    ("TLE-C-DEMO", Niveau.TERMINALE, ["Emma"]),
]

# (prénom, [(code question, réponse saisie)])
SEANCES = [
    ("Lina", [("2NDE-FRAC-01", "5/6"), ("2NDE-FRAC-02", "1/5"), ("2NDE-DEV-01", "x²+6x+9"),
              ("2NDE-DEV-03", "2x²+7x+4"), ("2NDE-EQ1-01", "5")]),
    ("Yanis", [("2NDE-FRAC-01", "2/5"), ("2NDE-FRAC-01", "5/6")]),
]


class DemoInterdite(RuntimeError):
    """Données de démonstration demandées en production : comptes et codes connus de tous (#116)."""


MOT_DE_PASSE_DEMO_PUBLIE = "demo-pkp-2026"
LONGUEUR_MIN_INTEGRATION = 12


def _mot_de_passe_demo() -> str:
    """Poste local : la valeur publiée ci-dessus. Intégration (VM DEV) : PKP_DEMO_MOT_DE_PASSE obligatoire, choisi
    par l'équipe et jamais versionné (#93) ; les comptes restent soumis aux règles habituelles (TOTP admin)."""
    from app.config import settings

    mot_de_passe = os.environ.get("PKP_DEMO_MOT_DE_PASSE", "")
    if settings.environnement == "dev":
        return mot_de_passe or MOT_DE_PASSE_DEMO_PUBLIE
    if len(mot_de_passe) < LONGUEUR_MIN_INTEGRATION or mot_de_passe == MOT_DE_PASSE_DEMO_PUBLIE:
        raise DemoInterdite(
            f"En intégration, définir PKP_DEMO_MOT_DE_PASSE ({LONGUEUR_MIN_INTEGRATION} caractères minimum, "
            "différent de la valeur publiée dans le dépôt)."
        )
    return mot_de_passe


def charger_demo(session: Session, codes_tires: dict[str, str] | None = None) -> bool:
    """Charge le contenu puis les données de démo. Renvoie False si la démo existait déjà.
    Refusé en production : la démo est un jeu de comptes de test (#116, #93). Hors poste local, les codes des
    élèves sont tirés au hasard et recopiés dans `codes_tires` (affichés une seule fois), au lieu de CODES_DEMO."""
    from app.config import settings

    if settings.production:
        raise DemoInterdite("Données de démonstration refusées en production (PKP_ENVIRONNEMENT=production).")
    mot_de_passe = _mot_de_passe_demo()
    codes = CODES_DEMO if settings.environnement == "dev" else {p: generer_code_eleve() for p in CODES_DEMO}
    contenu.importer(session, contenu.charger())
    anglais_contenu.importer_seances(session)  # soumises à validation : aucun élève ne les voit encore

    # Ajouté à part : une base de démo antérieure à la V2 reçoit aussi son administrateur.
    if not session.scalar(select(models.Enseignant).where(models.Enseignant.email == EMAIL_ADMIN_DEMO)):
        admin = models.Enseignant(
            nom="Administrateur Démo", email=EMAIL_ADMIN_DEMO, role=Role.ADMIN,
            mot_de_passe_hash=hacher_mot_de_passe(mot_de_passe),
        )
        session.add(admin)
        # Comme la migration 0023 pour les administrateurs existants : professeur et validateur de Maths lycée.
        permissions.appliquer(session, admin, [
            permissions.Portee(permissions.PROFESSEUR, permissions.MATHS_LYCEE),
            permissions.Portee(permissions.VALIDATEUR, permissions.MATHS_LYCEE),
        ], None)
        session.commit()

    # Professeur d'anglais seul : n'a accès qu'à l'espace /anglais (ajouté à part, comme l'administrateur).
    if not session.scalar(select(models.Enseignant).where(models.Enseignant.email == EMAIL_ANGLAIS_DEMO)):
        anglais = models.Enseignant(
            nom="Professeur d'anglais Démo", email=EMAIL_ANGLAIS_DEMO, mot_de_passe_hash=hacher_mot_de_passe(mot_de_passe),
        )
        session.add(anglais)
        permissions.appliquer(session, anglais, [
            permissions.Portee(permissions.PROFESSEUR, permissions.ANGLAIS_COLLEGE),
            permissions.Portee(permissions.VALIDATEUR, permissions.ANGLAIS_COLLEGE),
        ], None)
        session.commit()

    if session.scalar(select(models.Enseignant).where(models.Enseignant.email == EMAIL_DEMO)):
        return False

    enseignant = models.Enseignant(
        nom="Enseignant Démo",
        email=EMAIL_DEMO,
        mot_de_passe_hash=hacher_mot_de_passe(mot_de_passe),
    )
    session.add(enseignant)
    permissions.appliquer(session, enseignant, [permissions.Portee(permissions.PROFESSEUR, permissions.MATHS_LYCEE)], None)

    eleves: dict[str, models.Eleve] = {}
    for code, niveau, prenoms in CLASSES:
        classe = models.Classe(code=code, niveau=niveau, parcours=parcours_par_defaut(niveau), enseignant=enseignant)
        session.add(classe)
        classe.chapitres_proposes = chapitres_du_programme(session, classe)
        for prenom in prenoms:
            eleves[prenom] = models.Eleve(
                prenom=prenom, classe=classe, code_hash=hacher_code_eleve(codes[prenom]), identifiant=identifiant_demo(prenom)
            )
            session.add(eleves[prenom])
    session.flush()
    if codes_tires is not None and codes is not CODES_DEMO:
        codes_tires.update({identifiant_demo(p): c for p, c in codes.items()})

    instant = datetime.now(UTC) - timedelta(days=1)
    for prenom, saisies in SEANCES:
        seance = models.Seance(eleve=eleves[prenom], debut=instant)
        session.add(seance)  # avant les requêtes : leur autoflush doit trouver la séance en session
        for code_question, saisie in saisies:
            question = session.scalar(select(models.Question).where(models.Question.code == code_question))
            instant += timedelta(minutes=1)
            seance.reponses.append(
                models.Reponse(
                    question=question,
                    reponse_donnee=saisie,
                    correcte=corriger(question_vers_domaine(question), saisie),
                    duree_s=45.0,
                    repondu_le=instant,
                )
            )
        seance.fin = instant

    session.commit()
    return True


def main() -> None:
    from app.db.session import SessionLocale

    with SessionLocale() as session:
        codes: dict[str, str] = {}
        try:
            print("Données de démo chargées." if charger_demo(session, codes) else "Contenu à jour, démo déjà présente.")
        except DemoInterdite as exc:
            raise SystemExit(str(exc)) from exc
    if codes:
        print("Codes des élèves de test (affichés une seule fois, à conserver dans le gestionnaire de l'équipe) :")
        for identifiant, code in codes.items():
            print(f"  {identifiant} : {code}")


if __name__ == "__main__":
    main()
