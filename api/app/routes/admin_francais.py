"""Page « Français » de l'administration (#231) : où en est la matière, et ce qu'il reste à faire.

Synthèse en lecture seule, réservée à l'administrateur : domaines, cours (chapitres YAML et dossiers, présentés
ensemble), état de validation, ouverture aux classes, classes pilotes, validateurs habilités par niveau, fonctions
sensibles et alertes. Aucune action ici : chaque alerte renvoie vers l'écran existant qui la traite (validation,
équipe, domaines). Aucune donnée d'élève n'est renvoyée, hormis des effectifs.
"""
# Issue #231 — Espace administrateur Français (Claude)

from fastapi import APIRouter, Response
from sqlalchemy import func, select
from sqlalchemy.orm import selectinload

from app import permissions
from app.auth import AdminCourant, SessionDB
from app.config import settings
from app.db import models
from app.referentiel import NatureChapitre, StatutValidation

router = APIRouter(prefix="/admin/francais", tags=["administration"])

DOMAINES = permissions.DOMAINES_FRANCAIS
ORDRE_NIVEAUX = ["6e", "5e", "4e", "3e", "2nde", "1re", "Tle"]
# Rubriques affichées (FR-UI-D1) : les dossiers forment « Lire et comprendre ».
RUBRIQUE_DOSSIER = "lire"


def _niveau(valeur) -> str:
    return getattr(valeur, "value", valeur)


def _cle_niveau(niveau: str) -> int:
    return ORDRE_NIVEAUX.index(niveau) if niveau in ORDRE_NIVEAUX else len(ORDRE_NIVEAUX)


def _classes_actives(session: SessionDB) -> list[models.Classe]:
    return list(session.scalars(
        select(models.Classe)
        .where(models.Classe.archivee_le.is_(None), models.Classe.domaine_code.in_(DOMAINES))
        .options(selectinload(models.Classe.chapitres_proposes), selectinload(models.Classe.enseignant))
        .order_by(models.Classe.code)
    ))


def _statut_chapitre(ch: models.Chapitre, q: dict) -> str:
    if ch.masque:
        return "masque"
    if q["total"] == 0:
        return "vide"
    if q["a_corriger"]:
        return "a_corriger"
    if q["validees"] == q["total"]:
        return "pret"
    return "a_valider"


def _statut_dossier(d: models.DossierFrancais) -> str:
    courante = d.courante.statut
    if courante == "soumis":
        return "a_valider" if d.validee is None else "revision_a_valider"
    if d.validee is not None:
        return "pret"
    return "a_corriger" if courante == "refuse" else "brouillon"


def _cours(session: SessionDB, classes: list[models.Classe]) -> list[dict]:
    comptes: dict[int, dict] = {}
    for chapitre_id, statut, n in session.execute(
        select(models.Competence.chapitre_id, models.Question.statut_validation, func.count())
        .join(models.Question, models.Question.competence_id == models.Competence.id)
        .join(models.Chapitre, models.Chapitre.id == models.Competence.chapitre_id)
        .where(models.Question.archivee.is_(False), models.Chapitre.domaine_code.in_(DOMAINES))
        .group_by(models.Competence.chapitre_id, models.Question.statut_validation)
    ):
        q = comptes.setdefault(chapitre_id, {"total": 0, "validees": 0, "a_valider": 0, "a_corriger": 0})
        q["total"] += n
        cle = {StatutValidation.VALIDEE: "validees", StatutValidation.A_CORRIGER: "a_corriger"}.get(statut, "a_valider")
        q[cle] += n

    ouverts_chapitre: dict[int, list[str]] = {}
    for c in classes:
        for ch in c.chapitres_proposes:
            ouverts_chapitre.setdefault(ch.id, []).append(c.code)

    cours = []
    for ch in session.scalars(
        select(models.Chapitre).where(
            models.Chapitre.domaine_code.in_(DOMAINES), models.Chapitre.nature == NatureChapitre.APPRENTISSAGE
        )
    ):
        q = comptes.get(ch.id, {"total": 0, "validees": 0, "a_valider": 0, "a_corriger": 0})
        cours.append({
            "type": "chapitre", "id": ch.id, "code": ch.code, "titre": ch.titre, "niveau": _niveau(ch.niveau),
            "domaine": ch.domaine_code, "rubrique": ch.rubrique.value if ch.rubrique else None, "ordre": ch.ordre,
            "questions": q, "statut": _statut_chapitre(ch, q), "classes": sorted(ouverts_chapitre.get(ch.id, [])),
        })

    actives = {c.id for c in classes}
    for d in session.scalars(select(models.DossierFrancais).where(models.DossierFrancais.domaine_code.in_(DOMAINES))):
        validee = d.validee
        cours.append({
            "type": "dossier", "id": d.id, "code": d.code, "titre": d.titre, "niveau": d.niveau, "domaine": d.domaine_code,
            "rubrique": RUBRIQUE_DOSSIER, "ordre": 100,
            "version": {"courante": d.courante.numero, "statut_courante": d.courante.statut,
                        "validee": validee.numero if validee else None},
            "statut": _statut_dossier(d),
            "classes": sorted(o.classe.code for o in d.ouvertures if o.classe_id in actives),
        })
    return sorted(cours, key=lambda c: (_cle_niveau(c["niveau"]), c["ordre"], c["titre"]))


