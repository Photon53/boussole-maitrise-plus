// Issue #179 — Rédaction en ligne et correction par le professeur (Claude)
//
// L'élève choisit un sujet, écrit, enregistre son brouillon, puis le remet ; il lit ensuite le commentaire de son
// professeur et peut réécrire dans une nouvelle version. Fermé tant que la rédaction en ligne n'est pas ouverte (403).
import { useCallback, useEffect, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";

const STATUTS = { brouillon: "Brouillon", remise: "Remise, en attente de correction", corrigee: "Corrigée" };
export const FERMEE = "La rédaction en ligne n'est pas encore ouverte.";
export const RAPPEL =
  "N'écris ni ton adresse, ni tes coordonnées, ni d'informations intimes sur toi ou sur d'autres personnes : " +
  "préfère des personnages et des lieux imaginaires.";

export default function Redaction({ jeton, onExpire }) {
  const [sujets, setSujets] = useState(null);
  const [ouvert, setOuvert] = useState(null);
  const [erreur, setErreur] = useState(null);
  const [fermee, setFermee] = useState(false);

  const echec = useCallback((err) => {
    if (err.status === 401 && onExpire) onExpire();
    else if (err.status === 403) setFermee(true);
    else setErreur(err.message);
  }, [onExpire]);
  const charger = useCallback(() => api("/eleves/moi/redactions", { jeton }).then(setSujets, echec), [jeton, echec]);
  useEffect(() => {
    charger();
  }, [charger]);

  if (ouvert)
    return <Sujet questionId={ouvert} jeton={jeton} echec={echec} onRetour={() => { setOuvert(null); charger(); }} />;
  if (fermee) {
    return (
      <section className="carte" aria-labelledby="titre-redaction">
        <h2 id="titre-redaction">Rédaction</h2>
        <p className="info" role="note">
          {FERMEE} Les sujets sont dans « Mes cours », rubrique Rédaction : rédige sur ta copie et remets-la à ta
          professeure.
        </p>
      </section>
    );
  }
  if (erreur) return <Erreur message={erreur} />;
  if (!sujets) return <p className="doux">Chargement des sujets…</p>;
  return (
    <section className="carte" aria-labelledby="titre-redaction">
      <h2 id="titre-redaction">Rédaction</h2>
      {sujets.length === 0 ? (
        <p className="doux">Pas encore de sujet de rédaction ouvert par ta professeure.</p>
      ) : (
        <ul className="liste-sujets">
          {sujets.map((s) => (
            <li key={s.question_id}>
              <button className="lien" onClick={() => setOuvert(s.question_id)}>{s.chapitre} — {s.competence}</button>{" "}
              <span className="doux petit">{s.statut ? STATUTS[s.statut] : "À écrire"}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Sujet({ questionId, jeton, echec, onRetour }) {
  const [enonce, setEnonce] = useState(null);
  return (
    <section className="carte" aria-labelledby="titre-sujet">
      <button className="lien" onClick={onRetour}>← Tous les sujets</button>
      <h2 id="titre-sujet">Sujet</h2>
      {enonce && <p>{enonce}</p>}
      <p className="aide" role="note">{RAPPEL}</p>
      <EditeurRedaction questionId={questionId} jeton={jeton} echec={echec} onCharge={(d) => setEnonce(d.enonce)} />
    </section>
  );
}

/** Nombre de mots et de paragraphes d'un texte : un repère pour l'élève, jamais une note. */
export function compter(texte) {
  const mots = texte.trim() ? texte.trim().split(/\s+/).length : 0;
  const paragraphes = texte.split(/\n\s*\n/).filter((p) => p.trim()).length;
  return { mots, paragraphes };
}

/**
 * Brouillon, remise, versions corrigées et réécriture d'un sujet (#179). Partagé par la liste des sujets et par
 * l'atelier de rédaction de l'écran de cours (#231). Ne s'affiche que si la rédaction en ligne est ouverte.
 */
export function EditeurRedaction({ questionId, jeton, echec, onCharge }) {
  const [detail, setDetail] = useState(null);
  const [texte, setTexte] = useState("");
  const [message, setMessage] = useState(null);
  const [erreur, setErreur] = useState(null);

  const recevoir = useCallback((d) => {
    setDetail(d);
    const derniere = d.versions.at(-1);
    setTexte(derniere?.statut === "brouillon" ? derniere.texte : "");
  }, []);
  useEffect(() => {
    api(`/eleves/moi/redactions/${questionId}`, { jeton }).then((d) => {
      recevoir(d);
      onCharge?.(d);
    }, echec);
    // onCharge n'est appelé qu'au chargement.
  }, [questionId, jeton, recevoir, echec]);

  async function envoyer(remettre) {
    setMessage(null);
    setErreur(null);
    try {
      let d = await api(`/eleves/moi/redactions/${questionId}`, { jeton, methode: "PUT", corps: { texte } });
      if (remettre) d = await api(`/eleves/moi/redactions/${questionId}/remise`, { jeton, methode: "POST" });
      recevoir(d);
      setMessage(remettre ? "Rédaction remise à ta professeure." : "Brouillon enregistré.");
    } catch (err) {
      if (err.status === 401) echec(err);
      else setErreur(err.message);
    }
  }

  if (!detail) return <p className="doux">Chargement…</p>;
  const derniere = detail.versions.at(-1);
  const enAttente = derniere?.statut === "remise";
  const { mots, paragraphes } = compter(texte);
  return (
    <div className="editeur-redaction">
      {message && <p className="succes" role="status">{message}</p>}
      <Erreur message={erreur} />
      {enAttente ? (
        <p className="info">Ta rédaction est remise : ta professeure va la corriger.</p>
      ) : (
        <>
          <label htmlFor={`texte-redaction-${questionId}`}>
            {derniere?.statut === "corrigee" ? `Réécriture (version ${derniere.version + 1})` : "Ta rédaction"}
          </label>
          <textarea
            id={`texte-redaction-${questionId}`}
            className="texte-a-ecrire"
            rows={14}
            maxLength={10000}
            value={texte}
            onChange={(e) => setTexte(e.target.value)}
            aria-describedby={`compteur-${questionId}`}
          />
          <p id={`compteur-${questionId}`} className="doux petit compteur-redaction">
            {mots} mot{mots > 1 ? "s" : ""} · {paragraphes} paragraphe{paragraphes > 1 ? "s" : ""} · saute une ligne entre deux paragraphes
          </p>
          <div className="actions">
            <button className="secondaire" disabled={!texte.trim()} onClick={() => envoyer(false)}>Enregistrer le brouillon</button>
            <button disabled={!texte.trim()} onClick={() => envoyer(true)}>Remettre à ma professeure</button>
          </div>
        </>
      )}
      {detail.versions.filter((v) => v.statut !== "brouillon").reverse().map((v) => (
        <article key={v.id} className="encadre version-redaction">
          <strong>Version {v.version} — {STATUTS[v.statut]}</strong>
          <p className="texte-redaction">{v.texte}</p>
          {v.commentaire && (
            <div className="retour-professeure">
              <strong>Retour de ta professeure</strong>
              <p>{v.commentaire}</p>
            </div>
          )}
        </article>
      ))}
      {detail.conserver_jusqu_au && (
        <p className="doux petit">Tes rédactions sont conservées jusqu'au {new Date(detail.conserver_jusqu_au).toLocaleDateString("fr-FR")}, puis supprimées.</p>
      )}
    </div>
  );
}
