// Issue #231 — Dossier de lecture de l'élève : sept étapes, texte et questions côte à côte (Claude)
//
// Le dossier validé et ouvert à la classe (version élève, sans corrigé, ARCH-4), rangé selon la méthode commune de
// #177 (FR-UI-D2) : objectifs, leçon, quiz, entraînement, transfert, réponses rédigées, « Je sais ». Pendant les
// questions, le texte reste à côté, lignes numérotées dans la marge ; les lignes que cite la question sont repérées.
// Les activités (quiz, réponses rédigées, auto-évaluation) sont les composants existants de #217, inchangés.
import { useMemo, useState } from "react";
import { Maths } from "../maths.jsx";
import RailEtapes, { NavigationEtapes, SEPT_ETAPES } from "../ui/Etapes.jsx";
import { AutoEvaluation, QuizFrancais, ReponsesRedigees } from "./ActiviteFrancais.jsx";

/** Lignes citées par une consigne : « ligne 5 », « lignes 4 à 12 », « l. 3-7 ». */
export function lignesCitees(texte) {
  const plages = [];
  const motif = /(?:lignes?|l\.)\s*(\d+)(?:\s*(?:à|-|–|et)\s*(\d+))?/gi;
  for (const m of texte.matchAll(motif)) {
    const debut = Number(m[1]);
    const fin = m[2] ? Number(m[2]) : debut;
    plages.push([Math.min(debut, fin), Math.max(debut, fin)]);
  }
  return plages;
}

function dansPlage(n, plages) {
  return plages.some(([a, b]) => n >= a && n <= b);
}

/** Texte numéroté ; `plages` : lignes repérées (citées par la question en cours). */
export function TexteNumerote({ texte, plages = [] }) {
  return (
    <article className="texte-source" aria-labelledby={`texte-${texte.code}`}>
      <h3 id={`texte-${texte.code}`}>{texte.titre}</h3>
      <ol className="texte-numerote">
        {texte.lignes.map((ligne, i) => (
          <li key={i} value={i + 1} className={dansPlage(i + 1, plages) ? "citee" : undefined}>
            {ligne}
          </li>
        ))}
      </ol>
      {texte.mention && <p className="doux petit">{texte.mention}</p>}
    </article>
  );
}

/** Texte à côté des activités ; plusieurs textes : un sélecteur. */
function AvecTexte({ textes, codes, plages, children }) {
  const utiles = textes.filter((t) => codes.includes(t.code));
  const [choisi, setChoisi] = useState(utiles[0]?.code);
  const texte = utiles.find((t) => t.code === choisi) ?? utiles[0];
  if (!texte) return children;
  return (
    <div className="lecture-partagee">
      <div className="lecture-texte">
        {utiles.length > 1 && (
          <div className="fr-filtres" role="group" aria-label="Texte affiché">
            {utiles.map((t) => (
              <button key={t.code} type="button" className={t.code === texte.code ? "petit" : "secondaire petit"}
                aria-pressed={t.code === texte.code} onClick={() => setChoisi(t.code)}>
                {t.titre}
              </button>
            ))}
          </div>
        )}
        <TexteNumerote texte={texte} plages={plages} />
      </div>
      <div className="lecture-activite">{children}</div>
    </div>
  );
}

function Questions({ questions, textes, intro }) {
  const [enCours, setEnCours] = useState(questions[0]?.code);
  const question = questions.find((q) => q.code === enCours) ?? questions[0];
  const plages = question ? lignesCitees(question.consigne) : [];
  return (
    <AvecTexte textes={textes} codes={[...new Set(questions.map((q) => q.texte).filter(Boolean))]} plages={plages}>
      {intro.map((l) => (
        <p key={l} className="doux petit">{l}</p>
      ))}
      <ol className="questions-dossier">
        {questions.map((q) => (
          <li key={q.code} className={q.code === question?.code ? "en-cours" : undefined}>
            <button type="button" className="question-entete" aria-expanded={q.code === question?.code}
              onClick={() => setEnCours(q.code)}>
              <span className="badge neutre">{q.code}</span>
              {q.difficulte_proposee && <span className="doux petit">difficulté {q.difficulte_proposee}</span>}
            </button>
            <p className="question-consigne">{q.consigne}</p>
            {q.code === question?.code && (
              <>
                {lignesCitees(q.consigne).length > 0 && (
                  <p className="doux petit">Les lignes citées sont repérées dans la marge du texte.</p>
                )}
                {q.coup_de_pouce && (
                  <details className="coup-de-pouce">
                    <summary>Coup de pouce</summary>
                    <p>{q.coup_de_pouce}</p>
                  </details>
                )}
                <p className="doux petit">Rédige ta réponse : ton professeur la relira.</p>
              </>
            )}
          </li>
        ))}
      </ol>
    </AvecTexte>
  );
}

