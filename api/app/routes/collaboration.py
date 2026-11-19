# Issue #171 — Candidatures de professeurs et demandes de partenariat (Claude)
"""« Enseigner ou collaborer avec nous » : formulaire public, puis « Accueil et demandes » côté administration.

Deux circuits : professeur candidat (`/collaboration/candidatures`, CV facultatif) et école, institut ou
association (`/collaboration/partenariats`). Sans compte ; rien n'est créé d'autre que la demande : ni compte, ni
habilitation, ni contrat, ni envoi de message. Fermé tant que `PKP_COLLABORATION_ACTIVE` est faux.

Côté administration, deux files distinctes (candidatures / partenariats), réservées aux administrateurs (jeton
admin, rôle revérifié en base) : un professeur ou un validateur n'y a pas accès. Le journal ne note que le
traitement (statut, issue, responsable, présence de notes), jamais les coordonnées, le message ni le CV.
"""

import json
from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, HTTPException, Query, Request, status
from fastapi.concurrency import run_in_threadpool
from fastapi.responses import FileResponse, Response
from pydantic import BaseModel, Field, ValidationError, field_validator
from sqlalchemy import func, or_, select

from app import collaboration, journal, limitation
from app.auth import AdminCourant, SessionDB
from app.config import settings
from app.db import models
from app.schemas import _EMAIL, _PRENOM

router = APIRouter(tags=["collaboration"])

TypeDemande = Literal["candidature", "partenariat"]
Statut = Literal["nouveau", "a-traiter", "traite"]
Issue = Literal["suite-demandee", "refus", "cloture"]
Matiere = Literal["maths", "francais", "anglais"]
NiveauScolaire = Literal["6e", "5e", "4e", "3e", "2nde", "1re", "Tle"]
TypeStructure = Literal["ecole", "institut", "association", "autre"]
TAILLE_PAGE = 50

Texte60 = Annotated[str, Field(min_length=1, max_length=60)]
Texte80 = Annotated[str, Field(min_length=1, max_length=80)]


def _nettoyer(v):
    return v.strip() if isinstance(v, str) else v


# ---------------------------------------------------------------------------------------------------- schémas


class _Contact(BaseModel):
    prenom: Texte60
    nom: Texte80
    email: Annotated[str, Field(min_length=5, max_length=254)]
    telephone: Annotated[str, Field(max_length=30, pattern=r"^[0-9+ ().-]*$")] | None = None
    # L'information sur l'usage et la conservation des données doit avoir été affichée et lue.
    information_lue: Literal[True]
    # Piège à robots : champ caché, laissé vide par une personne.
    site_web: Annotated[str, Field(max_length=200)] = ""

    _nettoyage = field_validator("prenom", "nom", "telephone", "site_web", mode="before")(_nettoyer)

    @field_validator("prenom", "nom")
    @classmethod
    def _lettres(cls, v: str) -> str:
        v = " ".join(v.split())
        if not _PRENOM.match(v):
            raise ValueError("Prénom et nom : lettres, espaces, tirets et apostrophes seulement.")
        return v

    @field_validator("email")
    @classmethod
    def _email(cls, v: str) -> str:
        v = v.strip().lower()
        if not _EMAIL.match(v):
            raise ValueError("Adresse e-mail invalide.")
        return v


class NouvelleCandidature(_Contact):
    matieres: Annotated[list[Matiere], Field(min_length=1, max_length=3)]
    niveaux: Annotated[list[NiveauScolaire], Field(min_length=1, max_length=7)]
    disponibilites: Annotated[str, Field(max_length=500)] | None = None
    message: Annotated[str, Field(max_length=3000)] | None = None
    cv_base64: str | None = None  # PDF encodé en base64, facultatif

    _nettoyage_texte = field_validator("disponibilites", "message", mode="before")(_nettoyer)


class NouveauPartenariat(_Contact):
    structure_nom: Annotated[str, Field(min_length=2, max_length=150)]
    structure_type: TypeStructure
    fonction: Annotated[str, Field(max_length=100)] | None = None
    partenariat: Annotated[str, Field(min_length=10, max_length=3000)]

    _nettoyage_texte = field_validator("structure_nom", "fonction", "partenariat", mode="before")(_nettoyer)


