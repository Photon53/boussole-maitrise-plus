// Issue #231 — Accueil et cours Français de l'élève (Claude)
//
// Trois destinations pour l'élève de français (FR-UI-D5) : Accueil, Mes cours, Ma progression, plus « S'entraîner »
// et « Plus ». Chapitres et dossiers se présentent de la même façon (A1, FR-UI-D1) ; l'étape affichée du parcours
// guidé en sept étapes (FR-UI-D2) ne change pas le choix des questions par le moteur (FR-UI-D3).
import { useEffect, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";

export const RUBRIQUES = [
  ["lire", "Lire et comprendre", "Textes, compréhension, préparation au brevet."],
  ["grammaire", "Grammaire", "Nature et fonctions des mots, orthographe."],
  ["conjugaison", "Conjugaison", "Temps, modes et terminaisons."],
  ["redaction", "Rédaction", "Écrire, relire, réécrire avec ta professeure."],
];
const LIBELLE_RUBRIQUE = Object.fromEntries(RUBRIQUES.map(([c, l]) => [c, l]));

const ETATS = {
  pas_commence: ["À commencer", "neutre"],
  en_cours: ["En cours", "action"],
  a_reprendre: ["À revoir", "alerte"],
  maitrise: ["Maîtrisé", "ok"],
  reussi: ["Réussi", "ok"],
};

/** Données de l'accueil, partagées par l'accueil et « Mes cours ». */
export function useAccueilFrancais(jeton, onExpire) {
  const [donnees, setDonnees] = useState(null);
  const [erreur, setErreur] = useState(null);
  useEffect(() => {
    let actif = true;
    api("/francais/eleve/accueil", { jeton }).then(
      (d) => actif && setDonnees(d),
      (err) => {
        if (!actif) return;
        if (err.status === 401 && onExpire) onExpire();
        else setErreur(err.message);
      },
    );
    return () => {
      actif = false;
    };
  }, [jeton, onExpire]);
  return { donnees, erreur };
}

/** Les sept étapes ; `termine` : cours maîtrisé ou réussi, toutes les étapes sont faites. */
function Etapes({ etape, total = 7, termine = false }) {
  return (
    <span className="fr-etapes" role="img" aria-label={termine ? `Étape ${etape} sur ${total}, terminé` : `Étape ${etape} sur ${total}`}>
      {Array.from({ length: total }, (_, i) => (
        <span key={i} className={termine || i + 1 < etape ? "fait" : i + 1 === etape ? "encours" : ""} />
      ))}
    </span>
  );
}

function Pastille({ etat }) {
  const [libelle, ton] = ETATS[etat] ?? [etat, "neutre"];
  return <span className={`badge ${ton}`}>{libelle}</span>;
}

/** Action principale d'un cours : la leçon tant que l'élève découvre, puis l'entraînement ; le dossier s'ouvre. */
function libelleAction(c) {
  if (c.type === "dossier") return c.etat === "pas_commence" ? "Commencer" : "Reprendre";
  if (c.etat === "pas_commence") return "Commencer";
  return c.etape >= 7 ? "Revoir" : "Reprendre";
}

export function AccueilFrancais({ jeton, onExpire, onOuvrir, onRubrique, onAller }) {
  const { donnees, erreur } = useAccueilFrancais(jeton, onExpire);
  const [ressources, setRessources] = useState([]);

  useEffect(() => {
    api("/cours/mon-cours", { jeton }).then(
      (chapitres) => setRessources(chapitres.flatMap((c) => c.ressources.map((r) => ({ ...r, chapitre: c.titre })))),
      () => setRessources([]),
    );
  }, [jeton]);

  if (erreur) return <Erreur message={erreur} />;
  if (!donnees) return <p className="doux">Chargement de ton espace Français…</p>;

  const reprise = donnees.cours.find((c) => c.cle === donnees.reprise);
  const parRubrique = (r) => donnees.cours.filter((c) => c.rubrique === r);

  return (
    <div className="fr-eleve">
      <header className="fr-eleve-entete">
        <h2>Mon espace Français</h2>
        <p className="doux">
          {donnees.cours.length
            ? `Ta professeure a ouvert ${donnees.cours.length} cours pour ta classe.`
            : "Ta professeure n'a pas encore ouvert de cours de français pour ta classe."}
        </p>
      </header>

      {!donnees.acces && (
        <p className="info" role="note">
          Le français n'est pas encore ouvert à ta classe. Ta progression et ton historique restent consultables.
        </p>
      )}

      {reprise && (
        <section className="fr-reprise" aria-labelledby="fr-reprise-titre">
          <div className="fr-reprise-texte">
            <p className="surtitre">{reprise.derniere_activite ? "Reprendre ton cours" : "Pour commencer"}</p>
            <h3 id="fr-reprise-titre">{reprise.titre}</h3>
            <p className="doux">
              {LIBELLE_RUBRIQUE[reprise.rubrique] ?? "Français"} · étape {reprise.etape} sur 7 :{" "}
              <strong>{donnees.etapes[reprise.etape - 1]}</strong>
            </p>
            <Etapes etape={reprise.etape} />
          </div>
          <button onClick={() => onOuvrir(reprise)}>
            {reprise.derniere_activite ? "Continuer" : "Commencer"}
          </button>
        </section>
      )}

      <section aria-labelledby="fr-rubriques-titre" className="fr-bloc">
        <h3 id="fr-rubriques-titre">Les quatre rubriques</h3>
        <div className="fr-rubriques">
          {RUBRIQUES.map(([code, libelle, description]) => {
            const liste = parRubrique(code);
            const commences = liste.filter((c) => c.etat !== "pas_commence").length;
            return (
              <button key={code} className="fr-rubrique" onClick={() => onRubrique(code)}>
                <span className="fr-rubrique-titre">{libelle}</span>
                <span className="doux petit">{description}</span>
                <span className="fr-rubrique-pied">
                  {liste.length === 0
                    ? "Pas encore de cours"
                    : `${liste.length} cours · ${commences} commencé${commences > 1 ? "s" : ""}`}
                  {code === "redaction" && !donnees.redaction_ouverte && liste.length > 0 && (
                    <span className="badge neutre">Sur copie</span>
                  )}
                </span>
              </button>
            );
          })}
        </div>
      </section>

      <div className="fr-deux">
        <section className="carte" aria-labelledby="fr-a-commencer">
          <h3 id="fr-a-commencer">Tes cours</h3>
          {donnees.cours.length === 0 ? (
            <p className="doux">Rien à faire pour l'instant.</p>
          ) : (
            <ul className="fr-liste">
              {donnees.cours.slice(0, 4).map((c) => (
                <li key={c.cle}>
                  <div>
                    <strong>{c.titre}</strong>
                    <div className="doux petit">{LIBELLE_RUBRIQUE[c.rubrique] ?? "Français"}</div>
                  </div>
                  <button className="secondaire petit" onClick={() => onOuvrir(c)}>{libelleAction(c)}</button>
                </li>
              ))}
            </ul>
          )}
          {donnees.cours.length > 4 && (
            <button className="lien" onClick={() => onRubrique("")}>Voir tous mes cours</button>
          )}
        </section>
        <section className="carte" aria-labelledby="fr-ressources">
          <h3 id="fr-ressources">Ressources de ta professeure</h3>
          {ressources.length === 0 ? (
            <p className="doux">Pas encore de fiche ni de lien.</p>
          ) : (
            <ul className="fr-liste">
              {ressources.slice(0, 3).map((r) => (
                <li key={r.id}>
                  <div>
                    <strong>{r.titre}</strong>
                    <div className="doux petit">{r.type === "lien" ? "Lien" : "Fiche"} · {r.chapitre}</div>
                  </div>
                </li>
              ))}
            </ul>
          )}
          <button className="lien" onClick={() => onAller("mon-cours")}>Toutes les ressources</button>
        </section>
      </div>
    </div>
  );
}

export function CoursFrancais({ jeton, onExpire, rubrique, onRubrique, onOuvrir, onLecon }) {
  const { donnees, erreur } = useAccueilFrancais(jeton, onExpire);
  if (erreur) return <Erreur message={erreur} />;
  if (!donnees) return <p className="doux">Chargement de tes cours…</p>;
  const presentes = RUBRIQUES.filter(([code]) => donnees.rubriques[code]);
  const cours = donnees.cours.filter((c) => !rubrique || c.rubrique === rubrique);

  return (
    <div className="fr-eleve">
      <p className="doux">Les cours ouverts par ta professeure. Leçons, entraînements et dossiers se présentent de la même façon.</p>
      <div className="fr-filtres" role="group" aria-label="Filtrer par rubrique">
        <button className={rubrique ? "secondaire petit" : "petit"} aria-pressed={!rubrique} onClick={() => onRubrique("")}>
          Toutes ({donnees.cours.length})
        </button>
        {presentes.map(([code, libelle]) => (
          <button key={code} className={rubrique === code ? "petit" : "secondaire petit"} aria-pressed={rubrique === code}
            onClick={() => onRubrique(code)}>
            {libelle} ({donnees.rubriques[code]})
          </button>
        ))}
      </div>
      {cours.length === 0 ? (
        <p className="carte doux">
          {donnees.cours.length ? "Aucun cours dans cette rubrique pour l'instant." : "Ta professeure n'a pas encore ouvert de cours."}
        </p>
      ) : (
        <div className="fr-cartes-cours">
          {cours.map((c) => (
            <article key={c.cle} className="fr-carte-cours" aria-labelledby={`titre-${c.cle}`}>
              <div className="fr-carte-haut">
                <span className="fr-rub">{LIBELLE_RUBRIQUE[c.rubrique] ?? "Français"}</span>
                <Pastille etat={c.etat} />
              </div>
              <h3 id={`titre-${c.cle}`}>{c.titre}</h3>
              <div className="fr-carte-etape">
                <Etapes etape={c.etape} termine={["maitrise", "reussi"].includes(c.etat)} />
                <span className="doux petit">Étape {c.etape} sur 7 : {donnees.etapes[c.etape - 1]}</span>
              </div>
              <div className="fr-carte-pied">
                <span className="doux petit">
                  {c.type === "dossier"
                    ? c.score !== null && c.score !== undefined ? `Quiz : ${c.score}/${c.total}` : `Texte, quiz de ${c.nb_quiz} questions`
                    : c.rubrique === "redaction"
                      ? "Sujet de rédaction"
                      : `${c.nb_questions} question${c.nb_questions > 1 ? "s" : ""}`}
                </span>
                <span className="fr-carte-actions">
                  {c.type === "chapitre" && c.a_une_lecon && c.etat !== "pas_commence" && (
                    <button className="lien petit" onClick={() => onLecon(c)}>Leçon</button>
                  )}
                  <button className="petit" onClick={() => onOuvrir(c)}>{libelleAction(c)}</button>
                </span>
              </div>
            </article>
          ))}
        </div>
      )}
    </div>
  );
}

/** « Plus » : ce qui sort de la navigation principale, sans rien retirer. */
export function PlusFrancais({ onAller }) {
  const entrees = [
    ["redaction", "Rédaction", "Les sujets de rédaction de ta classe."],
    ["mon-cours", "Ressources de ta professeure", "Fiches et liens, chapitre par chapitre."],
    ["pkp", "Fiches et PDF", "Résumés et fiches des chapitres ouverts."],
    ["historique", "Mon historique", "Tes réponses et leurs corrections."],
    ["remarques", "Remarques", "Signaler une erreur ou faire une suggestion."],
  ];
  return (
    <ul className="fr-plus">
      {entrees.map(([cle, titre, texte]) => (
        <li key={cle}>
          <button className="fr-plus-entree" onClick={() => onAller(cle)}>
            <strong>{titre}</strong>
            <span className="doux petit">{texte}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}