def _equipe(session: SessionDB) -> dict[str, dict[str, list[str]]]:
    """Par domaine : noms des validateurs et des professeurs habilités, par niveau (« * » : tout le domaine)."""
    equipe: dict[str, dict[str, list[str]]] = {"validateur": {}, "professeur": {}}
    for h in session.scalars(
        select(models.Habilitation)
        .join(models.Enseignant, models.Enseignant.id == models.Habilitation.enseignant_id)
        .where(models.Habilitation.domaine_code.in_(DOMAINES), models.Enseignant.actif.is_(True))
        .options(selectinload(models.Habilitation.enseignant))
    ):
        noms = equipe[h.role].setdefault(h.niveau or "*", [])
        if h.enseignant.nom not in noms:
            noms.append(h.enseignant.nom)
    return equipe


def _pour_niveau(equipe: dict[str, list[str]], niveau: str) -> list[str]:
    return sorted({*equipe.get(niveau, []), *equipe.get("*", [])})


@router.get("/synthese")
def synthese(_: AdminCourant, session: SessionDB, reponse: Response) -> dict:
    reponse.headers["Cache-Control"] = "private, no-store"
    domaines = []
    for code in DOMAINES:
        d = session.get(models.DomainePedagogique, code)
        domaines.append({"code": code, "libelle": permissions.LIBELLES[code], "actif": bool(d and d.actif),
                         "public": bool(d and d.public)})

    classes = _classes_actives(session)
    pilotes_ids = set(session.scalars(select(models.ClassePilote.classe_id)))
    effectifs = dict(session.execute(
        select(models.Eleve.classe_id, func.count()).where(models.Eleve.classe_id.in_([c.id for c in classes]))
        .group_by(models.Eleve.classe_id)
    ).all()) if classes else {}
    cours = _cours(session, classes)
    equipe = _equipe(session)

    ouverts_par_classe: dict[str, int] = {}
    for c in cours:
        for code in c["classes"]:
            ouverts_par_classe[code] = ouverts_par_classe.get(code, 0) + 1
    vues_classes = [
        {"id": c.id, "code": c.code, "niveau": _niveau(c.niveau), "domaine": c.domaine_code,
         "enseignant": c.enseignant.nom, "eleves": effectifs.get(c.id, 0), "pilote": c.id in pilotes_ids,
         "cours_ouverts": ouverts_par_classe.get(c.code, 0)}
        for c in classes
    ]

    niveaux_vus = {c["niveau"] for c in cours} | {c["niveau"] for c in vues_classes}
    niveaux = []
    for niveau in sorted(niveaux_vus, key=_cle_niveau):
        du_niveau = [c for c in cours if c["niveau"] == niveau and c["statut"] != "masque"]
        niveaux.append({
            "niveau": niveau,
            "cours": len(du_niveau),
            "cours_prets": sum(c["statut"] == "pret" for c in du_niveau),
            "questions": sum(c.get("questions", {}).get("total", 0) for c in du_niveau),
            "questions_validees": sum(c.get("questions", {}).get("validees", 0) for c in du_niveau),
            "validateurs": _pour_niveau(equipe["validateur"], niveau),
            "professeurs": _pour_niveau(equipe["professeur"], niveau),
            "classes_pilotes": [c["code"] for c in vues_classes if c["niveau"] == niveau and c["pilote"]],
        })

    fonctions = [
        {"code": "redaction", "libelle": "Rédaction en ligne des élèves", "active": settings.redaction_active,
         "reglage": "PKP_REDACTION_ACTIVE", "decision": "RGPD-2"},
        {"code": "pdf", "libelle": "PDF de « Mon cours »", "active": settings.pdf_francais_ouvert,
         "reglage": "PKP_PDF_FRANCAIS_OUVERT", "decision": "V2-D12 (A5)"},
    ]
    visibles = [c for c in cours if c["statut"] != "masque"]
    chiffres = {
        "cours": len(visibles),
        "cours_prets": sum(c["statut"] == "pret" for c in visibles),
        "questions": sum(c.get("questions", {}).get("total", 0) for c in visibles),
        "questions_validees": sum(c.get("questions", {}).get("validees", 0) for c in visibles),
        "classes_pilotes": sum(c["pilote"] for c in vues_classes),
        "eleves_pilotes": sum(c["eleves"] for c in vues_classes if c["pilote"]),
    }
    return {
        "domaines": domaines, "chiffres": chiffres, "niveaux": niveaux, "cours": cours, "classes": vues_classes,
        "fonctions": fonctions, "alertes": _alertes(domaines, niveaux, cours, vues_classes),
    }


