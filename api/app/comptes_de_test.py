"""Comptes de test : reconnus à leur adresse dans un domaine réservé, autorisés hors production seulement (#93).

Les domaines `.test`, `.example`, `.invalid`, `.localhost` et `example.com/.net/.org` sont réservés (RFC 2606, RFC 6761) : ils
n'appartiennent à personne et ne reçoivent jamais de courrier. Un compte de test (et tout compte de la démonstration,
en `@pkp.test`) se reconnaît donc sans liste à tenir à jour : `prof.essai@boussole.test`, `admin.recette@boussole.test`.

Ces comptes ont leur propre mot de passe et, pour un administrateur, le même second facteur que les autres : rien
n'est assoupli. En production, ils sont refusés à la création, à la connexion et au contrôle avant mise en service.
"""
# Issue #93 — Comptes de test en DEV, interdits en production (Claude)

from fastapi import HTTPException, status

from app.config import settings

DOMAINES_RESERVES = (".test", ".example", ".invalid", ".localhost")  # domaines de premier niveau
DOMAINES_EXEMPLE = ("example.com", "example.net", "example.org")  # RFC 2606, avec leurs sous-domaines
REFUS_PRODUCTION = "Compte de test refusé en production : utilisez une adresse réelle."


def est_compte_de_test(email: str) -> bool:
    domaine = email.strip().lower().rpartition("@")[2].rstrip(".")
    return any(domaine == d[1:] or domaine.endswith(d) for d in DOMAINES_RESERVES) or any(
        domaine == d or domaine.endswith("." + d) for d in DOMAINES_EXEMPLE
    )


def refuser_en_production(email: str) -> None:
    """403 en production pour un compte de test ; sans effet ailleurs."""
    if settings.production and est_compte_de_test(email):
        raise HTTPException(status.HTTP_403_FORBIDDEN, REFUS_PRODUCTION)
