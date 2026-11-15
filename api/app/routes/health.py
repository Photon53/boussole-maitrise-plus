from fastapi import APIRouter

from app.config import settings

router = APIRouter(tags=["système"])


@router.get("/health")
def health() -> dict[str, str]:
    # Hors production, l'environnement est affiché : on sait sur quel serveur on teste (#93).
    # En production, rien de plus que l'état.
    if settings.production:
        return {"status": "ok"}
    return {"status": "ok", "environnement": settings.environnement}