/** Étapes du dossier : contenu de chacune, et étapes sans activité grisées. */
function etapesDuDossier(d) {
  const e = d.eleve;
  const entrainement = e.questions.filter((q) => q.partie !== "transfert");
  const transfert = e.questions.filter((q) => q.partie === "transfert");
  const quiz = e.quiz ?? [];
  const contenu = {
    1: e.objectifs.length > 0,
    2: e.lecon.length > 0,
    3: quiz.length > 0,
    4: entrainement.length > 0,
    5: transfert.length > 0,
    6: Boolean(d.saisie_ouverte),
    7: Boolean(e.je_verifie) || (e.je_sais ?? []).length > 0,
  };
  const details = {
    1: "Objectifs, prérequis",
    2: "Leçon, exemple",
    3: `Quiz de ${quiz.length} questions`,
    4: `${entrainement.length} questions sur le texte`,
    5: `${transfert.length} questions sur un autre texte`,
    6: "Mes réponses rédigées",
    7: "Je vérifie, je sais",
  };
  return {
    etapes: SEPT_ETAPES.map((titre, i) => ({ numero: i + 1, titre, detail: details[i + 1], disponible: contenu[i + 1] })),
    entrainement,
    transfert,
  };
}

export default function LectureDossier({ dossier, jeton, onExpire, onFermer, libelleRetour }) {
  const { etapes, entrainement, transfert } = useMemo(() => etapesDuDossier(dossier), [dossier]);
  const premiere = etapes.find((e) => e.disponible)?.numero ?? 1;
  const [active, setActive] = useState(premiere);
  const [faites, setFaites] = useState([]);
  const e = dossier.eleve;
  const titreEtape = SEPT_ETAPES[active - 1];

  function choisir(numero) {
    setFaites((f) => (f.includes(active) ? f : [...f, active]));
    setActive(numero);
    window.scrollTo?.(0, 0);
  }

  return (
    <div className="ecran-cours">
      <RailEtapes
        titreCours={dossier.titre}
        rubrique="Lire et comprendre"
        etapes={etapes}
        active={active}
        faites={faites}
        onChoisir={choisir}
        onRetour={onFermer}
        libelleRetour={libelleRetour}
      />
      <section className="contenu-etape" aria-labelledby="titre-etape">
        <p className="surtitre">Étape {active} sur 7</p>
        <h2 id="titre-etape">{titreEtape}</h2>
        <h3 className="visuellement-cache" id="titre-dossier-francais">{dossier.titre}</h3>

        {active === 1 && (
          <div className="lecture">
            {e.objectifs.map((l) => (
              <p key={l}>{l}</p>
            ))}
          </div>
        )}
        {active === 2 && (
          <div className="lecture">
            {e.lecon.map((s) => (
              <section key={s.titre}>
                <h3>{s.titre}</h3>
                <Maths texte={s.markdown} />
              </section>
            ))}
          </div>
        )}
        {active === 3 && (
          <AvecTexte textes={e.textes} codes={[...new Set((e.quiz ?? []).map((q) => q.texte).filter(Boolean))]}>
            <QuizFrancais key={`quiz-${dossier.code}`} dossier={dossier} jeton={jeton} onExpire={onExpire} />
          </AvecTexte>
        )}
        {active === 4 && <Questions questions={entrainement} textes={e.textes} intro={e.consignes_questions} />}
        {active === 5 && <Questions questions={transfert} textes={e.textes} intro={[]} />}
        {active === 6 && (
          <ReponsesRedigees key={`reponses-${dossier.code}`} dossier={dossier} jeton={jeton} onExpire={onExpire} />
        )}
        {active === 7 && (
          <>
            {e.je_verifie && (
              <div className="lecture">
                <Maths texte={e.je_verifie} />
              </div>
            )}
            <AutoEvaluation key={`je-sais-${dossier.code}`} dossier={dossier} jeton={jeton} onExpire={onExpire} />
          </>
        )}
        {active !== 6 && !dossier.saisie_ouverte && [4, 5].includes(active) && (
          <p className="info petit" role="note">
            Réponds dans ton cahier : la réponse en ligne n'est pas encore ouverte. Ton professeur te fera un retour.
          </p>
        )}
        <NavigationEtapes etapes={etapes} active={active} onChoisir={choisir} />
      </section>
    </div>
  );
}
