// Issue #231 — Présentation de l'exercice et de la correction expliquée en français (Claude)
//
// Maquettes 4, 5 et 7 de la refonte : la phrase étudiée mise en scène, un clavier d'accents, une correction qui
// montre la méthode et ses étapes sans les cacher. Présentation seulement : le tirage des questions, la correction et
// la maîtrise restent ceux du moteur ; la solution n'arrive qu'avec le résultat, après la réponse (ARCH-4).
import { Maths } from "../maths.jsx";
import { solutionLisible } from "../composants.jsx";

export const ACCENTS = ["é", "è", "ê", "ë", "à", "â", "î", "ï", "ô", "ù", "û", "ç", "œ"];

/**
 * Sépare la consigne de la phrase étudiée : « Conjugue le verbe… « Elles (finir) leur repas. » ».
 * La phrase est le premier passage entre guillemets français ; sans guillemets, tout reste dans la consigne.
 */
export function decouperEnonce(texte) {
  const m = texte.match(/«\s*([^»]*?[^»\s])\s*»/);
  if (!m) return { consigne: texte, phrase: null, apres: "" };
  const consigne = texte.slice(0, m.index).replace(/[:\s]+$/, "").trim();
  const apres = texte.slice(m.index + m[0].length).trim();
  return { consigne, phrase: m[1], apres };
}

/** Phrase étudiée ; le verbe à conjuguer, entre parenthèses, est souligné. */
function Phrase({ texte }) {
  const morceaux = texte.split(/(\([^)]+\))/);
  return (
    <p className="phrase-exercice">
      {morceaux.map((m, i) => (/^\(.+\)$/.test(m) ? <span key={i} className="cible">{m}</span> : <span key={i}>{m}</span>))}
    </p>
  );
}

export function EnonceFrancais({ intitule }) {
  const { consigne, phrase, apres } = decouperEnonce(intitule);
  if (!phrase) {
    return (
      <p className="enonce">
        <Maths enLigne texte={intitule} />
      </p>
    );
  }
  return (
    <div className="enonce-francais">
      {consigne && <p className="consigne-exercice">{consigne}</p>}
      <Phrase texte={phrase} />
      {apres && apres !== "?" && <p className="consigne-exercice">{apres}</p>}
    </div>
  );
}

/** Lettres accentuées insérées à la place du curseur ; le focus reste dans le champ. */
export function ClavierAccents({ champ, valeur, onChange, desactive }) {
  function inserer(lettre) {
    const el = champ.current;
    const debut = el?.selectionStart ?? valeur.length;
    const fin = el?.selectionEnd ?? valeur.length;
    onChange(valeur.slice(0, debut) + lettre + valeur.slice(fin));
    requestAnimationFrame(() => {
      el?.focus();
      el?.setSelectionRange(debut + lettre.length, debut + lettre.length);
    });
  }
  return (
    <div className="clavier-accents" role="group" aria-label="Lettres accentuées">
      {ACCENTS.map((l) => (
        <button key={l} type="button" className="secondaire" disabled={desactive} onClick={() => inserer(l)} aria-label={`Insérer ${l}`}>
          {l}
        </button>
      ))}
    </div>
  );
}

/** Libellé lisible d'une réponse : pour un QCM, la lettre suivie du choix. */
function lisible(question, valeur, options) {
  if (question.type === "qcm" && options) {
    const o = options.find((x) => x.lettre === String(valeur).trim().toUpperCase());
    return o ? `${o.lettre}) ${o.texte}` : valeur;
  }
  return question.type === "texte" ? solutionLisible("texte", valeur) : valeur;
}

/**
 * Correction expliquée : verdict, réponse donnée et attendue, méthode et étapes visibles, erreur fréquente, retour à
 * la leçon. `correction` vient du résultat de la réponse (jamais avant).
 */
export function CorrectionFrancais({ question, options, donnee, resultat, onVoirMethode }) {
  const c = resultat.correction;
  return (
    <div className="correction-francais">
      <div className={`verdict-francais ${resultat.correcte ? "juste" : "a-revoir"}`}>
        <span className="verdict-icone" aria-hidden="true">{resultat.correcte ? "✓" : "↻"}</span>
        <div>
          <p className="verdict-titre">{resultat.correcte ? "Bravo, c'est juste." : "Pas encore : regardons ensemble."}</p>
          {!resultat.correcte && (
            <ul className="reponses-comparees">
              <li><span className="badge alerte">Ta réponse</span> {lisible(question, donnee, options)}</li>
              <li><span className="badge ok">Bonne réponse</span> {lisible(question, resultat.solution, options)}</li>
            </ul>
          )}
        </div>
      </div>
      {c && (c.methode || c.etapes?.length) ? (
        <section className="methode-francais" aria-label="Correction expliquée">
          {c.methode && (
            <p className="surtitre-methode">Méthode : <Maths enLigne texte={c.methode} /></p>
          )}
          {c.etapes?.length > 0 && (
            <ol className="etapes-correction">
              {c.etapes.map((e, i) => (
                <li key={i}><Maths enLigne texte={e} /></li>
              ))}
            </ol>
          )}
          {c.resultat && <p><strong>Résultat :</strong> <Maths enLigne texte={c.resultat} /></p>}
          {c.erreurs_frequentes?.length > 0 && (
            <div className="erreur-frequente">
              <strong>Erreur fréquente</strong>
              <ul>
                {c.erreurs_frequentes.map((e) => <li key={e}><Maths enLigne texte={e} /></li>)}
              </ul>
            </div>
          )}
        </section>
      ) : null}
      {onVoirMethode && (
        <button type="button" className="lien" onClick={onVoirMethode}>
          Revoir la méthode dans la leçon
        </button>
      )}
    </div>
  );
}
