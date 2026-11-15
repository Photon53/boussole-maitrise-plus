"""Contrôles d'une base avant la mise en service (#116, #93).

Usage, depuis `api/` : `python -m app.production verifier`
En production, code de sortie 1 si un compte de test ou de démonstration est présent (adresse dans un domaine
réservé, voir app/comptes_de_test.py) : l'étape de préparation échoue et l'API ne démarre pas.
Hors production (intégration, poste local), les mêmes comptes sont seulement listés : ils y sont autorisés.
Lecture seule : rien n'est modifié ni supprimé.
"""
# Issue #116 — Verrouillage du mode production (Claude) ; #93 — comptes de test en DEV (Claude)

import argparse
import sys

from sqlalchemy import select
from sqlalchemy.orm import Session

from app import comptes_de_test
from app.config import settings
from app.db import models


def problemes(session: Session) -> list[str]:
    """Comptes de test présents (enseignants, administrateurs, parents) : la démonstration et les comptes de
    recette ont des mots de passe et des codes élèves connus d'une équipe, pas de leur titulaire."""
    adresses = [("Compte", e) for e in session.scalars(select(models.Enseignant.email))]
    adresses += [("Compte parent", e) for e in session.scalars(select(models.Parent.email))]
    return [
        f"{genre} de test présent : {email}. Les comptes de test et de démonstration sont interdits en production ; "
        "utiliser une base de production vierge."
        for genre, email in sorted(adresses, key=lambda a: a[1])
        if comptes_de_test.est_compte_de_test(email)
    ]


def main() -> None:
    parser = argparse.ArgumentParser(description="Contrôles de la base avant la mise en service en production")
    parser.add_argument("commande", choices=["verifier"])
    parser.parse_args()
    from app.db.session import SessionLocale

    with SessionLocale() as session:
        trouves = problemes(session)
    if not settings.production:
        print(f"Environnement {settings.environnement} : {len(trouves)} compte(s) de test, autorisés hors production.")
        return
    for probleme in trouves:
        print(f"REFUS : {probleme}", file=sys.stderr)
    if trouves:
        sys.exit(1)
    print("Base prête pour la production : aucun compte de test ni de démonstration.")


if __name__ == "__main__":
    main()