def _alertes(domaines: list[dict], niveaux: list[dict], cours: list[dict], classes: list[dict]) -> list[dict]:
    """Ce qui empêche les élèves pilotes de travailler, du plus bloquant au moins urgent ; chaque alerte nomme
    l'écran qui la traite."""
    alertes: list[dict] = []
    college = next(d for d in domaines if d["code"] == "francais-college")
    if not college["actif"]:
        alertes.append({"gravite": "bloquant", "action": "domaines",
                        "message": "Le Français collège n'est pas activé : ni l'équipe ni les classes pilotes n'y ont accès."})

    a_valider_q = sum(c.get("questions", {}).get("a_valider", 0) for c in cours if c["statut"] != "masque")
    if a_valider_q:
        n = sum(1 for c in cours if c["type"] == "chapitre" and c["statut"] == "a_valider")
        alertes.append({"gravite": "a_faire", "action": "validation-questions",
                        "message": f"{a_valider_q} question{'s' if a_valider_q > 1 else ''} à valider dans {n} cours : "
                                   "un cours n'est proposé aux élèves qu'une fois ses questions validées."})
    a_corriger = [c for c in cours if c["statut"] == "a_corriger"]
    if a_corriger:
        alertes.append({"gravite": "a_faire", "action": "validation-questions",
                        "message": f"{len(a_corriger)} cours ont des questions renvoyées « à corriger » : "
                                   + ", ".join(c["titre"] for c in a_corriger[:3]) + "."})
    dossiers = [c for c in cours if c["type"] == "dossier" and c["statut"] in ("a_valider", "revision_a_valider")]
    if dossiers:
        alertes.append({"gravite": "a_faire", "action": "validation-dossiers",
                        "message": f"{len(dossiers)} dossier{'s' if len(dossiers) > 1 else ''} soumis à validation : "
                                   + ", ".join(c["titre"] for c in dossiers) + "."})

    for n in niveaux:
        if n["cours"] and not n["validateurs"]:
            alertes.append({"gravite": "attention", "action": "equipe",
                            "message": f"Aucun professeur validateur en {n['niveau']} : seul l'administrateur peut valider "
                                       f"les {n['cours']} cours de ce niveau."})
    pilotes = [c for c in classes if c["pilote"]]
    if not pilotes:
        alertes.append({"gravite": "attention", "action": "classes-pilotes",
                        "message": "Aucune classe pilote : aucun élève ne peut encore travailler en français."})
    for c in pilotes:
        if not c["cours_ouverts"]:
            alertes.append({"gravite": "attention", "action": "classes",
                            "message": f"La classe pilote {c['code']} ({c['enseignant']}) n'a aucun cours ouvert : "
                                       "ses élèves ne voient rien."})
        if not c["eleves"]:
            alertes.append({"gravite": "attention", "action": "classes",
                            "message": f"La classe pilote {c['code']} n'a encore aucun élève inscrit."})
    for n in niveaux:
        if n["cours_prets"] and not n["classes_pilotes"]:
            alertes.append({"gravite": "info", "action": "classes-pilotes",
                            "message": f"{n['cours_prets']} cours prêt{'s' if n['cours_prets'] > 1 else ''} en {n['niveau']}, "
                                       "mais aucune classe pilote de ce niveau."})
    ordre = {"bloquant": 0, "a_faire": 1, "attention": 2, "info": 3}
    return sorted(alertes, key=lambda a: ordre[a["gravite"]])
