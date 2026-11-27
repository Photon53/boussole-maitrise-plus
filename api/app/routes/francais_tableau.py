"""Tableau de bord d'une classe de français pour son professeur (#231).

Une seule réponse pour l'écran d'accueil du professeur : cours ouverts (chapitres et dossiers, présentés ensemble,
FR-UI-D1), état de chaque élève dans chaque cours, élèves à accompagner, présentation de la classe (#111 : parcours
guidé par défaut, FR-01) et travail à faire (questions à valider dans son périmètre, rédactions).

Lecture seule. Les états reprennent les règles existantes, sans en créer : la maîtrise est celle du moteur (seuil et
calcul inchangés, ARCH-5) ; le quiz d'un dossier garde son score distinct et n'entre dans aucune maîtrise (V2-D12).
Aucun texte rédigé par un élève n'est renvoyé (RGPD-2).
"""
# Issue #231 — Tableau de bord du professeur de français (Claude)

from datetime import UTC, datetime, timedelta

from fastapi import APIRouter, Response
from pkp_engine import calculer_maitrise, est_maitrisee
from sqlalchemy import func, select

from app import permissions
from app.auth import SessionDB
from app.config import settings
from app.db import models
from app.db.conversions import historique_eleve
from app.referentiel import StatutValidation
from app.routes.francais import MembreFrancais, _classe_francais, _dossiers_ouverts

router = APIRouter(prefix="/francais", tags=["français"])

RUBRIQUE_DOSSIER = "lire"
# En dessous de cette maîtrise, après assez de réponses, un cours est « à reprendre » ; sinon « en cours ».
SEUIL_A_REPRENDRE, REPONSES_MIN = 0.5, 5
# Quiz d'un dossier : part de bonnes réponses au meilleur essai (score distinct de la maîtrise, V2-D12).
QUIZ_REUSSI, QUIZ_A_REPRENDRE = 0.8, 0.5
INACTIF_APRES = timedelta(days=7)


def _etat_chapitre(historique, competences: list[models.Competence]) -> dict:
    ids = [c.id for c in competences]
    reponses = sum(1 for r in historique if r.competence_id in ids)
    if not ids:
        return {"etat": "pas_commence", "maitrise": None, "reponses": 0}
    maitrise = sum(calculer_maitrise(historique, i) for i in ids) / len(ids)
    if reponses == 0:
        etat = "pas_commence"
    elif all(est_maitrisee(historique, i) for i in ids):
        etat = "maitrise"
    elif reponses >= REPONSES_MIN and maitrise < SEUIL_A_REPRENDRE:
        etat = "a_reprendre"
    else:
        etat = "en_cours"
    return {"etat": etat, "maitrise": round(maitrise, 2), "reponses": reponses}


def _etat_dossier(p: models.ProgressionFrancais | None) -> dict:
    if p is None or not p.tentatives or not p.total:
        return {"etat": "pas_commence", "score": None, "total": None, "tentatives": 0}
    part = p.meilleur_score / p.total
    etat = "reussi" if part >= QUIZ_REUSSI else "a_reprendre" if part < QUIZ_A_REPRENDRE else "en_cours"
    return {"etat": etat, "score": p.meilleur_score, "total": p.total, "tentatives": p.tentatives}


def _a_valider(session: SessionDB, qui: models.Enseignant) -> list[dict]:
    """Questions de français à valider dans le périmètre du professeur, hors celles dont il est l'auteur (V2-D15)."""
    lignes = session.execute(
        select(models.Chapitre.id, models.Chapitre.titre, models.Chapitre.niveau, models.Chapitre.domaine_code,
               models.Question.auteur, func.count())
        .join(models.Competence, models.Competence.chapitre_id == models.Chapitre.id)
        .join(models.Question, models.Question.competence_id == models.Competence.id)
        .where(models.Chapitre.domaine_code.in_(permissions.DOMAINES_FRANCAIS), models.Chapitre.masque.is_(False),
               models.Question.archivee.is_(False), models.Question.statut_validation == StatutValidation.A_VALIDER)
        .group_by(models.Chapitre.id, models.Chapitre.titre, models.Chapitre.niveau, models.Chapitre.domaine_code,
                  models.Question.auteur)
    ).all()
    par_chapitre: dict[int, dict] = {}
    for chapitre_id, titre, niveau, domaine, auteur, n in lignes:
        niveau = getattr(niveau, "value", niveau)
        if not permissions.peut_valider(qui, domaine, niveau):
            continue
        if auteur and auteur.strip().lower() == qui.nom.strip().lower():
            continue
        c = par_chapitre.setdefault(chapitre_id, {"chapitre_id": chapitre_id, "titre": titre, "niveau": niveau, "questions": 0})
        c["questions"] += n
    return sorted(par_chapitre.values(), key=lambda c: (c["niveau"], c["titre"]))


