// Issue #179 — Rédaction en ligne et correction par le professeur (Claude)
//
// Rédactions remises par les élèves d'une classe de français ; le professeur lit le texte et le guide du sujet, puis
// écrit son commentaire. Les brouillons des élèves ne lui sont jamais montrés.
//
// Issue #231 (refonte Français) : fermeture présentée comme un état ; remises « À corriger » d'abord, puis
// « Corrigées » ; correction en deux colonnes (texte de l'élève en police de lecture, guide et commentaire à côté),
// passage direct à la remise suivante. Mêmes routes et mêmes règles d'accès (RGPD-2).
import { useCallback, useEffect, useState } from "react";
import { Erreur } from "../composants.jsx";
import { formaterDate } from "../ui/Cadre.jsx";
import { useApi } from "./useApi.js";

const STATUTS = { remise: "À corriger", corrigee: "Corrigée" };
export const PLAN_COMMENTAIRE = "Ce qui est réussi : \n\nPour ta réécriture : ";
const extrait = (texte, n = 90) => (texte.length > n ? `${texte.slice(0, n).trimEnd()}…` : texte);
const nbMots = (texte) => (texte.trim() ? texte.trim().split(/\s+/).length : 0);

export default function Redactions({ jeton, onExpire }) {
  const { appeler, erreur, setErreur } = useApi(jeton, onExpire);
  const [classes, setClasses] = useState(null);
  const [classe, setClasse] = useState("");
  const [liste, setListe] = useState(null);
  const [ouverte, setOuverte] = useState(null);
  const [fermee, setFermee] = useState(false);

  useEffect(() => {
    appeler("/enseignants/classes").then((l) => {
      const fr = l.filter((c) => c.matiere === "francais");
      setClasses(fr);
      if (fr.length === 1) setClasse(String(fr[0].id));
    }, () => {});
  }, [appeler]);
  const charger = useCallback(() => {
    if (!classe) return Promise.resolve([]);
    return appeler(`/enseignants/classes/${classe}/redactions`).then(
      (l) => {
        setListe(l);
        return l;
      },
      (err) => {
        // Rédaction en ligne fermée (RGPD-2) : un état expliqué, pas une erreur.
        if (err.status === 403) {
          setFermee(true);
          setErreur(null);
        }
        return [];
      },
    );
  }, [appeler, classe, setErreur]);
  useEffect(() => {
    setListe(null);
    charger();
  }, [charger]);

  if (ouverte) {
    return (
      <Correction
        id={ouverte}
        appeler={appeler}
        erreur={erreur}
        onRetour={() => {
          setOuverte(null);
          charger();
        }}
        onSuivante={async () => {
          const l = await charger();
          const suivante = l.find((r) => r.statut === "remise" && r.id !== ouverte);
          setOuverte(suivante ? suivante.id : null);
        }}
      />
    );
  }
  const aCorriger = (liste ?? []).filter((r) => r.statut === "remise");
  const corrigees = (liste ?? []).filter((r) => r.statut !== "remise");
  return (
    <section className="carte" aria-label="Rédactions remises">
      {fermee ? (
        <p className="info" role="note">
          La rédaction en ligne n'est pas encore ouverte : les élèves rédigent sur leur copie et vous la remettent. Les
          rédactions remises en ligne apparaîtront ici dès son ouverture.
        </p>
      ) : (
        <>
          <Erreur message={erreur} />
          {classes === null ? (
            <p className="doux">Chargement…</p>
          ) : classes.length === 0 ? (
            <p className="doux">Aucune classe de français.</p>
          ) : (
            <label>
              Classe
              <select value={classe} onChange={(e) => setClasse(e.target.value)}>
                <option value="">Choisir…</option>
                {classes.map((c) => <option key={c.id} value={c.id}>{c.code}</option>)}
              </select>
            </label>
          )}
          {liste && (liste.length === 0 ? (
            <p className="doux">Aucune rédaction remise pour l'instant.</p>
          ) : (
            <>
              <ListeRemises titre="À corriger" lignes={aCorriger} onOuvrir={setOuverte} vide="Tout est corrigé." />
              <ListeRemises titre="Corrigées" lignes={corrigees} onOuvrir={setOuverte} vide="Aucune pour l'instant." />
            </>
          ))}
        </>
      )}
    </section>
  );
}

