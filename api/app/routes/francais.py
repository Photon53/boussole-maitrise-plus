"""Dossiers de français : consultation, validation et ouverture aux classes, réservées aux adultes habilités (#98, #212).

Même circuit que l'anglais (#212) :
- consultation : la version validée si elle existe, sinon la version courante, montrée NON VALIDÉE ;
- file de validation (`/francais/validation`) : versions soumises, relues puis validées ou refusées avec motif par un
  validateur habilité dans le domaine et le niveau ou par un administrateur (V2-D15), jamais par leur auteur ; chaque décision est journalisée ;
- ouverture : le professeur ouvre à sa classe un dossier dont une version est validée ; ses élèves n'en lisent que
  la partie élève validée (`app.routes.francais_eleves`), si la classe a accès au domaine (SEC-D6).

Un jeton d'élève, d'enfant ou de parent est refusé (401) partout ici ; la session professeur et la session
d'administration sont acceptées (#217). Un adulte doit être administrateur, ou
professeur/validateur habilité dans le domaine et le niveau du dossier ; le domaine doit être actif. L'ouverture au
public du domaine n'est ni nécessaire ni modifiée.
"""
# Issue #98 — Intégration du premier dossier Français 3e en DEV (Claude)

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import francais, francais_pdf, journal, permissions
from app.auth import AdulteAuthentifie, SessionDB
from app.db import models
from app.referentiel import Role

router = APIRouter(prefix="/francais", tags=["français"])


def membre_francais(enseignant: AdulteAuthentifie, session: SessionDB) -> models.Enseignant:
    if enseignant.mdp_provisoire:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Choisissez d'abord un nouveau mot de passe.")
    actifs = [code for code in francais.DOMAINES_FRANCAIS if francais.domaine_actif(session, code)]
    if not any(francais.peut_lire(enseignant, code, None) for code in actifs):
        raise HTTPException(status.HTTP_403_FORBIDDEN,
                            "Réservé aux adultes habilités en français, dans un domaine activé pour la préparation.")
    return enseignant


MembreFrancais = Annotated[models.Enseignant, Depends(membre_francais)]


def dossier_ou_404(session: Session, code: str, qui: models.Enseignant) -> models.DossierFrancais:
    """Dossier introuvable, de domaine inactif ou hors des habilitations : même réponse, rien n'est divulgué."""
    d = session.scalar(select(models.DossierFrancais).where(models.DossierFrancais.code == code))
    if d is None or not francais.domaine_actif(session, d.domaine_code) or not francais.peut_lire(qui, d.domaine_code, d.niveau):
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Dossier introuvable.")
    return d


def _sans_cache(reponse: Response) -> None:
    # Corrigés et supports professeur : ni cache partagé, ni conservation par le navigateur.
    reponse.headers["Cache-Control"] = "private, no-store"


@router.get("/etat")
def etat(qui: AdulteAuthentifie, session: SessionDB, reponse: Response):
    """Issue #212 : pourquoi la liste est vide ou refusée (import absent, domaine non activé), pour l'administrateur
    seul, y compris quand aucun domaine français n'est actif. Les contrôles d'accès aux dossiers sont inchangés."""
    if qui.mdp_provisoire:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Choisissez d'abord un nouveau mot de passe.")
    if qui.role != Role.ADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Réservé aux administrateurs.")
    _sans_cache(reponse)
    return francais.etat(session)


@router.get("/dossiers")
def lister(qui: MembreFrancais, session: SessionDB, reponse: Response):
    _sans_cache(reponse)
    return [francais.resume(d, qui) for d in francais.lisibles(session, qui)]


def _affichee(version: models.DossierFrancaisVersion) -> dict:
    return {"version_affichee": version.numero, "validee": version.statut == "valide"}


@router.get("/dossiers/{code}/eleve")
def apercu_eleve(code: str, qui: MembreFrancais, session: SessionDB, reponse: Response):
    """Aperçu, pour l'adulte, de la partie élève (version validée, sinon courante NON VALIDÉE), sans corrigé."""
    _sans_cache(reponse)
    d = dossier_ou_404(session, code, qui)
    v = francais.version_professeur(d)
    return {**francais.resume(d, qui), **_affichee(v), "eleve": francais.vue_eleve(v)}


@router.get("/dossiers/{code}/professeur")
def supports_professeur(code: str, qui: MembreFrancais, session: SessionDB, reponse: Response):
    _sans_cache(reponse)
    d = dossier_ou_404(session, code, qui)
    v = francais.version_professeur(d)
    return {**francais.resume(d, qui), **_affichee(v), "professeur": francais.vue_professeur(v)}


