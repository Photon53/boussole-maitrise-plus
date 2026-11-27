// Issue #231 — Espace administrateur Français (Claude)
import { useEffect, useState } from "react";
import { Erreur } from "../composants.jsx";
import { useApi } from "../enseignant/useApi.js";
import { Lien, naviguer } from "../navigation.js";
import { Vide } from "../ui/Cadre.jsx";
import Icone from "../ui/Icone.jsx";

// Rubriques affichées (FR-UI-D1) : les dossiers forment « Lire et comprendre » ; « Mon cours » = ressources.
export const RUBRIQUES = {
  lire: "Lire et comprendre",
  grammaire: "Grammaire",
  conjugaison: "Conjugaison",
  redaction: "Rédaction",
  mon_cours: "Ressources",
};

const STATUTS = {
  pret: ["Prêt", "ok"],
  a_valider: ["À valider", "alerte"],
  revision_a_valider: ["Révision à valider", "alerte"],
  a_corriger: ["À corriger", "ko"],
  brouillon: ["Brouillon", "neutre"],
  vide: ["Sans question", "neutre"],
  masque: ["Masqué", "neutre"],
};

const GRAVITES = {
  bloquant: ["Bloquant", "ko"],
  a_faire: ["À faire", "alerte"],
  attention: ["Attention", "accent"],
  info: ["Info", "neutre"],
};

/** Écran qui traite chaque alerte : l'administrateur agit depuis la synthèse, sans chercher la page. */
const ACTIONS = {
  domaines: ["Ouvrir les domaines", "/admin/configuration"],
  "classes-pilotes": ["Gérer les classes pilotes", "/admin/configuration"],
  equipe: ["Gérer l'équipe", "/admin/professeurs"],
  classes: ["Voir les élèves et classes", "/admin/eleves?onglet=classes"],
  "validation-questions": ["Valider les questions", "/admin/exercices?statut=a-valider"],
  "validation-dossiers": ["Valider les dossiers", "/francais"],
};

const pct = (n, total) => (total ? Math.round((100 * n) / total) : 0);

