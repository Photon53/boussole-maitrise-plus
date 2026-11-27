// Issue #231 — Atelier de rédaction de l'écran de cours (Claude)
//
// Maquette 9 de la refonte : la consigne en grand, l'état réel de la rédaction en ligne, les critères de réussite du
// cours en liste à cocher, « Relire et réécrire » à côté. Fermée (PKP_REDACTION_ACTIVE faux, RGPD-2) : l'élève lit
// la consigne, prépare son brouillon **sur cet appareil seulement** (durée réglée sur le serveur, 10 jours par défaut,
// décision du propriétaire du 27/11/2026, voir brouillonLocal.js) et le recopie sur sa copie ; rien n'est envoyé au serveur. Sans identifiant
// d'élève (simulation par un adulte) ou avec une durée nulle, pas de brouillon.
// Ouverte : l'éditeur existant de #179 (brouillon, remise, retour de la professeure, réécriture).
import { useCallback, useEffect, useId, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";
import { Maths } from "../maths.jsx";
import { ecrireBrouillon, effacerBrouillon, lireBrouillon, purgerBrouillons } from "./brouillonLocal.js";
import { compter, EditeurRedaction, FERMEE, RAPPEL } from "./Redaction.jsx";

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

const dateCourte = (ms) => new Date(ms).toLocaleDateString("fr-FR", { day: "numeric", month: "long" });

/** Brouillon gardé sur l'appareil quand la rédaction en ligne est fermée : enregistré à chaque frappe (après une
 * courte pause), effacé `jours` jours après la dernière modification, ou tout de suite par l'élève. */
function BrouillonLocal({ eleveId, questionId, jours }) {
  const [texte, setTexte] = useState(() => {
    purgerBrouillons(jours);
    return lireBrouillon(eleveId, questionId, jours)?.texte ?? "";
  });
  const [entree, setEntree] = useState(() => lireBrouillon(eleveId, questionId, jours));

  useEffect(() => {
    const minuteur = setTimeout(() => {
      if (texte === (entree?.texte ?? "")) return;
      setEntree(ecrireBrouillon(eleveId, questionId, texte, jours));
    }, 600);
    return () => clearTimeout(minuteur);
  }, [texte, entree, eleveId, questionId, jours]);

  function effacer() {
    effacerBrouillon(eleveId, questionId);
    setEntree(null);
    setTexte("");
  }

  const { mots, paragraphes } = compter(texte);
  const id = `brouillon-local-${questionId}`;
  return (
    <div className="editeur-redaction">
      <div className="entete-brouillon">
        <label htmlFor={id}>Mon brouillon</label>
        <span className="doux petit" role="status">
          {entree ? `Enregistré sur cet appareil seulement, jusqu'au ${dateCourte(entree.expire_le)}` : `Gardé ${jours} jour${jours > 1 ? "s" : ""} sur cet appareil seulement`}
        </span>
      </div>
      <textarea
        id={id}
        className="texte-a-ecrire"
        rows={14}
        maxLength={10000}
        value={texte}
        onChange={(e) => setTexte(e.target.value)}
        aria-describedby={`compteur-local-${questionId}`}
      />
      <p id={`compteur-local-${questionId}`} className="doux petit compteur-redaction">
        {mots} mot{mots > 1 ? "s" : ""} · {paragraphes} paragraphe{paragraphes > 1 ? "s" : ""} · saute une ligne entre deux paragraphes
      </p>
      {texte && (
        <div className="actions">
          <button type="button" className="secondaire" onClick={effacer}>Effacer mon brouillon</button>
        </div>
      )}
    </div>
  );
}

export default function AtelierRedaction({ jeton, onExpire, competenceId, eleveId = null, criteres = [], relire = [] }) {
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

  const brouillon = Boolean(eleveId) && donnees?.brouillon_jours > 0;
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
              <>
                <div className="etat-ferme" role="note">
                  <span className="etat-ferme-icone" aria-hidden="true">✎</span>
                  <p>
                    <strong>{FERMEE}</strong>{" "}
                    {brouillon
                      ? "Tu peux préparer ton brouillon ci-dessous : ta professeure ne le voit pas. Recopie-le sur ta copie et remets-la-lui : elle te rendra ses remarques et tu pourras réécrire ton texte."
                      : "Rédige sur ta copie, puis remets-la à ta professeure : elle te rendra ses remarques et tu pourras réécrire ton texte."}
                  </p>
                </div>
                {brouillon && <BrouillonLocal eleveId={eleveId} questionId={s.question_id} jours={donnees.brouillon_jours} />}
              </>
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