@router.get("/dossiers/{code}/pdf/{public}")
def exporter_pdf(code: str, public: str, qui: MembreFrancais, session: SessionDB) -> Response:
    """Issue #217 : PDF de la version consultée (validée, sinon courante avec la mention NON VALIDÉ).

    « eleve » : partie élève seule, sans corrigé (ARCH-4) ; « professeur » : partie élève, supports et corrigés.
    Mêmes droits que la consultation : adulte habilité dans le domaine et le niveau, domaine actif.
    """
    if public not in francais_pdf.PUBLICS:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Export inconnu.")
    d = dossier_ou_404(session, code, qui)
    v = francais.version_professeur(d)
    suffixe = "" if v.statut == "valide" else "-NON-VALIDE"
    return Response(
        content=francais_pdf.produire_pdf(d, v, public), media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{d.code}-v{v.numero}-{public}{suffixe}.pdf"',
            "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff",
        },
    )


@router.get("/dossiers/{code}/historique")
def historique(code: str, qui: MembreFrancais, session: SessionDB, reponse: Response):
    _sans_cache(reponse)
    return francais.historique(dossier_ou_404(session, code, qui))


class Refus(BaseModel):
    motif: Annotated[str, Field(max_length=2000)]

    @field_validator("motif")
    @classmethod
    def _motif(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Le motif du refus est obligatoire.")
        return v


def _decider(code: str, qui: models.Enseignant, session: Session, motif: str | None) -> dict:
    """Décision d'un validateur habilité (domaine et niveau), jamais l'auteur ; journalisée.

    Valider rend la version diffusable : elle remplace l'ancienne version validée dans les classes où le dossier est
    ouvert. Refuser laisse en place la version validée déjà diffusée.
    """
    d = dossier_ou_404(session, code, qui)
    if refus := francais.refus_validation(qui, d.domaine_code, d.niveau):
        raise HTTPException(status.HTTP_403_FORBIDDEN, refus)
    courante = d.courante
    if probleme := francais.peut_decider(courante, qui):
        raise HTTPException(status.HTTP_409_CONFLICT, probleme)
    if motif is None:
        francais.valider(d, qui)
    else:
        francais.refuser(d, qui, motif)
    journal.noter(session, qui, "valider" if motif is None else "refuser", "dossier_francais", d.id,
                  {"code": d.code, "version": courante.numero, "statut": "soumis"},
                  {"code": d.code, "version": courante.numero, "statut": courante.statut, "motif": motif})
    session.commit()
    return francais.resume(d, qui)


@router.post("/dossiers/{code}/valider")
def valider(code: str, qui: MembreFrancais, session: SessionDB):
    return _decider(code, qui, session, None)


@router.post("/dossiers/{code}/refuser")
def refuser(code: str, corps: Refus, qui: MembreFrancais, session: SessionDB):
    return _decider(code, qui, session, corps.motif)


# --- File de validation, comme l'anglais (#212) ------------------------------------------------------------------

def validateur_francais(enseignant: AdulteAuthentifie, session: SessionDB) -> models.Enseignant:
    """Validateur d'un domaine de français actif, qu'il y enseigne ou non (EX.9-bis), ou administrateur (V2-D15)."""
    if enseignant.mdp_provisoire:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Choisissez d'abord un nouveau mot de passe.")
    if not any(d in francais.DOMAINES_FRANCAIS and francais.domaine_actif(session, d)
               for d in permissions.domaines_valides(enseignant)):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Réservé aux validateurs de français.")
    return enseignant


ValidateurFrancais = Annotated[models.Enseignant, Depends(validateur_francais)]


def _a_relire(session: Session, code: str, qui: models.Enseignant) -> models.DossierFrancais:
    d = dossier_ou_404(session, code, qui)
    if refus := francais.refus_validation(qui, d.domaine_code, d.niveau):
        raise HTTPException(status.HTTP_403_FORBIDDEN, refus)
    return d


@router.get("/validation")
def a_valider(qui: ValidateurFrancais, session: SessionDB, reponse: Response):
    """Dossiers soumis que ce validateur peut relire ; les siens sont signalés (`est_auteur`), il ne peut pas les valider."""
    _sans_cache(reponse)
    return [francais.resume(d, qui) for d in francais.a_valider(session, qui)]


@router.get("/validation/{code}")
def version_a_valider(code: str, qui: ValidateurFrancais, session: SessionDB, reponse: Response):
    """La version soumise en entier : partie élève, supports professeur et historique des décisions."""
    _sans_cache(reponse)
    d = _a_relire(session, code, qui)
    c = d.courante
    return {**francais.resume(d, qui), **_affichee(c), "eleve": francais.vue_eleve(c),
            "professeur": francais.vue_professeur(c), "historique": francais.historique(d)}


@router.post("/validation/{code}/valider")
def valider_dossier(code: str, qui: ValidateurFrancais, session: SessionDB):
    return _decider(code, qui, session, None)


@router.post("/validation/{code}/refuser")
def refuser_dossier(code: str, corps: Refus, qui: ValidateurFrancais, session: SessionDB):
    return _decider(code, qui, session, corps.motif)


# --- Ouverture aux classes du professeur (#212) -----------------------------------------------------------------

class ClasseOuverture(BaseModel):
    id: int
    code: str
    niveau: str
    ouvert: bool
    ouvert_le: str | None = None
    # Les élèves ne lisent le dossier que si leur classe a accès au domaine (classe pilote d'un domaine fermé, SEC-D6).
    acces_eleves: bool
    motif_acces: str | None = None


def _classes(session: Session, d: models.DossierFrancais, qui: models.Enseignant) -> list[ClasseOuverture]:
    lignes = []
    for c in francais.classes_compatibles(qui, d):
        o = francais.ouverture(d, c)
        refus = permissions.refus_acces_classe(session, c)
        lignes.append(ClasseOuverture(
            id=c.id, code=c.code, niveau=francais.niveau_de(c), ouvert=o is not None,
            ouvert_le=o.ouvert_le.isoformat() if o and o.ouvert_le else None,
            acces_eleves=refus is None, motif_acces=refus,
        ))
    return lignes


def _ma_classe(session: Session, d: models.DossierFrancais, qui: models.Enseignant, classe_id: int) -> models.Classe:
    """Une classe active du professeur, du domaine et du niveau du dossier ; sinon 404, rien n'est divulgué."""
    classe = next((c for c in francais.classes_compatibles(qui, d) if c.id == classe_id), None)
    if classe is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Classe introuvable.")
    if qui.role != Role.ADMIN and not permissions.enseigne(qui, d.domaine_code, d.niveau):
        raise HTTPException(status.HTTP_403_FORBIDDEN, f"Vous n'enseignez pas le français en {d.niveau}.")
    return classe


@router.get("/dossiers/{code}/classes", response_model=list[ClasseOuverture])
def classes_du_dossier(code: str, qui: MembreFrancais, session: SessionDB) -> list[ClasseOuverture]:
    """Vos classes du niveau du dossier, et pour chacune : dossier ouvert ou non, accès des élèves ou motif du refus."""
    return _classes(session, dossier_ou_404(session, code, qui), qui)


@router.put("/dossiers/{code}/classes/{classe_id}", response_model=list[ClasseOuverture])
def ouvrir(code: str, classe_id: int, qui: MembreFrancais, session: SessionDB) -> list[ClasseOuverture]:
    """Ouvre le dossier à la classe ; seule sa version validée sera servie aux élèves. Sans effet s'il est déjà ouvert."""
    d = dossier_ou_404(session, code, qui)
    classe = _ma_classe(session, d, qui, classe_id)
    if d.validee is None:
        raise HTTPException(status.HTTP_409_CONFLICT,
                            "Aucune version de ce dossier n'est validée : il ne peut pas encore être ouvert aux élèves.")
    if francais.ouverture(d, classe) is None:
        d.ouvertures.append(models.OuvertureDossierFrancais(classe=classe, ouvert_par=qui))
        journal.noter(session, qui, "ouvrir", "dossier_francais", d.id,
                      apres={"code": d.code, "classe": classe.code, "version_validee": d.validee.numero})
        session.commit()
    return _classes(session, d, qui)


@router.delete("/dossiers/{code}/classes/{classe_id}", response_model=list[ClasseOuverture])
def fermer(code: str, classe_id: int, qui: MembreFrancais, session: SessionDB) -> list[ClasseOuverture]:
    """Retire le dossier à la classe : ses élèves ne le voient plus, immédiatement. Rien d'autre n'est supprimé."""
    d = dossier_ou_404(session, code, qui)
    classe = _ma_classe(session, d, qui, classe_id)
    if (o := francais.ouverture(d, classe)) is not None:
        d.ouvertures.remove(o)
        journal.noter(session, qui, "fermer", "dossier_francais", d.id, avant={"code": d.code, "classe": classe.code})
        session.commit()
    return _classes(session, d, qui)