/** Synthèse du français pour l'administrateur : ce qui est prêt, ce qui bloque, et où agir. */
export default function FrancaisAdmin({ jeton, onExpire, onDomaine }) {
  const { appeler, erreur } = useApi(jeton, onExpire);
  const [s, setS] = useState(null);
  const [rubrique, setRubrique] = useState("");

  useEffect(() => {
    appeler("/admin/francais/synthese").then(setS, () => {});
  }, [appeler]);

  /** Les pages de l'administration filtrent par domaine : passer en Français collège avant d'y aller. */
  function aller(vers) {
    if (vers.startsWith("/admin/") && onDomaine) onDomaine("francais-college");
    naviguer(vers);
  }

  if (!s) return erreur ? <Erreur message={erreur} /> : <p className="doux">Chargement…</p>;

  const college = s.domaines.find((d) => d.code === "francais-college");
  const c = s.chiffres;
  const cours = s.cours.filter((x) => x.statut !== "masque" && (!rubrique || x.rubrique === rubrique));
  const parNiveau = Object.groupBy ? Object.groupBy(cours, (x) => x.niveau) : grouper(cours);
  const rubriquesPresentes = Object.keys(RUBRIQUES).filter((r) => s.cours.some((x) => x.rubrique === r && x.statut !== "masque"));

  return (
    <div className="fr-admin">
      <Erreur message={erreur} />
      <div className="fr-actions" role="group" aria-label="Actions du français">
        <button className="petit" onClick={() => aller(ACTIONS["validation-questions"][1])}>
          <Icone nom="exercices" /> Valider les questions
        </button>
        <Lien vers="/francais" className="bouton secondaire petit">
          <Icone nom="pdf" /> Dossiers, validation et PDF
        </Lien>
        <Lien vers="/admin/vue-eleve" className="bouton secondaire petit">
          <Icone nom="oeil" /> Voir comme un élève
        </Lien>
        <button className="secondaire petit" onClick={() => aller("/admin/configuration")}>
          <Icone nom="bouclier" /> Domaines et classes pilotes
        </button>
        <button className="secondaire petit" onClick={() => aller("/admin/professeurs")}>
          <Icone nom="professeurs" /> Équipe et habilitations
        </button>
      </div>

      <section className="carte fr-alertes" aria-labelledby="fr-a-traiter">
        <div className="carte-titre">
          <h2 id="fr-a-traiter">À traiter</h2>
          <span className="doux">{s.alertes.length ? `${s.alertes.length} point${s.alertes.length > 1 ? "s" : ""}` : ""}</span>
        </div>
        {s.alertes.length === 0 ? (
          <p className="fr-tout-va">
            <Icone nom="ok" /> Rien ne bloque les classes pilotes.
          </p>
        ) : (
          <ul className="fr-liste-alertes">
            {s.alertes.map((a, i) => (
              <li key={i}>
                <span className={`badge ${GRAVITES[a.gravite][1]}`}>{GRAVITES[a.gravite][0]}</span>
                <span className="fr-message">{a.message}</span>
                {ACTIONS[a.action] && (
                  <button className="lien" onClick={() => aller(ACTIONS[a.action][1])}>
                    {ACTIONS[a.action][0]}
                  </button>
                )}
              </li>
            ))}
          </ul>
        )}
      </section>

      <div className="kpis">
        <Indicateur libelle="Cours prêts" valeur={`${c.cours_prets} / ${c.cours}`} part={pct(c.cours_prets, c.cours)}
          sous="validés, donc proposables aux classes" />
        <Indicateur libelle="Questions validées" valeur={`${c.questions_validees} / ${c.questions}`}
          part={pct(c.questions_validees, c.questions)} sous="par un validateur autre que l'auteur" />
        <Indicateur libelle="Classes pilotes" valeur={c.classes_pilotes}
          sous={`${c.eleves_pilotes} élève${c.eleves_pilotes > 1 ? "s" : ""} inscrit${c.eleves_pilotes > 1 ? "s" : ""}`} />
        <Indicateur libelle="Français collège" valeur={college.actif ? "Actif" : "Inactif"}
          sous={college.public ? "Ouvert au public" : "Équipe et classes pilotes seulement"} />
      </div>

      <div className="fr-colonnes">
        <div className="fr-principal">
          <section className="carte" aria-labelledby="fr-niveaux">
            <h2 id="fr-niveaux">Par niveau</h2>
            <div className="tableau-defilant">
              <table className="fr-table">
                <thead>
                  <tr>
                    <th scope="col">Niveau</th>
                    <th scope="col">Cours prêts</th>
                    <th scope="col">Questions validées</th>
                    <th scope="col">Validateurs</th>
                    <th scope="col">Classes pilotes</th>
                  </tr>
                </thead>
                <tbody>
                  {s.niveaux.map((n) => (
                    <tr key={n.niveau}>
                      <th scope="row">{n.niveau}</th>
                      <td>{n.cours_prets} / {n.cours}</td>
                      <td>
                        <Jauge part={pct(n.questions_validees, n.questions)} texte={`${n.questions_validees} / ${n.questions}`} />
                      </td>
                      <td>{n.validateurs.length ? n.validateurs.join(", ") : <span className="alerte-douce">Aucun</span>}</td>
                      <td>{n.classes_pilotes.length ? n.classes_pilotes.join(", ") : <span className="doux">—</span>}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </section>

          <section className="carte" aria-labelledby="fr-cours">
            <div className="carte-titre">
              <h2 id="fr-cours">Cours</h2>
              <div className="fr-filtres" role="group" aria-label="Filtrer par rubrique">
                <button className={rubrique ? "secondaire petit" : "petit"} aria-pressed={!rubrique} onClick={() => setRubrique("")}>
                  Toutes
                </button>
                {rubriquesPresentes.map((r) => (
                  <button key={r} className={rubrique === r ? "petit" : "secondaire petit"} aria-pressed={rubrique === r}
                    onClick={() => setRubrique(r)}>
                    {RUBRIQUES[r]}
                  </button>
                ))}
              </div>
            </div>
            {cours.length === 0 ? (
              <Vide icone="cours">Aucun cours de français importé dans cette rubrique.</Vide>
            ) : (
              Object.entries(parNiveau).map(([niveau, liste]) => (
                <div key={niveau} className="fr-groupe-niveau">
                  <h3>{niveau}</h3>
                  <div className="tableau-defilant">
                    <table className="fr-table fr-cours">
                      <thead>
                        <tr>
                          <th scope="col">Cours</th>
                          <th scope="col">Rubrique</th>
                          <th scope="col">Validation</th>
                          <th scope="col">Ouvert à</th>
                          <th scope="col"><span className="visuellement-cache">Action</span></th>
                        </tr>
                      </thead>
                      <tbody>
                        {liste.map((x) => (
                          <LigneCours key={`${x.type}-${x.id}`} cours={x} aller={aller} />
                        ))}
                      </tbody>
                    </table>
                  </div>
                </div>
              ))
            )}
          </section>
        </div>

        <aside className="fr-cote">
          <section className="carte" aria-labelledby="fr-classes">
            <h2 id="fr-classes">Classes de français</h2>
            {s.classes.length === 0 ? (
              <p className="doux">Aucune classe de français.</p>
            ) : (
              <ul className="fr-liste">
                {s.classes.map((cl) => (
                  <li key={cl.id}>
                    <div>
                      <strong className="code">{cl.code}</strong>
                      {cl.pilote && <span className="badge ok">Pilote</span>}
                      <div className="doux petit">
                        {cl.niveau} · {cl.enseignant} · {cl.eleves} élève{cl.eleves > 1 ? "s" : ""} · {cl.cours_ouverts} cours ouvert{cl.cours_ouverts > 1 ? "s" : ""}
                      </div>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </section>
          <section className="carte" aria-labelledby="fr-sensibles">
            <h2 id="fr-sensibles">Fonctions sensibles</h2>
            <ul className="fr-liste">
              {s.fonctions.map((f) => (
                <li key={f.code}>
                  <div>
                    <strong>{f.libelle}</strong>
                    <div className="doux petit">
                      <code>{f.reglage}</code> · {f.decision}
                    </div>
                  </div>
                  <span className={`badge ${f.active ? "alerte" : "neutre"}`}>{f.active ? "Activée" : "Désactivée"}</span>
                </li>
              ))}
            </ul>
            <p className="doux petit">
              Lecture seule : ces fonctions se changent dans la configuration du serveur, sur décision du propriétaire.
            </p>
          </section>
          <section className="carte" aria-labelledby="fr-domaines">
            <h2 id="fr-domaines">Domaines</h2>
            <ul className="fr-liste">
              {s.domaines.map((d) => (
                <li key={d.code}>
                  <strong>{d.libelle}</strong>
                  <span className={`badge ${d.actif ? "ok" : "neutre"}`}>
                    {d.actif ? (d.public ? "Public" : "Actif, fermé au public") : "Inactif"}
                  </span>
                </li>
              ))}
            </ul>
          </section>
        </aside>
      </div>
    </div>
  );
}

function grouper(liste) {
  return liste.reduce((acc, x) => ({ ...acc, [x.niveau]: [...(acc[x.niveau] ?? []), x] }), {});
}

function Indicateur({ libelle, valeur, sous, part }) {
  return (
    <div className="kpi">
      <div className="libelle">{libelle}</div>
      <div className="valeur">{valeur}</div>
      {part !== undefined && <Jauge part={part} />}
      <div className="sous">{sous}</div>
    </div>
  );
}

function Jauge({ part, texte }) {
  return (
    <div className="fr-jauge">
      {texte && <span>{texte}</span>}
      <span className="fr-barre" role="img" aria-label={`${part} %`}>
        <span style={{ width: `${part}%` }} />
      </span>
    </div>
  );
}

function LigneCours({ cours: x, aller }) {
  const [libelle, ton] = STATUTS[x.statut] ?? [x.statut, "neutre"];
  const q = x.questions;
  return (
    <tr>
      <td>
        <strong>{x.titre}</strong>
        <div className="doux petit">
          {x.type === "dossier" ? `Dossier ${x.code} · v${x.version.validee ?? x.version.courante}` : x.code}
        </div>
      </td>
      <td>{RUBRIQUES[x.rubrique] ?? "—"}</td>
      <td>
        <span className={`badge ${ton}`}>{libelle}</span>
        {q && q.total > 0 && <Jauge part={pct(q.validees, q.total)} texte={`${q.validees} / ${q.total}`} />}
      </td>
      <td>{x.classes.length ? x.classes.join(", ") : <span className="doux">—</span>}</td>
      <td>
        {x.statut !== "pret" && x.statut !== "vide" && (
          <button className="lien" onClick={() => aller(x.type === "dossier" ? "/francais" : `/admin/exercices?q=${encodeURIComponent(x.code)}`)}>
            {x.type === "dossier" ? "Ouvrir le dossier" : "Valider"}
          </button>
        )}
      </td>
    </tr>
  );
}
