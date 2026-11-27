"""Accueil Français de l'élève (#231) : reprendre son cours, les quatre rubriques, ses cours ouverts.

Une seule réponse pour l'écran d'accueil : chapitres ouverts à la classe et dossiers validés ouverts à la classe,
présentés ensemble (FR-UI-D1 : rubriques Lire et comprendre, Grammaire, Conjugaison, Rédaction), avec l'état de
l'élève et l'étape du parcours guidé en sept étapes (FR-UI-D2), calculée pour l'affichage seulement (FR-UI-D3 : le
moteur choisit toujours les questions). Mêmes règles d'accès que le reste du français : si la classe n'a pas accès
au domaine (SEC-D6), aucun cours n'est listé. Ni solution ni corrigé (ARCH-4).
"""
# Issue #231 — Accueil Français de l'élève (Claude)

from datetime import UTC, datetime

from fastapi import APIRouter, Response
from sqlalchemy import func, select

from app import francais, permissions
from app.auth import EleveCourant, SessionDB
from app.config import settings
from app.db import models
from app.db.conversions import historique_eleve
from app.progression import ids_ouverts_eleve, nb_questions_servables
from app.routes.francais_tableau import _etat_chapitre, _etat_dossier
from app.routes.redactions import _sujets as sujets_de_redaction

router = APIRouter(prefix="/francais/eleve", tags=["français-élève"])

RUBRIQUES = ("lire", "grammaire", "conjugaison", "redaction")
ETAPES = ("Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider")


def _etape(etat: dict) -> int:
    """Étape affichée du parcours guidé (1 à 7), d'après ce que l'élève a fait : rien → Découvrir ; maîtrisé ou
    réussi → Consolider ; sinon Appliquer, S'entraîner puis Approfondir au fil des réponses (3 par étape)."""
    if etat["etat"] in ("maitrise", "reussi"):
        return 7
    fait = etat.get("reponses", etat.get("tentatives", 0)) or 0
    if not fait:
        return 1
    return min(5, 3 + fait // 3)


def _aware(d: datetime | None) -> datetime | None:
    return d if d is None or d.tzinfo else d.replace(tzinfo=UTC)


def cours_de_l_eleve(session: SessionDB, eleve: models.Eleve) -> tuple[bool, list[dict]]:
    """Accès de la classe (SEC-D6) et cours ouverts de l'élève avec son état et son étape ; aucun cours sans accès.
    Partagé par l'accueil de l'élève et le bilan de ses parents (#231)."""
    classe = eleve.classe
    acces = permissions.refus_acces_classe(session, classe) is None
    cours: list[dict] = []
    if acces:
        permis = set(ids_ouverts_eleve(session, classe))
        chapitres = sorted((c for c in classe.chapitres_proposes if c.id in permis), key=lambda c: c.ordre)
        nb = nb_questions_servables(session, [c.id for c in chapitres])
        historique = historique_eleve(session, eleve.id)
        derniers = dict(session.execute(
            select(models.Competence.chapitre_id, func.max(models.Reponse.repondu_le))
            .join(models.Question, models.Question.competence_id == models.Competence.id)
            .join(models.Reponse, models.Reponse.question_id == models.Question.id)
            .join(models.Seance, models.Seance.id == models.Reponse.seance_id)
            .where(models.Seance.eleve_id == eleve.id).group_by(models.Competence.chapitre_id)
        ).all())
        for c in chapitres:
            competences = sorted((k for k in c.competences if not k.masque), key=lambda k: (k.ordre, k.code))
            etat = _etat_chapitre(historique, competences)
            lecon = next((k for k in competences if k.lecon is not None), None)
            cours.append({
                "cle": f"chapitre-{c.id}", "type": "chapitre", "id": c.id, "titre": c.titre,
                "rubrique": c.rubrique.value if c.rubrique else None,
                "competence_id": lecon.id if lecon else (competences[0].id if competences else None),
                "a_une_lecon": lecon is not None, "nb_questions": nb.get(c.id, 0),
                **etat, "etape": _etape(etat), "derniere_activite": _iso(derniers.get(c.id)),
            })
        for d in francais.ouverts_a(session, classe):
            p = session.scalar(select(models.ProgressionFrancais).where(
                models.ProgressionFrancais.eleve_id == eleve.id, models.ProgressionFrancais.code == d.code))
            etat = _etat_dossier(p)
            cours.append({
                "cle": f"dossier-{d.code}", "type": "dossier", "code": d.code, "titre": d.titre, "rubrique": "lire",
                "nb_quiz": len(d.validee.quiz or []), **etat, "etape": _etape(etat),
                "derniere_activite": _iso(p.maj_le) if p and p.tentatives else None,
            })
    return acces, cours


@router.get("/accueil")
def accueil(eleve: EleveCourant, session: SessionDB, reponse: Response) -> dict:
    reponse.headers["Cache-Control"] = "private, no-store"
    classe = eleve.classe
    acces, cours = cours_de_l_eleve(session, eleve)

    # Reprendre : le cours le plus récemment travaillé qui n'est pas terminé, sinon le premier à commencer.
    en_cours = sorted((c for c in cours if c["derniere_activite"] and c["etape"] < 7),
                      key=lambda c: c["derniere_activite"], reverse=True)
    a_commencer = [c for c in cours if c["etat"] == "pas_commence"]
    reprise = (en_cours or a_commencer or [None])[0]
    return {
        "eleve": {"prenom": eleve.prenom, "classe": classe.code, "niveau": francais.niveau_de(classe)},
        "acces": acces,
        "presentation": {"mode": "guide", "origine": "defaut"},
        "etapes": list(ETAPES),
        "cours": cours,
        "reprise": reprise["cle"] if reprise else None,
        "rubriques": {r: sum(c["rubrique"] == r for c in cours) for r in RUBRIQUES},
        "redaction_ouverte": settings.redaction_active,
    }


@router.get("/redaction/{competence_id}")
def consignes_de_redaction(competence_id: int, eleve: EleveCourant, session: SessionDB, reponse: Response) -> dict:
    """Consigne des sujets de rédaction d'une compétence, pour l'atelier de rédaction de l'écran de cours (#231).

    Du **contenu** seulement, comme la leçon : mêmes règles que les sujets de rédaction (chapitre ouvert à la classe,
    accès au domaine, question validée). Servie même quand la rédaction en ligne est fermée, pour que l'élève rédige
    sur sa copie : aucun texte d'élève n'est lu ni enregistré ici, la fermeture des routes de rédaction (RGPD-2)
    reste entière. Ni solution ni guide du professeur (ARCH-4).
    """
    reponse.headers["Cache-Control"] = "private, no-store"
    sujets = [q for q in sujets_de_redaction(session, eleve) if q.competence_id == competence_id]
    return {
        "ouverte": settings.redaction_active,
        "sujets": [{"question_id": q.id, "enonce": q.enonce} for q in sujets],
    }


def _iso(d: datetime | None) -> str | None:
    return _aware(d).isoformat() if d else None