class AccuseReception(BaseModel):
    reference: str
    type: TypeDemande


class EtatCollaboration(BaseModel):
    ouvert: bool
    formats_cv: list[str]
    cv_taille_max_mo: int
    conservation_jours: int | None


class DemandeResume(BaseModel):
    id: int
    reference: str
    type: TypeDemande
    contact: str
    structure_nom: str | None
    statut: Statut
    issue: Issue | None
    a_un_cv: bool
    responsable: str | None
    cree_le: datetime


class PageDemandes(BaseModel):
    demandes: list[DemandeResume]
    total: int
    page: int
    taille_page: int


class DemandeDetail(DemandeResume):
    prenom: str
    nom: str
    email: str
    telephone: str | None
    matieres: list[str]
    niveaux: list[str]
    disponibilites: str | None
    structure_type: TypeStructure | None
    fonction: str | None
    message: str | None
    cv_taille_octets: int | None
    notes_internes: str | None
    responsable_id: int | None
    maj_le: datetime


class Traitement(BaseModel):
    statut: Statut | None = None
    issue: Issue | None = None
    notes_internes: Annotated[str, Field(max_length=3000)] | None = None
    responsable_id: int | None = None


# ---------------------------------------------------------------------------------------------------- public


@router.get("/collaboration/etat", response_model=EtatCollaboration)
def etat() -> EtatCollaboration:
    return EtatCollaboration(
        ouvert=settings.collaboration_active, formats_cv=list(collaboration.FORMATS_CV),
        cv_taille_max_mo=settings.cv_taille_max_mo, conservation_jours=settings.collaboration_conservation_jours,
    )


def _limiter(request: Request) -> None:
    """Chaque envoi compte, accepté ou non : un robot ne peut pas essayer en boucle."""
    ip = limitation.adresse_ip(request)
    limitation.verifier((limitation.collaboration_par_ip, ip), (limitation.collaboration_globale, "toutes"))
    limitation.collaboration_par_ip.enregistrer(ip)
    limitation.collaboration_globale.enregistrer("toutes")


async def _lire(request: Request, schema: type[BaseModel], limite: int) -> BaseModel:
    """Lit le corps en s'arrêtant dès que la taille maximale est dépassée, puis le valide."""
    morceaux, total = [], 0
    async for morceau in request.stream():
        total += len(morceau)
        if total > limite:
            message = f"Le CV dépasse {settings.cv_taille_max_mo} Mo." if schema is NouvelleCandidature else "Formulaire trop long."
            raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, message)
        morceaux.append(morceau)
    try:
        return schema.model_validate(json.loads(b"".join(morceaux) or b"null"))
    except json.JSONDecodeError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Formulaire illisible.") from None
    except ValidationError as erreur:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, erreur.errors(include_url=False, include_context=False, include_input=False)) from None


def _accuse_factice(type_demande: str) -> AccuseReception:
    """Réponse au robot qui a rempli le piège : identique en apparence, rien n'est enregistré."""
    return AccuseReception(reference=collaboration.PREFIXES[type_demande] + "X" * 8, type=type_demande)


def _contact(corps: _Contact) -> dict:
    return {"prenom": corps.prenom, "nom": corps.nom, "email": corps.email, "telephone": corps.telephone or None}