@router.get("/classes/{classe_id}/tableau")
def tableau_de_la_classe(classe_id: int, qui: MembreFrancais, session: SessionDB, reponse: Response) -> dict:
    reponse.headers["Cache-Control"] = "private, no-store"
    classe = _classe_francais(session, qui, classe_id)
    chapitres = sorted(classe.chapitres_proposes, key=lambda c: c.ordre)
    dossiers = _dossiers_ouverts(session, classe)
    cours = (
        [{"cle": f"chapitre-{c.id}", "type": "chapitre", "id": c.id, "titre": c.titre,
          "rubrique": c.rubrique.value if c.rubrique else None} for c in chapitres]
        + [{"cle": f"dossier-{d.code}", "type": "dossier", "code": d.code, "titre": d.titre, "rubrique": RUBRIQUE_DOSSIER}
           for d in dossiers]
    )

    eleves = sorted(classe.eleves, key=lambda e: e.prenom.lower())
    ids = [e.id for e in eleves]
    progressions = {(p.eleve_id, p.code): p for p in session.scalars(select(models.ProgressionFrancais).where(
        models.ProgressionFrancais.eleve_id.in_(ids), models.ProgressionFrancais.code.in_([d.code for d in dossiers])))} if ids else {}
    dernieres = dict(session.execute(
        select(models.Seance.eleve_id, func.max(models.Reponse.repondu_le))
        .join(models.Reponse, models.Reponse.seance_id == models.Seance.id)
        .where(models.Seance.eleve_id.in_(ids)).group_by(models.Seance.eleve_id)
    ).all()) if ids else {}
    for p in progressions.values():
        if p.tentatives and (dernieres.get(p.eleve_id) is None or _aware(p.maj_le) > _aware(dernieres[p.eleve_id])):
            dernieres[p.eleve_id] = p.maj_le

    maintenant = datetime.now(UTC)
    lignes = []
    for e in eleves:
        historique = historique_eleve(session, e.id)
        etats = {f"chapitre-{c.id}": _etat_chapitre(historique, [k for k in c.competences if not k.masque]) for c in chapitres}
        etats |= {f"dossier-{d.code}": _etat_dossier(progressions.get((e.id, d.code))) for d in dossiers}
        derniere = dernieres.get(e.id)
        lignes.append({
            "id": e.id, "prenom": e.prenom, "identifiant": e.identifiant,
            "derniere_activite": _aware(derniere).isoformat() if derniere else None,
            "actif_7j": bool(derniere and maintenant - _aware(derniere) <= INACTIF_APRES),
            "cours": etats,
            "a_accompagner": any(v["etat"] == "a_reprendre" for v in etats.values()),
        })

    maitrises = [v["maitrise"] for ligne in lignes for k, v in ligne["cours"].items()
                 if k.startswith("chapitre-") and v["reponses"]]
    return {
        "classe": {"id": classe.id, "code": classe.code, "niveau": getattr(classe.niveau, "value", classe.niveau),
                   "acces_eleves": permissions.refus_acces_classe(session, classe) is None,
                   "pilote": session.get(models.ClassePilote, classe.id) is not None},
        # #111, FR-01 : sans réglage enregistré (EX.4 en attente), la présentation est le parcours guidé par défaut.
        "presentation": {"mode": "guide", "origine": "defaut"},
        "cours": cours,
        "eleves": lignes,
        "indicateurs": {
            "eleves": len(lignes),
            "actifs_7j": sum(ligne["actif_7j"] for ligne in lignes),
            "cours_ouverts": len(cours),
            "maitrise_moyenne": round(sum(maitrises) / len(maitrises), 2) if maitrises else None,
            "a_accompagner": sum(ligne["a_accompagner"] for ligne in lignes),
        },
        "a_valider": _a_valider(session, qui),
        "redaction_ouverte": settings.redaction_active,
    }


def _aware(d: datetime) -> datetime:
    return d if d.tzinfo else d.replace(tzinfo=UTC)
