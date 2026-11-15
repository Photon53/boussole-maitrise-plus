#!/usr/bin/env python3
"""Faux « docker » pour le banc de test de boussole-dev-sync (ticket #65, PR 3b).

Simule, dans un fichier d'état JSON (variable FAUX_DOCKER_ETAT) : les images (tags, digests), un registre,
les conteneurs du projet Compose « boussole », la base (révision Alembic, empreinte du contenu importé),
la migration, l'import pédagogique, pg_dump / pg_restore et l'archive du volume fichiers.
Chaque appel est ajouté au journal « appels » de l'état. Aucune commande réelle n'est lancée.

Comportement des images du registre (« meta ») :
  head            révision Alembic attendue par le code
  revisions       révisions connues du code (alembic current échoue sur une révision inconnue)
  cassee          l'application ne répond pas (contrôles de santé en échec)
  migration_ko    alembic upgrade échoue (après avoir posé une révision intermédiaire si « rev_partielle »)
  import_ko       l'import pédagogique échoue
  import_modifie  l'import modifie les données (nouvelle empreinte)
  echec_publie    contrôles internes réussis, application publiée en échec (échec après ouverture)

Interruption : si l'état contient « tuer_si » et que la commande appelée le contient, tout le groupe de
processus (boussole-dev-sync lancé par setsid) est tué, comme lors d'un arrêt brutal de la VM.
"""
import io
import json
import os
import signal
import sys
import tarfile

ETAT = os.environ["FAUX_DOCKER_ETAT"]


def charger():
    with open(ETAT) as f:
        return json.load(f)


def sauver(e):
    tmp = ETAT + ".tmp"
    with open(tmp, "w") as f:
        json.dump(e, f, indent=1)
    os.replace(tmp, ETAT)


def image_id(e, ref):
    """Identifiant d'image pour un id, un tag ou une référence repo@digest ; None si inconnue."""
    if ref in e["images"]:
        return ref
    for iid, im in e["images"].items():
        if ref in im["tags"] or ref in im["digests"]:
            return iid
    return None


def meta(e, iid):
    return e["images"][iid].get("meta", {})


def conteneur_par_id(e, cid):
    for s, c in e["conteneurs"].items():
        if c["id"] == cid:
            return s, c
    return None, None


def options(args, avec_valeur):
    """Sépare options et arguments positionnels (options à valeur listées dans avec_valeur)."""
    opts, pos, i = {}, [], 0
    while i < len(args):
        a = args[i]
        if a in avec_valeur:
            opts.setdefault(a, []).append(args[i + 1])
            i += 2
        elif a.startswith("-") and pos == []:
            opts[a] = True
            i += 1
        else:
            pos.append(a)
            i += 1
    return opts, pos


def lire_env(chemin):
    d = {}
    for ligne in open(chemin):
        ligne = ligne.strip()
        if ligne and not ligne.startswith("#") and "=" in ligne:
            k, v = ligne.split("=", 1)
            d[k] = v
    return d


def demarrer(e, service, iid, compose):
    n = e.setdefault("compteur", 0) + 1
    e["compteur"] = n
    e["conteneurs"][service] = {"id": f"c{n}-{service}", "image": iid, "running": True, "compose": compose,
                                "config_image": e["images"][iid]["tags"][0] if e["images"][iid]["tags"] else iid}


