from app.app import create_app

def test_health():
    app = create_app()
    client = app.test_client()
    resp = client.get("/healthz")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"
