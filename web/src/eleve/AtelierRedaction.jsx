// Issue #231 — Atelier de rédaction de l'écran de cours (Claude)
//
// Maquette 9 de la refonte : la consigne en grand, l'état réel de la rédaction en ligne, les critères de réussite du
// cours en liste à cocher, « Relire et réécrire » à côté. Fermée (PKP_REDACTION_ACTIVE faux, RGPD-2) : l'élève lit
// la consigne et rédige sur sa copie ; aucun champ de saisie, rien n'est enregistré, ni sur le serveur ni sur le poste.
// Ouverte : l'éditeur existant de #179 (brouillon, remise, retour de la professeure, réécriture).
import { useCallback, useEffect, useId, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";
import { Maths } from "../maths.jsx";
import { EditeurRedaction, FERMEE, RAPPEL } from "./Redaction.jsx";

/** Critères de réussite : les lignes « - … » de la partie « Mes critères de réussite » du cours. */
export function criteresDuCours(parties) {
  return (parties ?? [])
    .flatMap((p) => (p.texte ?? "").split("\n"))
    .map((l) => l.match(/^\s*[-*]\s+(.+)$/)?.[1]?.trim())
    .filter(Boolean);
}

function Consigne({ enonce }) {
  return (
    <div className="consigne-redaction">
      <p className="consigne-titre">Consigne</p>
      {enonce.split(/\n\s*\n/).map((p, i) => (
        <p key={i} className="consigne-texte">{p}</p>
      ))}
    </div>
  );
}

/** Liste à cocher pour se relire : un outil pour l'élève, l'état n'est gardé que pendant la visite. */
function Criteres({ parties }) {
  const id = useId();
  const [coches, setCoches] = useState(() => new Set());
  const criteres = criteresDuCours(parties);
  if (criteres.length === 0) {
    // Critères rédigés sans liste : le texte du cours, tel quel.
    const textes = (parties ?? []).filter((p) => p.texte);
    if (textes.length === 0) return null;
    return (
      <section className="atelier-bloc" aria-labelledby={`${id}-criteres`}>
        <h3 id={`${id}-criteres`}>Mes critères de réussite</h3>
        {textes.map((p, i) => <Maths key={i} texte={p.texte} />)}
      </section>
    );
  }
  const basculer = (i) =>
    setCoches((c) => {
      const n = new Set(c);
      if (n.has(i)) n.delete(i);
      else n.add(i);
      return n;
    });
  return (
    <section className="atelier-bloc" aria-labelledby={`${id}-criteres`}>
      <h3 id={`${id}-criteres`}>Mes critères de réussite</h3>
      <p className="doux petit">Coche chaque critère quand tu l'as vérifié en te relisant.</p>
      <ul className="criteres-reussite">
        {criteres.map((c, i) => (
          <li key={i}>
            <label>
              <input type="checkbox" checked={coches.has(i)} onChange={() => basculer(i)} />
              <span><Maths enLigne texte={c} /></span>
            </label>
          </li>
        ))}
      </ul>
      <p className="doux petit" role="status">
        {coches.size} critère{coches.size > 1 ? "s" : ""} vérifié{coches.size > 1 ? "s" : ""} sur {criteres.length}
      </p>
    </section>
  );
}

export default function AtelierRedaction({ jeton, onExpire, competenceId, criteres = [], relire = [] }) {
  // `criteres` et `relire` : parties du cours (étapes 3 et 5) déjà découpées par l'écran de cours.
  const [donnees, setDonnees] = useState(null);
  const [erreur, setErreur] = useState(null);
  const echec = useCallback((err) => (err.status === 401 ? onExpire?.() : setErreur(err.message)), [onExpire]);

  useEffect(() => {
    let actif = true;
    api(`/francais/eleve/redaction/${competenceId}`, { jeton }).then((d) => actif && setDonnees(d), (e) => actif && echec(e));
    return () => {
      actif = false;
    };
  }, [competenceId, jeton, echec]);

  return (
    <div className="atelier-redaction">
      <div className="atelier-principal">
        <Erreur message={erreur} />
        {!donnees && !erreur && <p className="doux">Chargement du sujet…</p>}
        {donnees && donnees.sujets.length === 0 && (
          <p className="doux">Pas encore de sujet de rédaction ouvert pour ce cours.</p>
        )}
        {donnees?.sujets.map((s) => (
          <article key={s.question_id} className="sujet-redaction">
            <Consigne enonce={s.enonce} />
            <p className="aide petit" role="note">{RAPPEL}</p>
            {donnees.ouverte ? (
              <EditeurRedaction questionId={s.question_id} jeton={jeton} echec={echec} />
            ) : (
              <div className="etat-ferme" role="note">
                <span className="etat-ferme-icone" aria-hidden="true">✎</span>
                <p>
                  <strong>{FERMEE}</strong> Rédige sur ta copie, puis remets-la à ta professeure : elle te rendra ses
                  remarques et tu pourras réécrire ton texte.
                </p>
              </div>
            )}
          </article>
        ))}
      </div>
      <aside className="atelier-cote" aria-label="Pour t'aider à écrire">
        <Criteres parties={criteres} />
        {relire?.length > 0 && (
          <section className="atelier-bloc">
            <h3>Relire et réécrire</h3>
            {relire.map((p, i) => p.texte && <Maths key={i} texte={p.texte} />)}
          </section>
        )}
      </aside>
    </div>
  );
}