@router.post("/collaboration/candidatures", response_model=AccuseReception, status_code=status.HTTP_201_CREATED)
async def candidater(request: Request, session: SessionDB) -> AccuseReception:
    collaboration.exiger_ouverture()
    _limiter(request)
    corps: NouvelleCandidature = await _lire(request, NouvelleCandidature, collaboration.taille_max_corps())
    if corps.site_web:
        return _accuse_factice("candidature")
    contenu = collaboration.decoder_cv(corps.cv_base64) if corps.cv_base64 else None
    if contenu is not None:
        await run_in_threadpool(collaboration.controler_cv, contenu)  # analyse isolée et bloquante (#4)
    demande = models.DemandeCollaboration(
        reference=collaboration.nouvelle_reference(session, "candidature"), type="candidature", **_contact(corps),
        matieres=",".join(dict.fromkeys(corps.matieres)), niveaux=",".join(dict.fromkeys(corps.niveaux)),
        disponibilites=corps.disponibilites or None, message=corps.message or None,
        statut="nouveau", cree_le=collaboration.maintenant(), maj_le=collaboration.maintenant(),
    )
    if contenu is not None:
        demande.cv_fichier, demande.cv_taille_octets = collaboration.ecrire_cv(contenu), len(contenu)
    session.add(demande)
    try:
        session.commit()
    except Exception:
        collaboration.supprimer_cv(demande.cv_fichier)  # pas de CV sans demande
        raise
    return AccuseReception(reference=demande.reference, type="candidature")


@router.post("/collaboration/partenariats", response_model=AccuseReception, status_code=status.HTTP_201_CREATED)
async def proposer_partenariat(request: Request, session: SessionDB) -> AccuseReception:
    collaboration.exiger_ouverture()
    _limiter(request)
    corps: NouveauPartenariat = await _lire(request, NouveauPartenariat, 64 * 1024)
    if corps.site_web:
        return _accuse_factice("partenariat")
    demande = models.DemandeCollaboration(
        reference=collaboration.nouvelle_reference(session, "partenariat"), type="partenariat", **_contact(corps),
        structure_nom=corps.structure_nom, structure_type=corps.structure_type, fonction=corps.fonction or None,
        message=corps.partenariat, statut="nouveau", cree_le=collaboration.maintenant(), maj_le=collaboration.maintenant(),
    )
    session.add(demande)
    session.commit()
    return AccuseReception(reference=demande.reference, type="partenariat")


# ---------------------------------------------------------------------------------------------------- administration


def _liste(valeur: str | None) -> list[str]:
    return valeur.split(",") if valeur else []


def _resume(d: models.DemandeCollaboration) -> dict:
    return dict(
        id=d.id, reference=d.reference, type=d.type, contact=f"{d.prenom} {d.nom}", structure_nom=d.structure_nom,
        statut=d.statut, issue=d.issue, a_un_cv=d.cv_fichier is not None,
        responsable=d.responsable.nom if d.responsable else None, cree_le=collaboration.utc(d.cree_le),
    )


def _detail(d: models.DemandeCollaboration) -> DemandeDetail:
    return DemandeDetail(
        **_resume(d), prenom=d.prenom, nom=d.nom, email=d.email, telephone=d.telephone, matieres=_liste(d.matieres),
        niveaux=_liste(d.niveaux), disponibilites=d.disponibilites, structure_type=d.structure_type, fonction=d.fonction,
        message=d.message, cv_taille_octets=d.cv_taille_octets, notes_internes=d.notes_internes,
        responsable_id=d.responsable_id, maj_le=collaboration.utc(d.maj_le),
    )


def _demande(session, demande_id: int) -> models.DemandeCollaboration:
    d = session.get(models.DemandeCollaboration, demande_id)
    if d is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Demande introuvable.")
    return d


@router.get("/admin/accueil/demandes", response_model=PageDemandes)
def lister(
    admin: AdminCourant,
    session: SessionDB,
    type: TypeDemande,
    statut: Statut | None = None,
    q: Annotated[str | None, Query(max_length=100)] = None,
    depuis: datetime | None = None,
    jusqua: datetime | None = None,
    page: Annotated[int, Query(ge=1)] = 1,
) -> PageDemandes:
    """Une file par type : candidatures ou partenariats, jamais mélangées."""
    D = models.DemandeCollaboration
    filtres = [D.type == type]
    if statut:
        filtres.append(D.statut == statut)
    if depuis:
        filtres.append(D.cree_le >= depuis)
    if jusqua:
        filtres.append(D.cree_le <= jusqua)
    if q and q.strip():
        motif = f"%{q.strip().lower()}%"
        filtres.append(or_(*(func.lower(c).like(motif) for c in (D.reference, D.prenom, D.nom, D.email, D.structure_nom))))
    total = session.scalar(select(func.count()).select_from(D).where(*filtres)) or 0
    demandes = session.scalars(
        select(D).where(*filtres).order_by(D.cree_le.desc(), D.id.desc()).offset((page - 1) * TAILLE_PAGE).limit(TAILLE_PAGE)
    )
    return PageDemandes(demandes=[DemandeResume(**_resume(d)) for d in demandes], total=total, page=page, taille_page=TAILLE_PAGE)


