// Issue #231 — Écran de cours de français en sept étapes (Claude)
//
// La leçon d'un chapitre (champs existants : objectifs, cours, résumé, méthodes, erreurs fréquentes, ressources),
// rangée selon la méthode commune de #177 (FR-UI-D2). Le cours rédigé suit déjà la trame « 1. Découvrir, 2. Comprendre,
// 3. Appliquer et s'entraîner, 4. Approfondir, 5. Réinvestir » : chaque partie va à son étape, sans toucher au contenu.
// Les étapes d'exercices ouvrent l'entraînement existant : le moteur choisit les questions (FR-UI-D3).
import { useEffect, useMemo, useRef, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";
import { Maths } from "../maths.jsx";
import RailEtapes, { NavigationEtapes, SEPT_ETAPES } from "../ui/Etapes.jsx";
import { ErreursFrequentes, Methodes, Objectifs } from "../ui/Pedagogie.jsx";
import { AvisCours } from "./Comprehension.jsx";
import { Ressources } from "./Cours.jsx";

const RUBRIQUES = { grammaire: "Grammaire", conjugaison: "Conjugaison", redaction: "Rédaction", lire: "Lire et comprendre" };

/** Étape d'une partie du cours, d'après son titre (« ## 3. Appliquer et s'entraîner »…). */
function etapeDuTitre(titre) {
  const t = titre.toLowerCase();
  if (t.includes("découvrir")) return 1;
  if (t.includes("comprendre")) return 2;
  if (t.includes("appliquer") || t.includes("critères")) return 3;
  if (t.includes("approfondir") || t.includes("relire") || t.includes("réécrire")) return 5;
  if (t.includes("réinvestir")) return 6;
  if (t.includes("retenir") || t.includes("consolider")) return 7;
  return 2;
}

/** Découpe le cours rédigé en parties « ## … » ; le texte avant le premier titre va à « Comprendre ». */
export function partiesDuCours(markdown) {
  const parties = {};
  let etape = 2;
  let titre = null;
  let lignes = [];
  const ranger = () => {
    const texte = lignes.join("\n").trim();
    if (texte || titre) (parties[etape] ??= []).push({ titre, texte });
  };
  for (const ligne of (markdown ?? "").split("\n")) {
    const m = ligne.match(/^##\s+(?:\d+\.\s*)?(.+)$/);
    if (m) {
      ranger();
      titre = m[1].trim();
      etape = etapeDuTitre(titre);
      lignes = [];
    } else {
      lignes.push(ligne);
    }
  }
  ranger();
  return parties;
}

/** Parties du cours d'une étape ; un titre identique au nom de l'étape (« Comprendre ») n'est pas répété. */
function Parties({ parties, etape }) {
  const meme = (titre) => titre && titre.toLowerCase() === (etape ?? "").toLowerCase();
  return (parties ?? []).map((p, i) => (
    <section key={i} className="lecture">
      {p.titre && !meme(p.titre) && <h3>{p.titre}</h3>}
      {p.texte && <Maths texte={p.texte} />}
    </section>
  ));
}

export default function EcranCours({
  jeton, onExpire, competenceId, etapeInitiale = null, rubrique = null, nbQuestions = null,
  onRetour, onEntrainer, onVoirHistorique,
}) {
  const [lecon, setLecon] = useState(null);
  const [erreur, setErreur] = useState(null);
  // Avancement calculé par le moteur (bonnes réponses par niveau, maîtrise) : affiché, jamais recalculé ici.
  const [avancement, setAvancement] = useState(null);

  useEffect(() => {
    let actif = true;
    api(`/eleves/moi/competences/${competenceId}/avancement`, { jeton }).then(
      (a) => actif && setAvancement(a),
      () => actif && setAvancement(null),
    );
    return () => {
      actif = false;
    };
  }, [competenceId, jeton]);

  useEffect(() => {
    let actif = true;
    setLecon(null);
    api(`/cours/${competenceId}`, { jeton }).then(
      (l) => actif && setLecon(l),
      (err) => {
        if (!actif) return;
        if (err.status === 401) onExpire();
        else setErreur(err.status === 404 ? "Pas encore de cours pour cette compétence." : err.message);
      },
    );
    return () => {
      actif = false;
    };
  }, [competenceId, jeton, onExpire]);

  if (erreur) {
    return (
      <section className="carte">
        <button className="lien" onClick={onRetour}>← Mes cours</button>
        <Erreur message={erreur} />
      </section>
    );
  }
  if (!lecon) return <p className="doux">Chargement du cours…</p>;
  return (
    <Etapes lecon={lecon} avancement={avancement} jeton={jeton} etapeInitiale={etapeInitiale} rubrique={rubrique} nbQuestions={nbQuestions}
      onRetour={onRetour} onEntrainer={onEntrainer} onVoirHistorique={onVoirHistorique} />
  );
}

function Avancement({ av, niveau }) {
  if (!av || !av.reponses) return null;
  const [reussies, objectif, libelle] = niveau === "avancees"
    ? [av.reussies_avancees, av.objectif_avancees, "Exercices difficiles (niveaux 4 et 5)"]
    : [av.reussies_bases, av.objectif_bases, "Exercices de base (niveaux 1 à 3)"];
  const part = objectif ? Math.min(100, Math.round((100 * reussies) / objectif)) : 0;
  return (
    <div className="cours-avancement">
      <span>{libelle} : <strong>{Math.min(reussies, objectif)} / {objectif}</strong> réussies</span>
      <span className="fr-barre" role="img" aria-label={`${part} %`}><span style={{ width: `${part}%` }} /></span>
    </div>
  );
}

function Etapes({ lecon, avancement, jeton, etapeInitiale, rubrique, nbQuestions, onRetour, onEntrainer, onVoirHistorique }) {
  const parties = useMemo(() => partiesDuCours(lecon.cours), [lecon.cours]);
  const redaction = rubrique === "redaction";
  // Exercices corrigés par la plateforme : inconnu (null) quand on arrive d'ailleurs que « Mes cours » ; on les propose.
  const exercices = !redaction && nbQuestions !== 0;
  const etapes = SEPT_ETAPES.map((titre, i) => {
    const n = i + 1;
    const disponible = {
      1: lecon.objectifs.length > 0 || Boolean(parties[1]),
      2: true,
      3: exercices || Boolean(parties[3]),
      4: exercices,
      5: exercices || Boolean(parties[5]) || lecon.erreurs_frequentes.length > 0,
      6: Boolean(parties[6]),
      7: true,
    }[n];
    const detail = {
      1: "Objectifs, ce qu'il faut savoir",
      2: "Leçon, exemple résolu",
      3: redaction ? "Critères de réussite" : "Premiers exercices",
      4: "Exercices adaptés à ton niveau",
      5: redaction ? "Relire et réécrire" : "Exercices difficiles, erreurs à éviter",
      6: "Dans un autre travail",
      7: "À retenir, ton bilan",
    }[n];
    return { numero: n, titre, detail, disponible };
  });
  const premiere = etapes.find((e) => e.disponible)?.numero ?? 2;
  const depart = etapeInitiale && etapes[etapeInitiale - 1]?.disponible ? etapeInitiale : premiere;
  const [active, setActive] = useState(depart);
  const [faites, setFaites] = useState(() => etapes.filter((e) => e.numero < depart).map((e) => e.numero));

  // Issue #154 : au changement d'étape, le focus va au titre de l'étape (annoncé par un lecteur d'écran).
  const refTitre = useRef(null);
  const dejaAffiche = useRef(false);
  useEffect(() => {
    if (dejaAffiche.current) refTitre.current?.focus();
    dejaAffiche.current = true;
  }, [active]);

  function choisir(n) {
    setFaites((f) => (f.includes(active) ? f : [...f, active]));
    setActive(n);
    window.scrollTo?.(0, 0);
  }

  const entrainer = () => onEntrainer(lecon.competence_id, lecon.libelle);
  const boutonExercices = (libelle) =>
    exercices && (
      <div className="cours-action">
        <button onClick={entrainer}>{libelle}</button>
        <p className="doux petit">
          Les questions s'adaptent à ton niveau : on travaille d'abord ce que tu maîtrises le moins. Chaque réponse est
          corrigée tout de suite, avec la méthode.
        </p>
      </div>
    );

  return (
    <div className="ecran-cours">
      <RailEtapes
        titreCours={lecon.chapitre}
        rubrique={RUBRIQUES[rubrique] ?? "Français"}
        etapes={etapes}
        active={active}
        faites={faites}
        onChoisir={choisir}
        onRetour={onRetour}
      />
      <section className="contenu-etape" aria-labelledby="titre-etape">
        <p className="surtitre">Étape {active} sur 7</p>
        <h2 id="titre-etape" ref={refTitre} tabIndex={-1}>{SEPT_ETAPES[active - 1]}</h2>

        {active === 1 && (
          <>
            <Objectifs objectifs={lecon.objectifs} />
            <Parties parties={parties[1]} etape="Découvrir" />
          </>
        )}
        {active === 2 && (
          <>
            <Parties parties={parties[2]} etape="Comprendre" />
            {lecon.resume && (
              <section className="resume" aria-labelledby="titre-essentiel">
                <h3 id="titre-essentiel">L'essentiel</h3>
                <Maths texte={lecon.resume} />
              </section>
            )}
            <Methodes methodes={lecon.methodes} />
            <Ressources ressources={lecon.ressources ?? []} jeton={jeton} titre="De ta professeure" />
          </>
        )}
        {active === 3 && (
          <>
            <Parties parties={parties[3]} etape="Appliquer" />
            {exercices && <Avancement av={avancement} niveau="bases" />}
            {boutonExercices("Commencer les exercices")}
          </>
        )}
        {active === 4 && (
          <>
            <Avancement av={avancement} niveau="bases" />
            {boutonExercices(avancement?.reponses ? "Continuer l'entraînement" : "Commencer les exercices")}
          </>
        )}
        {active === 5 && (
          <>
            <Parties parties={parties[5]} etape="Approfondir" />
            {exercices && <Avancement av={avancement} niveau="avancees" />}
            <ErreursFrequentes erreurs={lecon.erreurs_frequentes} />
            {boutonExercices("M'entraîner encore")}
          </>
        )}
        {active === 6 && <Parties parties={parties[6]} etape="Réinvestir" />}
        {active === 7 && (
          <>
            {lecon.resume && (
              <section className="resume" aria-labelledby="titre-retenir">
                <h3 id="titre-retenir">À retenir</h3>
                <Maths texte={lecon.resume} />
              </section>
            )}
            {avancement?.reponses > 0 && (
              <p className={avancement.maitrisee ? "succes" : "info"} role="status">
                {avancement.maitrisee
                  ? `Compétence maîtrisée : ${Math.round(avancement.maitrise * 100)} %.`
                  : `Maîtrise actuelle : ${Math.round(avancement.maitrise * 100)} % (maîtrisée à partir de 80 %).`}
              </p>
            )}
            <Parties parties={parties[7]} etape="Consolider" />
            <AvisCours competenceId={lecon.competence_id} jeton={jeton} />
            {onVoirHistorique && (
              <div className="actions">
                <button className="secondaire" onClick={() => onVoirHistorique(lecon.competence_id)}>
                  Revoir mes réponses
                </button>
              </div>
            )}
          </>
        )}
        <NavigationEtapes etapes={etapes} active={active} onChoisir={choisir} />
      </section>
    </div>
  );
}
