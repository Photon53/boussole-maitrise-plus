"""Bilan Français d'un enfant pour son parent (#231).

Les deux circuits sont couverts : parent d'un élève de classe, et famille avec carte. Le contrôle d'accès est
celui des autres vues parent : `parents.enfants` (404 sinon).

Un **bilan**, jamais du contenu (SEC-D6, RGPD-2) : titres des cours ouverts, état, étape, scores de quiz, temps de
travail, nombre de retours de la professeure. Ni énoncé, ni corrigé, ni texte rédigé par l'enfant. Si la classe
n'a pas (ou plus) accès au français (SEC-D6), aucun cours n'est listé ; temps de travail et retours restent visibles.
"""
# Issue #231 — Espace parent : bilan Français (Claude)

from fastapi import APIRouter, HTTPException, Response, status
from sqlalchemy import func, select

from app import francais, parents
from app.auth import ParentCourant, SessionDB
from app.db import models
from app.routes.francais_accueil import cours_de_l_eleve
from app.routes.parents import _mon_enfant

router = APIRouter(prefix="/parents", tags=["parent"])

CHAMPS_COURS = ("titre", "type", "rubrique", "etat", "etape", "score", "total", "derniere_activite")


def _retours(session: SessionDB, eleve_id: int) -> dict:
    """Nombre de textes remis et relus (réponses rédigées des dossiers et rédactions) ; jamais leur contenu."""
    compte = {"remis": 0, "relus": 0}
    for modele in (models.ReponseRedigeeFrancais, models.Redaction):
        for statut, n in session.execute(
            select(modele.statut, func.count()).where(modele.eleve_id == eleve_id, modele.statut != "brouillon")
            .group_by(modele.statut)
        ):
            compte["relus" if statut == "corrigee" else "remis"] += n
    return compte


@router.get("/enfants/{eleve_id}/francais")
def bilan_francais(eleve_id: int, parent: ParentCourant, session: SessionDB, reponse: Response) -> dict:
    reponse.headers["Cache-Control"] = "private, no-store"
    eleve = _mon_enfant(session, parent, eleve_id)
    if not eleve.classe.domaine_code.startswith("francais-"):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Pas de classe de français.")
    acces, cours = cours_de_l_eleve(session, eleve)
    resume = parents.resume(session, eleve)
    lignes = [{k: c.get(k) for k in CHAMPS_COURS} for c in cours]
    return {
        "eleve": {"id": eleve.id, "prenom": eleve.prenom, "classe": eleve.classe.code,
                  "niveau": francais.niveau_de(eleve.classe)},
        "acces": acces,
        "indicateurs": {
            "cours": len(lignes),
            "commences": sum(c["etat"] != "pas_commence" for c in lignes),
            "termines": sum(c["etat"] in ("maitrise", "reussi") for c in lignes),
            "minutes_7_jours": resume.minutes_7_jours,
            "derniere_activite": resume.derniere_activite.isoformat() if resume.derniere_activite else None,
        },
        "cours": lignes,
        "a_revoir": [c["titre"] for c in lignes if c["etat"] == "a_reprendre"],
        "retours": _retours(session, eleve.id),
    }
