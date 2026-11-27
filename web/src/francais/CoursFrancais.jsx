// Issue #217 — Cours de français visibles dans l'espace Français (Claude)
//
// Les chapitres interactifs de français (#177 : grammaire, conjugaison, rédaction) se servent et se valident comme
// ceux des maths. Cet onglet les rend visibles depuis l'espace Français : par niveau et par rubrique, avec l'état de
// validation de leurs questions et les classes où ils sont ouverts. Lecture seule ; la validation se fait question
// par question dans la page « Validation » de l'espace professeur ou dans l'administration.
import { useEffect, useState } from "react";
import { Lien } from "../navigation.js";
import { Maths } from "../maths.jsx";
import { NIVEAUX } from "../parcours.js";
import { Vide } from "../ui/Cadre.jsx";

const RUBRIQUES = { grammaire: "Grammaire", conjugaison: "Conjugaison", redaction: "Rédaction", mon_cours: "Mon cours" };
const STATUTS = { validee: "Validée", "a-valider": "À valider", "a-corriger": "À corriger" };

export default function CoursFrancais({ appeler, admin }) {
  const [chapitres, setChapitres] = useState(null);
  const [choisi, setChoisi] = useState(null);

  useEffect(() => {
    appeler("/francais/chapitres").then(setChapitres, () => setChapitres([]));
  }, [appeler]);

  if (chapitres === null) return <p className="doux">Chargement…</p>;
  if (choisi) return <DetailCours id={choisi} appeler={appeler} admin={admin} onRetour={() => setChoisi(null)} />;
  if (chapitres.length === 0) {
    return <Vide>Aucun cours de français dans votre périmètre (domaine activé et habilitation au niveau).</Vide>;
  }
  const niveaux = NIVEAUX.map(([v, l]) => [v, l, chapitres.filter((c) => c.niveau === v)]).filter(([, , cs]) => cs.length);
  return (
    <section>
      <p className="carte doux" role="note">
        Cours interactifs : leçon, exercices corrigés automatiquement et sujets de rédaction. Une classe les voit quand son
        professeur les ouvre (onglet « Classes » de l'espace professeur). Leurs questions se valident une par une
        {admin ? " (Administration → Exercices)" : " (page « Validation » de l'espace professeur)"}.
      </p>
      {niveaux.map(([v, libelle, cs]) => (
        <div key={v} className="carte">
          <h2>{libelle}</h2>
          <ul className="liste-simple">
            {cs.map((c) => (
              <li key={c.id}>
                <strong>{c.titre}</strong>{" "}
                <span className="doux petit">
                  {RUBRIQUES[c.rubrique] ?? c.rubrique} · {c.code} · {c.nb_validees}/{c.nb_questions} questions validées
                  {c.nb_a_corriger ? ` · ${c.nb_a_corriger} à corriger` : ""}
                  {c.ouvert_dans.length ? ` · ouvert dans ${c.ouvert_dans.join(", ")}` : ""}
                </span>
                <div className="actions">
                  <button className="secondaire" onClick={() => setChoisi(c.id)}>
                    Lire le cours
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </div>
      ))}
    </section>
  );
}

function DetailCours({ id, appeler, admin, onRetour }) {
  const [cours, setCours] = useState(null);

  useEffect(() => {
    appeler(`/francais/chapitres/${id}`).then(setCours, () => {});
  }, [appeler, id]);

  if (!cours) return <p className="doux">Chargement…</p>;
  return (
    <section>
      <button className="lien" onClick={onRetour}>
        ← Tous les cours
      </button>
      <div className="carte">
        <h2>{cours.titre}</h2>
        <p className="doux petit">
          {cours.niveau} · {RUBRIQUES[cours.rubrique] ?? cours.rubrique} · {cours.nb_validees}/{cours.nb_questions} questions
          validées
        </p>
        {cours.peut_valider && (
          <p>
            <Lien vers={admin ? "/admin/exercices" : "/enseignant/validation"}>Valider ces questions</Lien>
          </p>
        )}
      </div>
      {cours.competences.map((c) => (
        <article key={c.id} className="carte">
          <h3>{c.libelle}</h3>
          {c.resume && (
            <div className="encadre">
              <Maths texte={c.resume} />
            </div>
          )}
          {c.cours ? <Maths texte={c.cours} /> : <p className="doux">Leçon à venir.</p>}
          {c.questions.length > 0 && (
            <>
              <h4>Questions ({c.questions.length})</h4>
              <ol>
                {c.questions.map((q) => (
                  <li key={q.id}>
                    <Maths texte={q.enonce} enLigne />{" "}
                    <span className="doux petit">
                      ({q.type}, difficulté {q.difficulte}, {STATUTS[q.statut] ?? q.statut}) — réponse : {q.solution}
                    </span>
                  </li>
                ))}
              </ol>
            </>
          )}
        </article>
      ))}
    </section>
  );
}
