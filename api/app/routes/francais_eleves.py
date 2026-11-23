"""Dossiers de français servis aux élèves (#212) : même règle que l'anglais, seule la version validée est lue.

Un élève ne lit un dossier que si :
- son professeur l'a ouvert à sa classe (`/francais/dossiers/{code}/classes/{id}`) ;
- une version du dossier est validée : c'est elle, et elle seule, qui est servie ; une révision soumise ou refusée
  ne la remplace pas ;
- sa classe a accès au domaine : domaine public, ou classe pilote d'un domaine actif mais fermé (SEC-D6), contrôlé
  ici côté API, y compris par adresse directe.

Seule la partie élève est servie : ni corrigé, ni support professeur (ARCH-4). Aucune réponse n'est reçue : les
réponses sont rédigées et relèvent d'un retour du professeur, la plateforme ne les corrige pas.
"""
# Issue #212 — Circuit du français aligné sur l'anglais (Claude)

from fastapi import APIRouter, HTTPException, Response, status

from app import francais, permissions
from app.auth import EleveCourant, SessionDB

router = APIRouter(prefix="/francais/eleve", tags=["français-élève"])


def _sans_cache(reponse: Response) -> None:
    reponse.headers["Cache-Control"] = "private, no-store"


def _ligne(d) -> dict:
    return {"code": d.code, "titre": d.titre, "niveau": d.niveau, "version": d.validee.numero}


@router.get("/dossiers")
def mes_dossiers(eleve: EleveCourant, session: SessionDB, reponse: Response):
    """Dossiers ouverts à sa classe, dans leur version validée ; aucun si la classe n'a pas accès au domaine."""
    _sans_cache(reponse)
    return [_ligne(d) for d in francais.ouverts_a(session, eleve.classe)]


@router.get("/dossiers/{code}")
def mon_dossier(code: str, eleve: EleveCourant, session: SessionDB, reponse: Response):
    _sans_cache(reponse)
    classe = eleve.classe
    if classe.domaine_code.startswith("francais-") and (refus := permissions.refus_acces_classe(session, classe)):
        raise HTTPException(status.HTTP_403_FORBIDDEN, refus)
    d = next((d for d in francais.ouverts_a(session, classe) if d.code == code), None)
    if d is None:  # inconnu, non ouvert, jamais validé ou d'un autre niveau : même réponse, rien n'est divulgué
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Dossier introuvable.")
    return {**_ligne(d), "eleve": francais.vue_eleve(d.validee)}