@router.get("/admin/accueil/demandes/{demande_id}", response_model=DemandeDetail)
def lire(demande_id: int, admin: AdminCourant, session: SessionDB) -> DemandeDetail:
    return _detail(_demande(session, demande_id))


@router.post("/admin/accueil/demandes/{demande_id}", response_model=DemandeDetail)
def traiter(demande_id: int, corps: Traitement, admin: AdminCourant, session: SessionDB) -> DemandeDetail:
    d = _demande(session, demande_id)
    champs = corps.model_dump(exclude_unset=True)
    if champs.get("responsable_id") is not None:
        responsable = session.get(models.Enseignant, champs["responsable_id"])
        if responsable is None or responsable.role.value != "admin":
            raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Le responsable du traitement doit être un administrateur.")
    statut = champs.get("statut", d.statut)
    issue = champs.get("issue", d.issue)
    if statut == "traite" and issue is None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Indiquez l'issue du traitement : suite demandée, refus ou clôture.")
    if statut != "traite" and "issue" not in champs:
        issue = None  # une demande rouverte n'a plus d'issue
    elif statut != "traite" and issue is not None:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "L'issue ne s'indique que pour une demande traitée.")
    champs["statut"], champs["issue"] = statut, issue

    def trace() -> dict:  # jamais le texte des notes, seulement leur présence
        return {"statut": d.statut, "issue": d.issue, "responsable_id": d.responsable_id, "notes": bool(d.notes_internes)}

    avant = trace()
    for cle, valeur in champs.items():
        setattr(d, cle, (valeur.strip() or None) if cle == "notes_internes" and isinstance(valeur, str) else valeur)
    d.maj_le = collaboration.maintenant()
    journal.noter(session, admin, "traiter", "demande-collaboration", d.id, avant, trace())
    session.commit()
    return _detail(d)


@router.get("/admin/accueil/demandes/{demande_id}/cv")
def telecharger_cv(demande_id: int, admin: AdminCourant, session: SessionDB) -> FileResponse:
    d = _demande(session, demande_id)
    chemin = collaboration.chemin_cv(d)
    journal.noter(session, admin, "telecharger-cv", "demande-collaboration", d.id)
    session.commit()
    return FileResponse(
        chemin, media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="CV-{d.reference}.pdf"',
            "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff",
        },
    )


@router.get("/admin/accueil/demandes/{demande_id}/export")
def exporter(demande_id: int, admin: AdminCourant, session: SessionDB) -> Response:
    """Droit d'accès de la personne : toutes les données de sa demande (le CV se télécharge à part)."""
    d = _demande(session, demande_id)
    journal.noter(session, admin, "exporter", "demande-collaboration", d.id)
    session.commit()
    return Response(
        _detail(d).model_dump_json(indent=2), media_type="application/json",
        headers={"Content-Disposition": f'attachment; filename="demande-{d.reference}.json"', "Cache-Control": "private, no-store"},
    )


@router.delete("/admin/accueil/demandes/{demande_id}", status_code=status.HTTP_204_NO_CONTENT)
def supprimer(demande_id: int, admin: AdminCourant, session: SessionDB) -> Response:
    """Effacement (demande de la personne, ou fin du traitement) : la demande et son CV."""
    d = _demande(session, demande_id)
    fichier, type_demande = d.cv_fichier, d.type
    session.delete(d)
    journal.noter(session, admin, "supprimer", "demande-collaboration", demande_id, {"type": type_demande, "cv": fichier is not None})
    session.commit()
    collaboration.supprimer_cv(fichier)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