def compose(e, args):
    opts, pos = options(args, {"-p", "--env-file", "-f"})
    fichier = opts["-f"][0]
    env = {}
    for f in opts.get("--env-file", []):
        env.update(lire_env(f))
    dev = fichier.endswith("docker-compose.dev.yml")

    def image_service(service):
        if dev:
            ref = env.get("BOUSSOLE_WEB_IMAGE" if service == "web" else "BOUSSOLE_API_IMAGE")
        else:
            ref = "boussole-web" if service == "web" else "pkp-api:latest"
        iid = image_id(e, ref or "")
        if iid is None:
            sys.exit(f"faux docker compose : image absente {ref}")
        return iid

    cmd = pos[0]
    if cmd == "run":
        _, rpos = options(pos[1:], set())
        rpos = [a for a in rpos if a not in ("--rm", "--no-deps", "-T")]
        service, commande = rpos[0], rpos[1:]
        iid = image_service(service)
        m = meta(e, iid)
        db = e["db"]
        if commande[:2] == ["alembic", "current"]:
            if db["revision"] not in m["revisions"]:
                print(f"FAILED: Can't locate revision identified by '{db['revision']}'", file=sys.stderr)
                sys.exit(1)
            print(db["revision"] + (" (head)" if db["revision"] == m["head"] else ""))
            return
        if commande[:3] == ["alembic", "upgrade", "head"]:
            if m.get("migration_ko"):
                if m.get("rev_partielle"):
                    db["revision"] = m["rev_partielle"]
                    sauver(e)
                print("migration en échec", file=sys.stderr)
                sys.exit(1)
            db["revision"] = m["head"]
            sauver(e)
            return
        if commande[:3] == ["python", "-m", "app.contenu"]:
            if m.get("import_ko"):
                print("import en échec", file=sys.stderr)
                sys.exit(1)
            simulation = "--simulation" in commande
            if m.get("import_modifie") and db["empreinte"] != m["import_modifie"]:
                if not simulation:
                    db["empreinte"] = m["import_modifie"]
                    sauver(e)
                print(("[simulation] " if simulation else "") + "Créés   : 1 questions")
            else:
                print(("[simulation] " if simulation else "") + "Aucun changement : la base est à jour.")
            return
        sys.exit(f"faux docker compose run : commande inconnue {commande}")
    if cmd == "up":
        services = [a for a in pos[1:] if not a.startswith("-")]
        for s in services:
            demarrer(e, s, image_service(s), fichier)
        sauver(e)
        return
    sys.exit(f"faux docker compose : sous-commande inconnue {cmd}")


def api_saine(e):
    c = e["conteneurs"].get("api")
    return bool(c and c["running"] and not meta(e, c["image"]).get("cassee"))


