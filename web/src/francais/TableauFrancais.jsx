// Issue #231 — Tableau de bord du professeur de français (Claude)
import { useEffect, useState } from "react";
import { Erreur } from "../composants.jsx";
import { useApi } from "../enseignant/useApi.js";
import { Lien } from "../navigation.js";
import { Vide } from "../ui/Cadre.jsx";
import Icone from "../ui/Icone.jsx";

const RUBRIQUES = { lire: "Lire et comprendre", grammaire: "Grammaire", conjugaison: "Conjugaison", redaction: "Rédaction" };

// États calculés par l'API à partir des règles existantes (maîtrise du moteur ; score distinct pour les quiz).
const ETATS = {
  maitrise: ["Maîtrisé", "m"],
  reussi: ["Réussi", "m"],
  en_cours: ["En cours", "c"],
  a_reprendre: ["À reprendre", "r"],
  pas_commence: ["Pas commencé", "n"],
};

// #111 et calendrier A4 : seul le parcours guidé est disponible pour le pilote.
const PRESENTATIONS = [
  ["guide", "Parcours guidé", null],
  ["brevet", "Objectif brevet", "Prévu au plus tard le 1er mars 2027"],
  ["bibliotheque", "Bibliothèque", "Prévu en février 2027"],
];
const ORIGINES = { defaut: "par défaut", groupe: "réglage de la classe", seance: "réglage de la séance" };

const date = (iso) => {
  if (!iso) return "jamais";
  const jours = Math.floor((Date.now() - new Date(iso).getTime()) / 86_400_000);
  return jours <= 0 ? "aujourd'hui" : jours === 1 ? "hier" : `il y a ${jours} jours`;
};

/** Accueil du professeur de français : sa classe en un écran, et ce qu'il a à faire. */
export default function TableauFrancais({ jeton, onExpire, validateur = false }) {
  const { appeler, erreur } = useApi(jeton, onExpire);
  const [classes, setClasses] = useState(null);
  const [classeId, setClasseId] = useState(null);
  const [t, setT] = useState(null);

  useEffect(() => {
    appeler("/francais/classes").then(
      (c) => {
        setClasses(c);
        if (c.length) setClasseId(c[0].id);
      },
      () => setClasses([]),
    );
  }, [appeler]);

  useEffect(() => {
    if (!classeId) return;
    setT(null);
    appeler(`/francais/classes/${classeId}/tableau`).then(setT, () => {});
  }, [appeler, classeId]);

  if (classes === null) return erreur ? <Erreur message={erreur} /> : <p className="doux">Chargement…</p>;
  if (classes.length === 0) {
    return (
      <section className="carte">
        <Erreur message={erreur} />
        <Vide icone="classes">
          Vous n'avez pas encore de classe de français. Créez-la dans « Mes classes » ; en période de pilote, c'est
          l'administrateur qui l'ouvre comme classe pilote.
        </Vide>
      </section>
    );
  }

  return (
    <div className="fr-prof">
      <Erreur message={erreur} />
      <div className="fr-prof-barre">
        <label htmlFor="fr-classe">Classe</label>
        <select id="fr-classe" value={classeId ?? ""} onChange={(e) => setClasseId(Number(e.target.value))}>
          {classes.map((c) => (
            <option key={c.id} value={c.id}>
              {c.code} · {c.niveau}
              {c.acces_eleves ? "" : " (élèves sans accès)"}
            </option>
          ))}
        </select>
        <div className="fr-actions">
          <Lien vers="/enseignant/classes" className="bouton secondaire petit">
            <Icone nom="cours" /> Ouvrir ou fermer des cours
          </Lien>
          <Lien vers="/francais" className="bouton secondaire petit">
            <Icone nom="pdf" /> Dossiers et PDF
          </Lien>
          <Lien vers="/enseignant/vue-eleve" className="bouton secondaire petit">
            <Icone nom="oeil" /> Voir comme un élève
          </Lien>
        </div>
      </div>
      {!t ? <p className="doux">Chargement…</p> : <Tableau t={t} validateur={validateur} />}
    </div>
  );
}

