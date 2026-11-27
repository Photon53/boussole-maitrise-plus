// Issue #231 — Espace parent : bilan Français de l'enfant (Claude)
//
// Un bilan, jamais du contenu (SEC-D6, RGPD-2) : cours ouverts, état et étape, scores de quiz, temps de travail,
// nombre de retours de la professeure. Ni énoncé, ni corrigé, ni texte écrit par l'enfant : l'API ne les envoie pas.
import { useEffect, useState } from "react";
import { formaterDate } from "../ui/Cadre.jsx";

const RUBRIQUES = { lire: "Lire et comprendre", grammaire: "Grammaire", conjugaison: "Conjugaison", redaction: "Rédaction" };
const ETATS = {
  pas_commence: ["Pas commencé", "neutre"],
  en_cours: ["En cours", "action"],
  a_reprendre: ["À revoir", "alerte"],
  maitrise: ["Maîtrisé", "ok"],
  reussi: ["Réussi", "ok"],
};
const minutes = (m) => (m < 60 ? `${Math.round(m)} min` : `${Math.floor(m / 60)} h ${String(Math.round(m % 60)).padStart(2, "0")}`);

export default function BilanFrancais({ eleveId, appeler }) {
  const [b, setB] = useState(null);
  useEffect(() => {
    appeler(`/parents/enfants/${eleveId}/francais`).then(setB, () => {});
  }, [appeler, eleveId]);

  if (!b) return <section className="carte"><p className="doux">Chargement du bilan de français…</p></section>;
  const i = b.indicateurs;
  const r = b.retours;
  return (
    <>
      <section className="carte" aria-labelledby={`bilan-fr-${eleveId}`}>
        <h2 id={`bilan-fr-${eleveId}`}>
          Le français de {b.eleve.prenom} <span className="doux petit">{b.eleve.classe} · {b.eleve.niveau}</span>
        </h2>
        {!b.acces && (
          <p className="info" role="note">
            Le français n'est pas ouvert à la classe de {b.eleve.prenom} en ce moment : aucun cours n'est affiché.
          </p>
        )}
        <div className="kpis" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))" }}>
          <div className="kpi"><div className="libelle">Cours commencés</div><div className="valeur">{i.commences} / {i.cours}</div></div>
          <div className="kpi"><div className="libelle">Cours terminés</div><div className="valeur">{i.termines}</div><div className="sous">maîtrisés ou réussis</div></div>
          <div className="kpi"><div className="libelle">Travail sur 7 jours</div><div className="valeur">{minutes(i.minutes_7_jours)}</div></div>
          <div className="kpi">
            <div className="libelle">Dernière activité</div>
            <div className="valeur fr-valeur-petite">{i.derniere_activite ? formaterDate(i.derniere_activite) : "—"}</div>
          </div>
        </div>
      </section>

      <div className="fr-deux">
        <section className="carte" aria-labelledby={`cours-fr-${eleveId}`}>
          <h3 id={`cours-fr-${eleveId}`}>Cours ouverts par la professeure</h3>
          {b.cours.length === 0 ? (
            <p className="doux">Aucun cours de français n'est ouvert pour l'instant.</p>
          ) : (
            <ul className="fr-liste">
              {b.cours.map((c) => {
                const [libelle, ton] = ETATS[c.etat] ?? [c.etat, "neutre"];
                return (
                  <li key={`${c.type}-${c.titre}`}>
                    <div>
                      <strong>{c.titre}</strong>
                      <div className="doux petit">
                        {RUBRIQUES[c.rubrique] ?? "Français"} · étape {c.etape} sur 7
                        {c.type === "dossier" && c.total ? ` · quiz ${c.score}/${c.total}` : ""}
                      </div>
                    </div>
                    <span className={`badge ${ton}`}>{libelle}</span>
                  </li>
                );
              })}
            </ul>
          )}
        </section>
        <div className="fr-cote">
          <section className="carte" aria-labelledby={`aider-fr-${eleveId}`}>
            <h3 id={`aider-fr-${eleveId}`}>Comment l'aider</h3>
            {b.a_revoir.length ? (
              <>
                <p>Ces cours sont à revoir : proposez-lui d'y retourner, étape « Comprendre » puis exercices.</p>
                <ul>{b.a_revoir.map((t) => <li key={t}>{t}</li>)}</ul>
              </>
            ) : (
              <p className="doux">Rien de particulier à revoir. Un peu de lecture chaque jour reste le meilleur entraînement.</p>
            )}
          </section>
          <section className="carte" aria-labelledby={`retours-fr-${eleveId}`}>
            <h3 id={`retours-fr-${eleveId}`}>Retours de la professeure</h3>
            <p>
              {r.relus} texte{r.relus > 1 ? "s" : ""} relu{r.relus > 1 ? "s" : ""} par la professeure
              {r.remis ? ` · ${r.remis} en attente de relecture` : ""}.
            </p>
          </section>
          <p className="info petit" role="note">
            Par respect de la vie privée de {b.eleve.prenom}, ses textes et ses réponses rédigées ne sont pas montrés ici :
            vous voyez le bilan de son travail.
          </p>
        </div>
      </div>
    </>
  );
}