def main():
    args = sys.argv[1:]
    e = charger()
    ligne = " ".join(args)
    e.setdefault("appels", []).append(ligne)
    if e.get("tuer_si") and e["tuer_si"] in ligne:
        e["tuer_si"] = None
        sauver(e)
        os.killpg(os.getpgid(0), signal.SIGKILL)
    sauver(e)
    cmd = args[0]

    if cmd == "compose":
        return compose(e, args[1:])

    if cmd == "ps":
        _, pos = options(args[1:], {"--filter"})
        opts, _ = options(args[1:], {"--filter"})
        service = [f.rsplit("=", 1)[1] for f in opts.get("--filter", []) if "service=" in f][0]
        c = e["conteneurs"].get(service)
        if c:
            print(c["id"])
        return

    if cmd == "inspect":
        modele, cible = args[args.index("-f") + 1], args[-1]
        s, c = conteneur_par_id(e, cible)
        if c is None:
            # Docker 29 (image store containerd) écrit une ligne vide sur la sortie standard avant l'erreur
            # « No such container » : boussole-dev-sync ne doit pas confondre cette sortie avec un identifiant.
            print()
            sys.exit(1)  # pas un conteneur (image) : boussole-dev-sync se rabat sur la référence
        if ".State.Running" in modele:
            print("true" if c["running"] else "false")
        elif ".State.Status" in modele:
            print(("running " if c["running"] else "exited ") + c["config_image"])
        elif "config_files" in modele:
            print(c["compose"])
        elif '"image":' in modele:
            print(json.dumps({"image": c["config_image"], "id_image": c["image"], "demarre": "2026-11-10T20:00:00Z",
                              "montages": f"boussole_{s}:/data "}))
        elif "{{.Image}}" in modele:
            print(c["image"])
        else:
            sys.exit(f"faux docker inspect : modèle inconnu {modele}")
        return

    if cmd == "image":
        if args[1] == "inspect":
            iid = image_id(e, args[-1])
            if iid is None:
                sys.exit(1)
            modele = args[args.index("-f") + 1]
            if ".Id" in modele:
                print(iid)
            elif ".Created" in modele:
                print(e["images"][iid].get("cree", "2026-11-12T00:00:00.000000000Z"))
            else:
                print(json.dumps(e["images"][iid]["digests"]))
            return
        if args[1] == "prune":
            return
    if cmd == "tag":
        iid = image_id(e, args[1])
        if iid is None:
            sys.exit(1)
        for im in e["images"].values():
            if args[2] in im["tags"]:
                im["tags"].remove(args[2])
        e["images"][iid]["tags"].append(args[2])
        sauver(e)
        return
    if cmd == "login":
        sys.stdin.read()
        print("Login Succeeded")
        return
    if cmd == "pull":
        ref = args[-1]
        if ref not in e["registre"]:
            sys.exit(f"pull : {ref} introuvable")
        if image_id(e, ref) is None:
            e["images"]["img-" + ref.rsplit(":", 1)[-1][:12]] = {"tags": [], "digests": [ref], "meta": e["registre"][ref]}
            sauver(e)
        return
    if cmd == "stop":
        s, c = conteneur_par_id(e, args[-1])
        c["running"] = False
        sauver(e)
        return
    if cmd == "volume":
        vols = e.setdefault("volumes_temporaires", [])
        if args[1] == "create":
            vols.append(args[2])
        elif args[1] == "rm":
            if args[2] not in vols:
                sys.exit(f"volume rm : {args[2]} n'est pas un volume temporaire du banc")
            vols.remove(args[2])
        sauver(e)
        return
    if cmd == "run" and "-d" in args and args[args.index("--name") + 1].startswith("boussole-controle-web-"):
        nom = args[args.index("--name") + 1]
        if "-p" in args or "--publish" in args:
            sys.exit("faux docker : le conteneur de contrôle ne doit publier aucun port")
        iid = image_id(e, args[-1])
        if iid is None:
            sys.exit(1)
        e.setdefault("controles", {})[nom] = {"image": iid}
        sauver(e)
        print(nom)
        return
    if cmd == "run" and "-d" in args:   # base temporaire de restauration
        nom = args[args.index("--name") + 1]
        e.setdefault("restaurations", {})[nom] = {"revision": None, "empreinte": None}
        sauver(e)
        print(nom)
        return
    if cmd == "rm":
        e.get("restaurations", {}).pop(args[-1], None)
        e.get("controles", {}).pop(args[-1], None)
        sauver(e)
        return
    if cmd == "exec":
        pos = [a for a in args[1:] if not a.startswith("-")]
        cid, commande = pos[0], args[args.index(pos[0]) + 1:]
        if cid in e.get("controles", {}):   # front de contrôle (Caddy) : page et fichiers servis, /api relayé
            url = commande[-1]
            web_ok = not meta(e, e["controles"][cid]["image"]).get("cassee")
            if url.endswith("/api/health"):
                if api_saine(e):
                    print('{"status":"ok"}')
                    return
                sys.exit(1)
            if not web_ok:
                sys.exit(1)
            if url.endswith("/"):
                print('<!doctype html><script type="module" src="/assets/index-abc123.js"></script>')
            return
        s_api, c_api = conteneur_par_id(e, cid)
        if s_api == "api" and commande[0] == "python":   # /health interne de l'API
            if api_saine(e):
                print('{"status":"ok"}')
                return
            sys.exit(1)
        if cid in e.get("restaurations", {}):   # base temporaire
            r = e["restaurations"][cid]
            if commande[0] == "pg_isready":
                return
            if commande[0] == "pg_restore":
                contenu = sys.stdin.read()
                r.update(dict(x.split("=", 1) for x in contenu.split()[1:]))
                sauver(e)
                return
            if commande[0] == "psql":
                sql = commande[-1]
                print(r["revision"] if "alembic_version" in sql else r["empreinte"] if "chapitre:" in sql else "3")
                return
        db = e["db"]
        if commande[0] == "psql":
            sql = commande[-1]
            if e.get("db_ko"):
                sys.exit(2)
            if "alembic_version" in sql:
                print(db["revision"])
            elif "chapitre:" in sql:
                print(db["empreinte"])
            else:
                sys.exit(f"faux psql : requête inconnue {sql}")
            return
        if commande[0] == "pg_dump":
            if e.get("dump_ko"):
                sys.exit(1)
            sys.stdout.write(f"PGDMP revision={db['revision']} empreinte={db['empreinte']}\n")
            return
        if commande[0] == "pg_restore":
            sys.stdin.read()
            if e.get("restore_ko"):
                sys.exit(1)
            print(";  Archive created")
            return
    if cmd == "run" and "tar" in args:
        tampon = io.BytesIO()
        with tarfile.open(fileobj=tampon, mode="w:gz") as t:
            donnees = b"pdf de test"
            info = tarfile.TarInfo("./ressource.pdf")
            info.size = len(donnees)
            t.addfile(info, io.BytesIO(donnees))
        sys.stdout.buffer.write(tampon.getvalue())
        return
    sys.exit(f"faux docker : commande non simulée {args}")


if __name__ == "__main__":
    main()