function Tableau({ t, validateur }) {
  const i = t.indicateurs;
  const accompagner = t.eleves.filter((e) => e.a_accompagner);
  return (
    <>
      {!t.classe.acces_eleves && (
        <p className="info" role="note">
          Les élèves de {t.classe.code} n'ont pas accès au français : la classe n'est pas (ou plus) classe pilote.
          Leur suivi reste consultable.
        </p>
      )}
      <div className="kpis">
        <div className="kpi"><div className="libelle">Élèves actifs sur 7 jours</div><div className="valeur">{i.actifs_7j} / {i.eleves}</div></div>
        <div className="kpi"><div className="libelle">Cours ouverts</div><div className="valeur">{i.cours_ouverts}</div></div>
        <div className="kpi">
          <div className="libelle">Maîtrise moyenne</div>
          <div className="valeur">{i.maitrise_moyenne === null ? "—" : `${Math.round(i.maitrise_moyenne * 100)} %`}</div>
          <div className="sous">sur les cours commencés, exercices corrigés automatiquement</div>
        </div>
        <div className="kpi">
          <div className="libelle">Élèves à accompagner</div>
          <div className={`valeur${i.a_accompagner ? " fr-valeur-alerte" : ""}`}>{i.a_accompagner}</div>
        </div>
      </div>

      <div className="fr-deux">
        <section className="carte" aria-labelledby="fr-a-faire">
          <h2 id="fr-a-faire">À faire</h2>
          <ul className="fr-liste">
            {validateur && (
              <li>
                <div>
                  <strong>
                    {t.a_valider.reduce((n, c) => n + c.questions, 0) || "Aucune"} question
                    {t.a_valider.reduce((n, c) => n + c.questions, 0) > 1 ? "s" : ""} à valider
                  </strong>
                  <div className="doux petit">
                    {t.a_valider.length ? t.a_valider.map((c) => `${c.titre} (${c.niveau})`).join(" · ") : "Votre file est vide."}
                  </div>
                </div>
                {t.a_valider.length > 0 && (
                  <Lien vers="/enseignant/validation" className="bouton secondaire petit">Valider</Lien>
                )}
              </li>
            )}
            <li>
              <div>
                <strong>Élèves à accompagner</strong>
                <div className="doux petit">
                  {accompagner.length ? accompagner.map((e) => e.prenom).join(", ") : "Aucun élève en difficulté sur un cours."}
                </div>
              </div>
            </li>
            <li>
              <div>
                <strong>Rédactions en ligne</strong>
                <div className="doux petit">
                  {t.redaction_ouverte ? "Ouvertes : relisez les textes remis." : "Fermées (RGPD-2) : les élèves rédigent sur copie."}
                </div>
              </div>
              {t.redaction_ouverte ? (
                <Lien vers="/enseignant/redactions" className="bouton secondaire petit">Relire</Lien>
              ) : (
                <span className="badge neutre">Fermé</span>
              )}
            </li>
          </ul>
        </section>
        <section className="carte" aria-labelledby="fr-presentation">
          <h2 id="fr-presentation">Présentation pour {t.classe.code}</h2>
          <ul className="fr-liste">
            {PRESENTATIONS.map(([code, libelle, prevu]) => (
              <li key={code}>
                <div>
                  <strong>{libelle}</strong>
                  <div className="doux petit">{t.presentation.mode === code ? `Origine : ${ORIGINES[t.presentation.origine]}` : prevu}</div>
                </div>
                <span className={`badge ${t.presentation.mode === code ? "ok" : "neutre"}`}>
                  {t.presentation.mode === code ? "Active" : "Bientôt"}
                </span>
              </li>
            ))}
          </ul>
        </section>
      </div>

      <section className="carte" aria-labelledby="fr-suivi">
        <div className="carte-titre">
          <h2 id="fr-suivi">Suivi de la classe {t.classe.code}</h2>
          <span className="doux petit">La correction humaine n'entre jamais dans la maîtrise.</span>
        </div>
        {t.eleves.length === 0 || t.cours.length === 0 ? (
          <Vide icone="classes">
            {t.eleves.length === 0 ? "Aucun élève inscrit dans cette classe." : "Aucun cours ouvert à cette classe."}
          </Vide>
        ) : (
          <div className="tableau-defilant" tabIndex={0} role="region" aria-label="Suivi de la classe, tableau défilant">
            <table className="fr-table fr-suivi">
              <thead>
                <tr>
                  <th scope="col">Élève</th>
                  {t.cours.map((c) => (
                    <th scope="col" key={c.cle}>
                      <span className="fr-entete-cours">{c.titre}</span>
                      <span className="doux">{RUBRIQUES[c.rubrique] ?? ""}</span>
                    </th>
                  ))}
                  <th scope="col">Dernière activité</th>
                </tr>
              </thead>
              <tbody>
                {t.eleves.map((e) => (
                  <tr key={e.id}>
                    <th scope="row">{e.prenom}</th>
                    {t.cours.map((c) => (
                      <td key={c.cle}><Etat etat={e.cours[c.cle]} /></td>
                    ))}
                    <td className={e.actif_7j ? "" : "doux"}>{date(e.derniere_activite)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </>
  );
}

function Etat({ etat }) {
  if (!etat) return <span className="doux">—</span>;
  const [libelle, ton] = ETATS[etat.etat] ?? [etat.etat, "n"];
  const detail = etat.score !== undefined && etat.score !== null ? ` ${etat.score}/${etat.total}` : "";
  return <span className={`fr-niveau ${ton}`}>{libelle}{detail}</span>;
}