function ListeRemises({ titre, lignes, onOuvrir, vide }) {
  return (
    <section className="remises" aria-label={titre}>
      <h3>{titre} <span className="doux petit">({lignes.length})</span></h3>
      {lignes.length === 0 ? (
        <p className="doux petit">{vide}</p>
      ) : (
        <ul className="liste-redactions">
          {lignes.map((r) => (
            <li key={r.id}>
              <button type="button" className="remise" onClick={() => onOuvrir(r.id)}>
                <strong>{r.eleve} — version {r.version}</strong>
                <span className="doux petit">{extrait(r.sujet)}</span>
                <span className="doux petit">
                  {r.remise_le ? `Remise le ${formaterDate(r.remise_le)}` : "Remise"}
                  {r.corrigee_le ? ` · corrigée le ${formaterDate(r.corrigee_le)}` : ""}
                </span>
              </button>
              <span className={`badge ${r.statut === "remise" ? "alerte" : "ok"}`}>{STATUTS[r.statut]}</span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function Correction({ id, appeler, erreur, onRetour, onSuivante }) {
  const [r, setR] = useState(null);
  const [commentaire, setCommentaire] = useState("");
  const [message, setMessage] = useState(null);
  const [verifies, setVerifies] = useState(() => new Set());
  useEffect(() => {
    setR(null);
    setMessage(null);
    setVerifies(new Set());
    appeler(`/enseignants/redactions/${id}`).then((x) => { setR(x); setCommentaire(x.commentaire ?? ""); }, () => {});
  }, [appeler, id]);

  async function envoyer(e) {
    e.preventDefault();
    setMessage(null);
    try {
      setR(await appeler(`/enseignants/redactions/${id}/correction`, { methode: "POST", corps: { commentaire } }));
      setMessage("Correction envoyée à l'élève.");
    } catch {
      // erreur déjà affichée
    }
  }

  const basculer = (i) =>
    setVerifies((v) => {
      const n = new Set(v);
      if (n.has(i)) n.delete(i);
      else n.add(i);
      return n;
    });

  if (!r) return <p className="doux">Chargement…</p>;
  const etapes = r.correction?.etapes ?? [];
  return (
    <section className="carte correction-redaction" aria-labelledby="titre-correction">
      <button type="button" className="lien" onClick={onRetour}>← Toutes les rédactions</button>
      <div className="correction-entete">
        <h2 id="titre-correction">{r.eleve} — version {r.version}</h2>
        <span className={`badge ${r.statut === "remise" ? "alerte" : "ok"}`}>{STATUTS[r.statut]}</span>
      </div>
      <div className="correction-grille">
        <div className="correction-texte">
          <details className="sujet-rappel">
            <summary>Sujet</summary>
            {r.sujet.split(/\n\s*\n/).map((p, i) => <p key={i}>{p}</p>)}
          </details>
          <article className="copie-eleve" aria-label="Texte de l'élève">
            {r.texte.split(/\n\s*\n/).map((p, i) => <p key={i}>{p}</p>)}
          </article>
          <p className="doux petit">
            {nbMots(r.texte)} mots · {r.texte.split(/\n\s*\n/).filter((p) => p.trim()).length} paragraphe(s)
            {r.remise_le ? ` · remise le ${formaterDate(r.remise_le)}` : ""}
          </p>
        </div>
        <aside className="correction-cote" aria-label="Guide et commentaire">
          <section className="atelier-bloc">
            <h3>Guide de correction</h3>
            {r.correction?.methode && <p className="doux petit">{r.correction.methode}</p>}
            {etapes.length > 0 ? (
              <ul className="criteres-reussite">
                {etapes.map((e, i) => (
                  <li key={i}>
                    <label>
                      <input type="checkbox" checked={verifies.has(i)} onChange={() => basculer(i)} />
                      <span>{e}</span>
                    </label>
                  </li>
                ))}
              </ul>
            ) : null}
            {r.guide && <p className="petit"><strong>Attendus :</strong> {r.guide}</p>}
          </section>
          {message && <p className="succes" role="status">{message}</p>}
          <Erreur message={erreur} />
          <form onSubmit={envoyer} className="commentaire-redaction">
            <label htmlFor="commentaire-redaction">Commentaire pour l'élève</label>
            <textarea
              id="commentaire-redaction"
              rows={9}
              maxLength={10000}
              value={commentaire}
              placeholder="Une réussite, puis une piste de réécriture."
              onChange={(e) => setCommentaire(e.target.value)}
            />
            <div className="actions">
              {!commentaire.trim() && (
                <button type="button" className="secondaire" onClick={() => setCommentaire(PLAN_COMMENTAIRE)}>
                  Partir du plan « réussite, piste »
                </button>
              )}
              <button type="submit" disabled={!commentaire.trim()}>Envoyer la correction</button>
              {message && (
                <button type="button" className="secondaire" onClick={onSuivante}>Rédaction suivante →</button>
              )}
            </div>
          </form>
        </aside>
      </div>
    </section>
  );
}
