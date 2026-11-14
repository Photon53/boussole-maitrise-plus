"""Contrôles d'une base avant la mise en service en production (#116).

Usage, depuis `api/` : `python -m app.production verifier`
Code de sortie 1 si un problème est trouvé : l'étape de préparation échoue et l'API ne démarre pas.
Lecture seule : rien n'est modifié ni supprimé.
"""
# Issue #116 — Verrouillage du mode production (Claude)

import argparse
import sys

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import models
from app.db.seed import EMAIL_ADMIN_DEMO, EMAIL_ANGLAIS_DEMO, EMAIL_DEMO

EMAILS_DEMO = (EMAIL_DEMO, EMAIL_ADMIN_DEMO, EMAIL_ANGLAIS_DEMO)


def problemes(session: Session) -> list[str]:
    """Comptes de la démonstration présents : leurs mots de passe et les codes de leurs élèves sont publics."""
    presents = sorted(session.scalars(select(models.Enseignant.email).where(models.Enseignant.email.in_(EMAILS_DEMO))))
    return [
        f"Compte de démonstration présent : {email} (mot de passe et codes élèves publiés dans app/db/seed.py). "
        "Supprimer la démonstration ou utiliser une base de production vierge."
        for email in presents
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Contrôles de la base avant la mise en service en production")
    parser.add_argument("commande", choices=["verifier"])
    parser.parse_args()
    from app.db.session import SessionLocale

    with SessionLocale() as session:
        trouves = problemes(session)
    for probleme in trouves:
        print(f"REFUS : {probleme}", file=sys.stderr)
    if trouves:
        sys.exit(1)
    print("Base prête pour la production : aucun compte de démonstration.")


if __name__ == "__main__":
    main()
