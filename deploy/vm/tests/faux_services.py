#!/usr/bin/env python3
"""Faux services HTTP pour le banc de test de boussole-dev-sync (ticket #65, PR 3b).

Un seul serveur local joue trois rôles :
- serveur de métadonnées GCE : jeton du compte de la VM (en-tête Metadata-Flavor exigé) ;
- API JSON de Cloud Storage : objets stockés dans un dossier, lecture, métadonnées, création avec
  ifGenerationMatch=0 ; toute LISTE du bucket est refusée (403) et journalisée ; jeton exigé ;
- application : /api/health, / et /assets/app.js, en bonne santé seulement si les conteneurs api et web
  du faux docker sont démarrés et que l'image de l'API n'est pas « cassee ».

Usage : faux_services.py <fichier port> <dossier objets> <journal requêtes> <état faux docker>
"""
import base64
import hashlib
import json
import os
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

FICHIER_PORT, OBJETS, JOURNAL, ETAT_DOCKER = sys.argv[1:5]
JETON = "faux-jeton-de-test"


def chemin_objet(nom):
    p = os.path.normpath(os.path.join(OBJETS, nom))
    if not p.startswith(os.path.normpath(OBJETS) + os.sep):
        raise ValueError(nom)
    return p


def app_en_sante():
    try:
        e = json.load(open(ETAT_DOCKER))
    except (OSError, ValueError):
        return False
    c = e["conteneurs"]
    if not all(s in c and c[s]["running"] for s in ("api", "web")):
        return False
    m = e["images"][c["api"]["image"]].get("meta", {})
    return not m.get("cassee") and not m.get("echec_publie")


class Gestionnaire(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def repondre(self, code, corps=b"{}", type_="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", type_)
        self.send_header("Content-Length", str(len(corps)))
        self.end_headers()
        self.wfile.write(corps)

    def journaliser(self):
        with open(JOURNAL, "a") as f:
            f.write(f"{self.command} {self.path} auth={'oui' if self.headers.get('Authorization') == 'Bearer ' + JETON else 'non'}\n")

    def autorise(self):
        if self.headers.get("Authorization") != "Bearer " + JETON:
            self.repondre(401, b'{"error":"jeton absent ou invalide"}')
            return False
        return True

    def do_GET(self):
        self.journaliser()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if u.path == "/computeMetadata/v1/instance/service-accounts/default/token":
            if self.headers.get("Metadata-Flavor") != "Google":
                return self.repondre(403)
            return self.repondre(200, json.dumps({"access_token": JETON, "expires_in": 3599}).encode())
        if u.path == "/api/health":
            return self.repondre(200, b'{"status":"ok"}') if app_en_sante() else self.repondre(502, b"indisponible", "text/plain")
        if u.path == "/":
            page = b'<!doctype html><html><head><script src="/assets/app.js"></script></head><body></body></html>'
            return self.repondre(200, page, "text/html") if app_en_sante() else self.repondre(502, b"indisponible", "text/plain")
        if u.path == "/assets/app.js":
            return self.repondre(200, b"console.log(1)", "text/javascript") if app_en_sante() else self.repondre(502)
        if u.path.rstrip("/").endswith("/o"):
            return self.repondre(403, b'{"error":"storage.objects.list refuse"}')
        if u.path.startswith("/storage/v1/b/"):
            if not self.autorise():
                return
            nom = urllib.parse.unquote(u.path.split("/o/", 1)[1])
            p = chemin_objet(nom)
            if not os.path.isfile(p):
                return self.repondre(404, b'{"error":"Not Found"}')
            donnees = open(p, "rb").read()
            if q.get("alt") == ["media"]:
                return self.repondre(200, donnees, "application/octet-stream")
            m = {"size": str(len(donnees)), "md5Hash": base64.b64encode(hashlib.md5(donnees).digest()).decode(),
                 "generation": str(os.stat(p).st_mtime_ns)}
            return self.repondre(200, json.dumps(m).encode())
        self.repondre(404)

    def do_POST(self):
        self.journaliser()
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        if not u.path.startswith("/upload/storage/v1/b/") or not self.autorise():
            return self.repondre(404) if not u.path.startswith("/upload/") else None
        corps = self.rfile.read(int(self.headers["Content-Length"]))
        p = chemin_objet(q["name"][0])
        if q.get("ifGenerationMatch") != ["0"]:
            return self.repondre(400, b'{"error":"creation seule attendue"}')
        if os.path.exists(p):
            return self.repondre(412, b'{"error":"conditionNotMet"}')
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(corps)
        self.repondre(200, json.dumps({"name": q["name"][0], "size": str(len(corps))}).encode())


serveur = HTTPServer(("127.0.0.1", 0), Gestionnaire)
with open(FICHIER_PORT, "w") as f:
    f.write(str(serveur.server_port))
serveur.serve_forever()
