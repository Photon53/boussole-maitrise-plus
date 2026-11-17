# Issue #162 — Diagnostic des acquis antérieurs, lot 2 (Claude)
"""Diagnostic des acquis antérieurs : règles de diffusion et observations.

- **Diffusion** : une question de diagnostic n'atteint un élève que si elle est **validée** par un professeur, quel
  que soit `PKP_SERVIR_QUESTIONS_NON_VALIDEES` (ce réglage ne concerne que l'entraînement). Les chapitres de
  diagnostic ne passent jamais par les séances d'entraînement (`progression.filtre_apprentissage`).
- **Public** : seulement un élève d'une classe active du niveau du chapitre, dont le parcours figure dans `publics`.
- **Observations** : table `observation_diagnostic`, distincte de `reponse`. Le taux de maîtrise, calculé sur
  `reponse`, ne les lit jamais.
- **Rédaction** : jamais corrigée par le moteur ; « en attente de correction » jusqu'à la décision d'un professeur.
- **Choix multiples** : ensemble exact des lettres cochées, sans crédit partiel (voir `pkp_engine.correction`).

La passation (lot 3), le dépôt de fichiers (lot 4) et le bilan (lot 5) s'appuient sur ce module.
"""

from datetime import UTC, datetime

from pkp_engine import Verdict, corrige_automatiquement, verifier
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import models
from app.db.conversions import question_vers_domaine
from app.referentiel import NatureChapitre, Role, StatutObservation, StatutValidation, domaine_maths

LONGUEUR_REPONSE_COURTE = 200
LONGUEUR_REDACTION = 4000


class DiagnosticRefuse(Exception):
    """Action refusée : question non diffusable, élève hors du public, observation déjà corrigée…"""


def filtre_diffusable() -> tuple:
    """Conditions SQL (requête jointe à `competence` et `chapitre`) : questions de diagnostic montrables à un élève."""
    return (
        models.Chapitre.nature == NatureChapitre.DIAGNOSTIC,
        models.Chapitre.masque.is_(False),
        models.Competence.masque.is_(False),
        models.Question.archivee.is_(False),
        models.Question.statut_validation == StatutValidation.VALIDEE,
    )


def chapitres_du_public(session: Session, classe: models.Classe) -> list[models.Chapitre]:
    """Chapitres de diagnostic destinés à cette classe : même niveau, parcours de la classe dans `publics`."""
    if classe.archivee_le is not None:
        return []
    candidats = session.scalars(
        select(models.Chapitre)
        .where(
            models.Chapitre.nature == NatureChapitre.DIAGNOSTIC,
            models.Chapitre.masque.is_(False),
            models.Chapitre.niveau == classe.niveau,
            models.Chapitre.domaine_code == domaine_maths(classe.niveau),
        )
        .order_by(models.Chapitre.ordre)
    )
    return [c for c in candidats if classe.parcours.value in (c.publics or [])]


def questions_diffusables(session: Session, classe: models.Classe) -> list[models.Question]:
    """Questions de diagnostic qu'un élève de cette classe peut recevoir : validées seulement."""
    chapitres = [c.id for c in chapitres_du_public(session, classe)]
    if not chapitres:
        return []
    return list(
        session.scalars(
            select(models.Question)
            .join(models.Competence, models.Question.competence_id == models.Competence.id)
            .join(models.Chapitre, models.Competence.chapitre_id == models.Chapitre.id)
            .where(models.Chapitre.id.in_(chapitres), *filtre_diffusable())
            .order_by(models.Chapitre.ordre, models.Competence.ordre, models.Question.difficulte, models.Question.id)
        )
    )


def est_diffusable(session: Session, question: models.Question, eleve: models.Eleve) -> bool:
    return question.id in {q.id for q in questions_diffusables(session, eleve.classe)}


def statut_automatique(question: models.Question, reponse_donnee: str) -> StatutObservation:
    """Juste ou faux selon le moteur ; « en attente de correction » pour une réponse rédigée (jamais le moteur)."""
    domaine = question_vers_domaine(question)
    if not corrige_automatiquement(domaine):
        return StatutObservation.EN_ATTENTE
    # Une valeur juste mais pas sous la forme demandée n'est pas une réussite (Verdict.FORME).
    return StatutObservation.JUSTE if verifier(domaine, reponse_donnee) is Verdict.JUSTE else StatutObservation.FAUX


def enregistrer_observation(
    session: Session, eleve: models.Eleve, question: models.Question, reponse_donnee: str
) -> models.ObservationDiagnostic:
    """Enregistre la réponse d'un élève à une question de diagnostic (dans `observation_diagnostic`, jamais dans
    `reponse`). Lève `DiagnosticRefuse` si la question n'est pas diffusable à cet élève."""
    if not est_diffusable(session, question, eleve):
        raise DiagnosticRefuse("Question de diagnostic non disponible pour cet élève (non validée ou hors public).")
    limite = LONGUEUR_REDACTION if not corrige_automatiquement(question_vers_domaine(question)) else LONGUEUR_REPONSE_COURTE
    if len(reponse_donnee) > limite:
        raise DiagnosticRefuse(f"Réponse trop longue ({limite} caractères au plus).")
    observation = models.ObservationDiagnostic(
        eleve=eleve, question=question, reponse_donnee=reponse_donnee,
        statut=statut_automatique(question, reponse_donnee), observe_le=datetime.now(UTC),
    )
    session.add(observation)
    session.flush()
    return observation


def en_attente(session: Session, classe: models.Classe) -> list[models.ObservationDiagnostic]:
    """Réponses rédigées des élèves de la classe qui attendent la correction du professeur."""
    return list(
        session.scalars(
            select(models.ObservationDiagnostic)
            .join(models.Eleve, models.ObservationDiagnostic.eleve_id == models.Eleve.id)
            .where(models.Eleve.classe_id == classe.id, models.ObservationDiagnostic.statut == StatutObservation.EN_ATTENTE)
            .order_by(models.ObservationDiagnostic.observe_le, models.ObservationDiagnostic.id)
        )
    )


def corriger_observation(
    session: Session, observation: models.ObservationDiagnostic, juste: bool, enseignant: models.Enseignant
) -> models.ObservationDiagnostic:
    """Décision du professeur sur une réponse rédigée. Seul le professeur de la classe (ou un administrateur)
    corrige ; une observation déjà corrigée ne change plus ici (le lot 4 décidera d'une éventuelle révision)."""
    if observation.statut is not StatutObservation.EN_ATTENTE:
        raise DiagnosticRefuse("Cette réponse n'attend pas de correction.")
    if enseignant.role is not Role.ADMIN and observation.eleve.classe.enseignant_id != enseignant.id:
        raise DiagnosticRefuse("Seul le professeur de la classe corrige cette réponse.")
    observation.statut = StatutObservation.JUSTE if juste else StatutObservation.FAUX
    observation.corrige_par = enseignant
    observation.corrige_le = datetime.now(UTC)
    session.flush()
    return observation
