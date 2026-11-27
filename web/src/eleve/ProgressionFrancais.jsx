// Issue #231 — « Ma progression » de l'élève de français (Claude)
//
// Maquette 8 de la refonte. Un bilan lisible plutôt qu'une liste de barres : le cours travaillé en dernier (avancement
// calculé par le moteur, « À retenir »), les quatre rubriques, ce qui est à retravailler et les dernières activités.
// Aucune donnée nouvelle : l'accueil Français (cours, états, étapes) et l'avancement d'une compétence. La maîtrise ne
// compte que les exercices corrigés par la plateforme ; une rédaction relue par la professeure n'y entre jamais (ARCH-5).
import { useEffect, useMemo, useState } from "react";
import { api } from "../api.js";
import { Erreur } from "../composants.jsx";
import { Maths } from "../maths.jsx";
import { RUBRIQUES, useAccueilFrancais } from "./FrancaisEleve.jsx";

const ETATS = {
  pas_commence: ["Pas commencé", "neutre"],
  en_cours: ["En cours", "action"],
  a_reprendre: ["À revoir", "alerte"],
  maitrise: ["Maîtrisé", "ok"],
  reussi: ["Réussi", "ok"],
};
const TERMINE = new Set(["maitrise", "reussi"]);
const JOUR = 24 * 60 * 60 * 1000;

/** « Aujourd'hui », « Hier », « Il y a 3 jours » ou la date. */
export function quand(iso, maintenant = Date.now()) {
  const d = new Date(iso);
  const jours = Math.floor((new Date(maintenant).setHours(0, 0, 0, 0) - new Date(d).setHours(0, 0, 0, 0)) / JOUR);
  if (jours <= 0) return "Aujourd'hui";
  if (jours === 1) return "Hier";
  if (jours < 30) return `Il y a ${jours} jours`;
  return d.toLocaleDateString("fr-FR", { day: "numeric", month: "long" });
}

/** Résumé d'une rubrique : cours terminés, état global, détail des premiers cours. */
export function resumeRubrique(cours) {
  if (cours.length === 0) return { ton: "neutre", libelle: "Pas encore", termines: 0, total: 0 };
  const termines = cours.filter((c) => TERMINE.has(c.etat)).length;
  const [libelle, ton] =
    termines === cours.length ? ["Maîtrisé", "ok"]
      : cours.some((c) => c.etat === "a_reprendre") ? ["À revoir", "alerte"]
        : cours.every((c) => c.etat === "pas_commence") ? ["À commencer", "neutre"]
          : ["En cours", "action"];
  return { ton, libelle, termines, total: cours.length };
}

const resultat = (c) =>
  c.type === "dossier"
    ? c.total ? `quiz ${c.score} / ${c.total}` : ""
    : c.maitrise != null ? `maîtrise ${Math.round(c.maitrise * 100)} %` : "";

/** Bilan du cours travaillé en dernier : avancement du moteur et « À retenir » de la leçon. */
function Bilan({ cours, jeton, etapes, onOuvrir }) {
  const [av, setAv] = useState(null);
  const [lecon, setLecon] = useState(null);
  useEffect(() => {
    let actif = true;
    setAv(null);
    setLecon(null);
    api(`/eleves/moi/competences/${cours.competence_id}/avancement`, { jeton }).then((a) => actif && setAv(a), () => {});
    if (cours.a_une_lecon) api(`/cours/${cours.competence_id}`, { jeton }).then((l) => actif && setLecon(l), () => {});
    return () => {
      actif = false;
    };
  }, [cours, jeton]);

  const tuile = (libelle, reussies, objectif) => {
    const part = objectif ? Math.min(100, Math.round((100 * reussies) / objectif)) : 0;
    return (
      <div className="bilan-tuile">
        <span className="doux petit">{libelle}</span>
        <strong className="bilan-chiffre">{Math.min(reussies, objectif)} / {objectif}</strong>
        <span className="fr-barre" role="img" aria-label={`${part} %`}><span style={{ width: `${part}%` }} /></span>
      </div>
    );
  };
  return (
    <section className="carte bilan-cours" aria-labelledby="titre-bilan">
      <div className="bilan-entete">
        <div>
          <p className="surtitre-progression">Bilan · étape {cours.etape} · {etapes[cours.etape - 1]}</p>
          <h3 id="titre-bilan">{cours.titre}</h3>
        </div>
        {av?.reponses > 0 && (
          <span className={`badge ${av.maitrisee ? "ok" : "action"}`}>
            {av.maitrisee ? "Compétence maîtrisée" : "Maîtrise"} · {Math.round(av.maitrise * 100)} %
          </span>
        )}
      </div>
      {av && (
        <div className="bilan-tuiles">
          {tuile("Exercices de base (niveaux 1 à 3)", av.reussies_bases, av.objectif_bases)}
          {tuile("Exercices difficiles (niveaux 4 et 5)", av.reussies_avancees, av.objectif_avancees)}
        </div>
      )}
      {lecon?.resume && (
        <div className="resume bilan-retenir">
          <p className="surtitre-progression">À retenir</p>
          <Maths texte={lecon.resume} />
        </div>
      )}
      <div className="bilan-pied">
        <span className="doux petit">Une compétence est maîtrisée à partir de 80 %, soit environ 5 bonnes réponses d'affilée.</span>
        <button type="button" className="secondaire" onClick={() => onOuvrir(cours)}>
          {TERMINE.has(cours.etat) ? "Revoir le cours" : "Reprendre le cours"}
        </button>
      </div>
    </section>
  );
}

