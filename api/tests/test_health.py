from fastapi.testclient import TestClient

from app.main import app
from app.schemas import QuestionPublique

client = TestClient(app)


def test_health():
    r = client.get("/health")
    assert r.status_code == 200
    # Hors production, l'environnement est indiqué (#93) ; les contrôles de déploiement ne lisent que « ok ».
    assert r.json() == {"status": "ok", "environnement": "dev"}


def test_question_publique_sans_solution():
    assert "solution" not in QuestionPublique.model_fields
