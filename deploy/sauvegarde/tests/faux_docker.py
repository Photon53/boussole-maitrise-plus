#!/usr/bin/env python3
# Issue #8 — Sauvegardes automatisées et restauration testée (Claude)
"""Faux docker pour le banc de deploy/sauvegarde-prod.sh : aucune base, aucun conteneur réel.

Base de production simulée : un « dump » est le texte PGDMP suivi des comptages en JSON. La base temporaire de
restauration reprend les comptages du dump qu'on lui donne. Pannes injectées par variables FAUX_* ; chaque
appel est noté dans $FAUX_LOG.
"""
import io
import json
import os
import re
import sys
import tarfile

ETAT = os.environ["FAUX_ETAT"]
COMPTAGES = {"enseignant": 3, "classe": 4, "eleve": 57, "enfant": 12, "parent": 9, "seance": 140,
             "reponse": 2210, "chapitre": 155, "question": 1795, "remarque": 2}
REVISION = os.environ.get("FAUX_REVISION", "0038")


def noter(args):
    with open(os.environ["FAUX_LOG"], "a") as f:
        f.write(" ".join(args) + "\n")


def psql(sql, comptages):
    if "alembic_version" in sql:
        return REVISION
    m = re.search(r"to_regclass\('public\.(\w+)'\)", sql)
    if m:
        return "t" if m.group(1) in comptages else "f"
    m = re.search(r"count\(\*\) FROM (\w+)", sql)
    if m:
        return str(comptages[m.group(1)])
    sys.exit(f"faux docker : SQL inattendu {sql}")


def base_temporaire():
    chemin = os.path.join(ETAT, "temporaire.json")
    return json.load(open(chemin)) if os.path.exists(chemin) else None


def main(args):
    noter(args)
    if args[0] == "compose":
        i = args.index("exec")
        service, cmd = args[i + 2], args[i + 3:]
        if service == "db":
            if os.environ.get("FAUX_DB_KO"):
                return 1
            if cmd[0] == "pg_isready":
                return 0
            if cmd[0] == "pg_dump":
                if os.environ.get("FAUX_PG_DUMP_KO"):
                    print("pg_dump: erreur simulée", file=sys.stderr)
                    return 1
                sys.stdout.write("PGDMP" + json.dumps(COMPTAGES))
                return 0
            if cmd[0] == "pg_restore":
                return 0 if sys.stdin.read().startswith("PGDMP") else 1
            if cmd[0] == "psql":
                print(psql(cmd[-1], COMPTAGES))
                return 0
        if service == "api":
            if os.environ.get("FAUX_API_KO"):
                return 1
            if cmd[0] == "true":
                return 0
            if cmd[0] == "tar":
                tampon = io.BytesIO()
                with tarfile.open(fileobj=tampon, mode="w:gz") as a:
                    for nom in ("fichiers/ressource-1.pdf", "fichiers/ressource-2.pdf"):
                        donnees = b"%PDF-1.4 faux"
                        info = tarfile.TarInfo(nom)
                        info.size = len(donnees)
                        a.addfile(info, io.BytesIO(donnees))
                sys.stdout.buffer.write(tampon.getvalue())
                return 0
        sys.exit(f"faux docker : appel compose inattendu {args}")
    if args[0] == "volume":
        return 0
    if args[0] == "rm":
        p = os.path.join(ETAT, "temporaire.json")
        if os.path.exists(p):
            os.remove(p)
        return 0
    if args[0] == "run":
        if "--network" not in args or args[args.index("--network") + 1] != "none":
            sys.exit("faux docker : base temporaire AVEC réseau (refusé par le banc)")
        if any(a.startswith("-p") or a == "--publish" for a in args):
            sys.exit("faux docker : port publié (refusé par le banc)")
        json.dump({}, open(os.path.join(ETAT, "temporaire.json"), "w"))
        return 0
    if args[0] == "exec":
        cmd = [a for a in args[1:] if a != "-i"]
        cmd = cmd[1:]  # nom du conteneur
        if cmd[0] == "pg_isready":
            return 0 if base_temporaire() is not None else 1
        if cmd[0] == "pg_restore":
            dump = sys.stdin.read()
            if not dump.startswith("PGDMP") or os.environ.get("FAUX_RESTORE_KO"):
                return 1
            comptages = json.loads(dump[5:])
            if os.environ.get("FAUX_RESTAURE_DIFF"):
                comptages["eleve"] -= 1
            json.dump(comptages, open(os.path.join(ETAT, "temporaire.json"), "w"))
            return 0
        if cmd[0] == "psql":
            print(psql(cmd[-1], base_temporaire()))
            return 0
    sys.exit(f"faux docker : appel inattendu {args}")


sys.exit(main(sys.argv[1:]))