export default function ProgressionFrancais({ jeton, onExpire, onOuvrir }) {
  const { donnees, erreur } = useAccueilFrancais(jeton, onExpire);
  const cours = useMemo(() => donnees?.cours ?? [], [donnees]);
  const recents = useMemo(
    () => cours.filter((c) => c.derniere_activite).sort((a, b) => b.derniere_activite.localeCompare(a.derniere_activite)),
    [cours],
  );
  const focus = recents.find((c) => c.type === "chapitre" && c.competence_id && c.rubrique !== "redaction");

  if (erreur) return <Erreur message={erreur} />;
  if (!donnees) return <p className="doux">Chargement de ta progression…</p>;
  const aRevoir = cours.filter((c) => c.etat === "a_reprendre");
  return (
    <div className="progression-fr">
      <div>
        <h2>Ma progression</h2>
        <p className="doux">
          Calculée à partir des exercices corrigés automatiquement. Les rédactions relues par ta professeure n'entrent
          pas dans ce calcul.
        </p>
      </div>
      {!donnees.acces && (
        <p className="info" role="note">Le français n'est pas ouvert à ta classe en ce moment.</p>
      )}
      {focus ? (
        <Bilan cours={focus} jeton={jeton} etapes={donnees.etapes} onOuvrir={onOuvrir} />
      ) : (
        donnees.acces && <p className="carte doux">Fais tes premiers exercices : ton bilan apparaîtra ici.</p>
      )}
      <div className="fr-deux">
        <section className="carte" aria-labelledby="titre-rubriques">
          <h3 id="titre-rubriques">Par rubrique</h3>
          <ul className="progression-rubriques">
            {RUBRIQUES.map(([code, libelle]) => {
              const liste = cours.filter((c) => c.rubrique === code);
              const r = resumeRubrique(liste);
              const redaction = code === "redaction";
              const part = r.total ? Math.round((100 * r.termines) / r.total) : 0;
              return (
                <li key={code}>
                  <div className="rubrique-ligne">
                    <strong>{libelle}</strong>
                    {redaction ? (
                      <span className="badge neutre">{donnees.redaction_ouverte ? "Retours de ta professeure" : "Sur copie"}</span>
                    ) : (
                      <span className={`badge ${r.ton}`}>{r.libelle}</span>
                    )}
                  </div>
                  <span className="doux petit">
                    {liste.length === 0
                      ? `Pas encore de cours ouvert en ${donnees.eleve.niveau}`
                      : redaction
                        ? `${liste.length} sujet${liste.length > 1 ? "s" : ""} · retours de ta professeure, sans pourcentage`
                        : liste.slice(0, 2).map((c) => `${c.titre} : ${ETATS[c.etat]?.[0].toLowerCase() ?? c.etat}`).join(" · ")
                          + (liste.length > 2 ? ` · et ${liste.length - 2} autre${liste.length > 3 ? "s" : ""}` : "")}
                  </span>
                  {!redaction && liste.length > 0 && (
                    <span className="fr-barre" role="img" aria-label={`${r.termines} cours terminé${r.termines > 1 ? "s" : ""} sur ${r.total}`}>
                      <span style={{ width: `${part}%` }} />
                    </span>
                  )}
                </li>
              );
            })}
          </ul>
        </section>
        <div className="fr-cote">
          <section className="carte" aria-labelledby="titre-retravailler">
            <h3 id="titre-retravailler">À retravailler</h3>
            {aRevoir.length === 0 ? (
              <p className="doux">Rien à reprendre pour l'instant.</p>
            ) : (
              <ul className="fr-liste">
                {aRevoir.map((c) => (
                  <li key={c.cle}>
                    <div>
                      <strong>{c.titre}</strong>
                      <div className="doux petit">{resultat(c)}</div>
                    </div>
                    <button type="button" className="secondaire petit" onClick={() => onOuvrir(c, 2)}>Réviser</button>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="carte" aria-labelledby="titre-activites">
            <h3 id="titre-activites">Dernières activités</h3>
            {recents.length === 0 ? (
              <p className="doux">Pas encore d'activité.</p>
            ) : (
              <ul className="fr-liste">
                {recents.slice(0, 4).map((c) => (
                  <li key={c.cle}>
                    <div>
                      <strong>{c.titre}</strong>
                      <div className="doux petit">
                        {quand(c.derniere_activite)}{resultat(c) ? ` · ${resultat(c)}` : ""}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
        </div>
      </div>
    </div>
  );
}
