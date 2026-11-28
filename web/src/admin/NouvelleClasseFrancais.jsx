// Issue #231 — Créer une classe de français depuis « Élèves et classes » (Claude)
//
// Le français n'avait pas d'entrée dans « Classes et groupes » : une classe de français ne se créait que depuis la
// configuration, comme classe pilote. Cette fenêtre applique les règles existantes sans les changer :
// - domaine actif mais fermé au public (cas du pilote, SEC-D6) : la classe est une classe pilote, avec motif
//   (route `/admin/classes-pilotes`, la seule qui ouvre un domaine fermé à une classe) ;
// - domaine ouvert au public : classe ordinaire (`/admin/classes`, habilitation du professeur revérifiée) ;
// - domaine inactif : rien n'est créé, l'écran renvoie vers la configuration.
// Les élèves s'ajoutent ensuite avec « Gérer », comme pour une classe de maths.
import { useEffect, useMemo, useState } from "react";
import { Modale } from "../ui/Cadre.jsx";
import { naviguer } from "../navigation.js";

export default function NouvelleClasseFrancais({ appeler, onFermer, onCreee }) {
  const [domaines, setDomaines] = useState(null);
  const [domaine, setDomaine] = useState("");
  const [niveau, setNiveau] = useState("");
  const [professeurs, setProfesseurs] = useState([]);
  const [professeur, setProfesseur] = useState("");
  const [motif, setMotif] = useState("");
  const [erreur, setErreur] = useState(null);
  const [envoi, setEnvoi] = useState(false);

  useEffect(() => {
    appeler("/admin/domaines").then(
      (l) => {
        const fr = l.filter((d) => d.matiere === "francais" && d.actif);
        setDomaines(fr);
        if (fr.length === 1) setDomaine(fr[0].code);
      },
      (err) => setErreur(err.message),
    );
  }, [appeler]);

  const choisi = useMemo(() => domaines?.find((d) => d.code === domaine), [domaines, domaine]);
  const pilote = choisi && !choisi.public;

  useEffect(() => {
    setNiveau("");
    setProfesseur("");
    setProfesseurs([]);
    if (domaine) appeler(`/admin/enseignants?domaine=${encodeURIComponent(domaine)}`).then((l) => setProfesseurs(l.filter((p) => p.actif)), () => {});
  }, [appeler, domaine]);

  async function creer(e) {
    e.preventDefault();
    setErreur(null);
    setEnvoi(true);
    try {
      const corps = { matiere: "francais", niveau, enseignant_id: Number(professeur) };
      const classe = pilote
        ? await appeler("/admin/classes-pilotes", { methode: "POST", corps: { ...corps, motif: motif.trim() } })
        : await appeler("/admin/classes", { methode: "POST", corps: { ...corps, parcours: "tronc-commun" } });
      onCreee({ ...classe, pilote });
    } catch (err) {
      setErreur(err.message);
    } finally {
      setEnvoi(false);
    }
  }

  return (
    <Modale titre="Nouvelle classe de français" onFermer={onFermer}>
      {erreur && <p className="erreur" role="alert">{erreur}</p>}
      {domaines === null && !erreur && <p className="doux">Chargement…</p>}
      {domaines?.length === 0 && (
        <>
          <p className="info" role="note">
            Le français n'est pas activé. Activez « Français collège » dans la configuration (sans l'ouvrir au public pour un
            pilote), puis revenez créer la classe.
          </p>
          <div className="actions">
            <button type="button" onClick={() => naviguer("/admin/configuration")}>Ouvrir la configuration</button>
          </div>
        </>
      )}
      {domaines?.length > 0 && (
        <form onSubmit={creer}>
          {domaines.length > 1 && (
            <>
              <label htmlFor="ncf-domaine">Domaine</label>
              <select id="ncf-domaine" required value={domaine} onChange={(e) => setDomaine(e.target.value)}>
                <option value="">Choisir…</option>
                {domaines.map((d) => <option key={d.code} value={d.code}>{d.libelle}</option>)}
              </select>
            </>
          )}
          {pilote && (
            <p className="info" role="note">
              {choisi.libelle} est encore fermé au public : la classe sera une <strong>classe pilote</strong> (SEC-D6). Seuls ses
              élèves auront accès au français ; vous pourrez la retirer des pilotes à tout moment dans la configuration.
            </p>
          )}
          <label htmlFor="ncf-niveau">Niveau</label>
          <select id="ncf-niveau" required value={niveau} disabled={!choisi} onChange={(e) => setNiveau(e.target.value)}>
            <option value="">Choisir…</option>
            {(choisi?.niveaux ?? []).map((n) => <option key={n} value={n}>{n}</option>)}
          </select>
          <label htmlFor="ncf-prof">Professeur de français</label>
          <select id="ncf-prof" required value={professeur} disabled={!choisi} onChange={(e) => setProfesseur(e.target.value)}>
            <option value="">Choisir…</option>
            {professeurs.map((p) => <option key={p.id} value={p.id}>{p.nom}</option>)}
          </select>
          {choisi && professeurs.length === 0 && (
            <p className="aide">
              Aucun professeur habilité en {choisi.libelle}. Donnez d'abord l'habilitation « professeur » de ce domaine à un compte,
              dans « Équipe ».
            </p>
          )}
          {pilote && (
            <>
              <label htmlFor="ncf-motif">Motif du pilote</label>
              <input id="ncf-motif" required minLength={3} maxLength={200} value={motif} placeholder="Par exemple : pilote de janvier 2027"
                onChange={(e) => setMotif(e.target.value)} />
            </>
          )}
          <div className="actions">
            <button type="submit" disabled={envoi || !niveau || !professeur || (pilote && motif.trim().length < 3)}>
              Créer la classe
            </button>
            <button type="button" className="secondaire" onClick={onFermer}>Annuler</button>
          </div>
        </form>
      )}
    </Modale>
  );
}
