// Issue #231 — File de validation du français : liste à gauche, aperçu élève et corrigé à droite (Claude)
//
// Maquette 11 de la refonte. Remplace, pour le français, le tableau de validation (constat N6 de l'audit) par une file :
// les questions groupées par chapitre ; pour chacune, ce que l'élève verra (sans la solution), puis le corrigé, puis la
// décision. Les règles ne changent pas : l'API revérifie le périmètre et refuse qu'un auteur valide son propre contenu
// (V2-D15) ; toute décision est journalisée. « À corriger » demande ici un motif, noté au journal pour l'auteur.
import { useCallback, useEffect, useMemo, useState } from "react";
import { Erreur, solutionLisible } from "../composants.jsx";
import { decouperQcm } from "../eleve/Exercice.jsx";
import { EnonceFrancais } from "../eleve/ExerciceFrancais.jsx";
import { Maths } from "../maths.jsx";
import { useApi } from "./useApi.js";

const BASE = "/enseignants/validation";
export const STATUTS = [
  ["a-valider", "À valider"],
  ["a-corriger", "À corriger"],
  ["validee", "Validées"],
];
const RUBRIQUES = { grammaire: "Grammaire", conjugaison: "Conjugaison", redaction: "Rédaction", mon_cours: "Mon cours" };
const TYPES = { qcm: "QCM", texte: "Réponse courte", redaction: "Rédaction", numerique: "Nombre", expression: "Expression" };

/** Questions regroupées par chapitre, dans l'ordre de l'API (niveau, chapitre, compétence, difficulté). */
export function grouperParChapitre(questions) {
  const groupes = [];
  const index = new Map();
  for (const q of questions) {
    const cle = `${q.niveau}|${q.chapitre}`;
    if (!index.has(cle)) {
      index.set(cle, groupes.length);
      groupes.push({ cle, niveau: q.niveau, chapitre: q.chapitre, rubrique: q.rubrique, questions: [] });
    }
    groupes[index.get(cle)].questions.push(q);
  }
  return groupes;
}

/** Ce que l'élève verra : énoncé (phrase mise en scène), choix d'un QCM ou zone de réponse ; jamais la solution. */
function ApercuEleve({ question }) {
  const { intitule, options } = question.type === "qcm" ? decouperQcm(question.enonce) : { intitule: question.enonce, options: null };
  return (
    <section className="apercu-eleve" aria-label="Aperçu élève">
      <p className="surtitre-file">Aperçu élève</p>
      {question.type === "redaction" ? (
        question.enonce.split(/\n\s*\n/).map((p, i) => <p key={i} className="consigne-texte">{p}</p>)
      ) : (
        <EnonceFrancais intitule={intitule} />
      )}
      {options ? (
        <ul className="apercu-options">
          {options.map((o) => (
            <li key={o.lettre}>
              <span className="lettre" aria-hidden="true">{o.lettre}</span>
              <Maths enLigne texte={o.texte} />
            </li>
          ))}
        </ul>
      ) : (
        question.type !== "redaction" && <div className="apercu-saisie" aria-hidden="true">Zone de réponse de l'élève</div>
      )}
    </section>
  );
}

/** Corrigé : réponse attendue (texte du choix pour un QCM) et correction expliquée. */
function Corrige({ question }) {
  const options = question.type === "qcm" ? decouperQcm(question.enonce).options : null;
  const choix = options?.find((o) => o.lettre === question.solution.trim().toUpperCase());
  const c = question.correction;
  return (
    <section className="corrige-file" aria-label="Corrigé">
      <p className="surtitre-file">Corrigé · jamais montré à l'élève avant sa réponse</p>
      <p>
        <strong>{question.type === "redaction" ? "Attendus : " : "Réponse : "}</strong>
        {choix ? `${choix.lettre}) ${choix.texte}` : <Maths enLigne texte={solutionLisible(question.type, question.solution)} />}
      </p>
      {c?.methode && <p><strong>Méthode :</strong> <Maths enLigne texte={c.methode} /></p>}
      {c?.etapes?.length > 0 && (
        <ol className="etapes-correction">
          {c.etapes.map((e, i) => <li key={i}><Maths enLigne texte={e} /></li>)}
        </ol>
      )}
      {c?.resultat && <p><strong>Résultat :</strong> <Maths enLigne texte={c.resultat} /></p>}
      {c?.erreurs_frequentes?.length > 0 && (
        <p><strong>Erreur fréquente :</strong> {c.erreurs_frequentes.join(" ; ")}</p>
      )}
    </section>
  );
}

function Decision({ question, statut, onDecider, envoi }) {
  const [motif, setMotif] = useState("");
  useEffect(() => setMotif(""), [question.id]);
  if (!question.peut_valider) {
    return <p className="info" role="note">Cette question est hors de votre périmètre de validation : lecture seule.</p>;
  }
  const id = `motif-${question.id}`;
  return (
    <div className="decision-file">
      {statut !== "a-corriger" && (
        <>
          <label htmlFor={id}>Motif (obligatoire pour « À corriger »)</label>
          <textarea id={id} rows={3} maxLength={500} value={motif} placeholder="Ce qui doit être corrigé…" onChange={(e) => setMotif(e.target.value)} />
        </>
      )}
      <div className="actions decision-actions">
        {statut !== "a-corriger" && (
          <button type="button" className="secondaire danger" disabled={envoi || !motif.trim()} onClick={() => onDecider("a-corriger", motif)}>
            À corriger
          </button>
        )}
        {statut === "a-corriger" && (
          <button type="button" className="secondaire" disabled={envoi} onClick={() => onDecider("a-valider")}>
            Remettre à valider
          </button>
        )}
        {statut !== "validee" && (
          <button type="button" className="valider" disabled={envoi} onClick={() => onDecider("validee")}>
            ✓ Valider
          </button>
        )}
      </div>
    </div>
  );
}

export default function FileValidation({ jeton, onExpire, domaines }) {
  const { appeler, erreur, setErreur } = useApi(jeton, onExpire);
  const [statut, setStatut] = useState("a-valider");
  const [totaux, setTotaux] = useState({});
  const [questions, setQuestions] = useState(null);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [groupe, setGroupe] = useState(null);
  const [rang, setRang] = useState(0);
  const [envoi, setEnvoi] = useState(false);
  const [message, setMessage] = useState(null);

  const lister = useCallback(
    async (s, p = 1) => {
      const pages = await Promise.all(
        domaines.map((d) => appeler(`${BASE}/questions?domaine=${encodeURIComponent(d)}&statut=${s}&page=${p}`)),
      );
      return { elements: pages.flatMap((x) => x.elements), total: pages.reduce((n, x) => n + x.total, 0) };
    },
    [appeler, domaines],
  );

  const compter = useCallback(async () => {
    const t = {};
    for (const [s] of STATUTS) t[s] = (await lister(s)).total;
    setTotaux(t);
  }, [lister]);

  useEffect(() => {
    compter().catch(() => {});
  }, [compter]);

  useEffect(() => {
    let actif = true;
    setQuestions(null);
    setPage(1);
    lister(statut).then((r) => {
      if (!actif) return;
      setQuestions(r.elements);
      setTotal(r.total);
      setGroupe(null);
      setRang(0);
    }, () => {});
    return () => {
      actif = false;
    };
  }, [statut, lister]);

  const groupes = useMemo(() => grouperParChapitre(questions ?? []), [questions]);
  const courant = groupes.find((g) => g.cle === groupe) ?? groupes[0];
  const question = courant?.questions[Math.min(rang, courant.questions.length - 1)];
  const position = courant ? Math.min(rang, courant.questions.length - 1) : 0;

  async function suite() {
    const r = await lister(statut, page + 1);
    setQuestions((q) => [...q, ...r.elements]);
    setPage(page + 1);
  }

  async function decider(nouveau, motif) {
    setEnvoi(true);
    setMessage(null);
    try {
      await appeler(`${BASE}/questions/${question.id}/validation`, {
        methode: "POST",
        corps: { statut: nouveau, ...(nouveau === "a-corriger" ? { motif: motif.trim() } : {}) },
      });
      const libelle = { validee: "validée", "a-corriger": "renvoyée à l'auteur", "a-valider": "remise à valider" }[nouveau];
      setMessage(`Question ${question.code ?? ""} ${libelle}.`);
      // La question quitte cette file ; on reste sur le même chapitre, à la question suivante.
      setQuestions((qs) => qs.filter((q) => q.id !== question.id));
      setTotal((t) => t - 1);
      compter().catch(() => {});
    } catch {
      // Message d'erreur de l'API affiché (par exemple : auteur de la question).
    } finally {
      setEnvoi(false);
    }
  }

  return (
    <section className="file-validation" aria-labelledby="titre-file">
      <div className="file-entete">
        <h2 id="titre-file">File de validation</h2>
        <p className="doux">
          Vous ne pouvez pas valider un contenu dont vous êtes l'auteur (V2-D15). Toute décision est journalisée.
        </p>
        <div className="file-statuts" role="tablist" aria-label="Statut">
          {STATUTS.map(([s, l]) => (
            <button
              key={s}
              role="tab"
              aria-selected={statut === s}
              className={statut === s ? "file-statut active" : "file-statut"}
              onClick={() => {
                setStatut(s);
                setMessage(null);
                setErreur(null);
              }}
            >
              {l} <span className="compte">{totaux[s] ?? "…"}</span>
            </button>
          ))}
        </div>
      </div>
      {message && <p className="succes" role="status">{message}</p>}
      <Erreur message={erreur} />
      {questions === null && !erreur && <p className="doux">Chargement…</p>}
      {questions?.length === 0 && <p className="doux">Aucune question dans cette file.</p>}
      {courant && (
        <div className="file-grille">
          <nav className="file-liste" aria-label="Chapitres">
            <ul>
              {groupes.map((g) => (
                <li key={g.cle}>
                  <button
                    type="button"
                    className={g.cle === courant.cle ? "file-chapitre actif" : "file-chapitre"}
                    aria-current={g.cle === courant.cle ? "true" : undefined}
                    onClick={() => {
                      setGroupe(g.cle);
                      setRang(0);
                      setMessage(null);
                    }}
                  >
                    <span className="file-tag">{g.niveau} · {RUBRIQUES[g.rubrique] ?? "Français"}</span>
                    <strong>{g.chapitre}</strong>
                    <span className="doux petit">
                      {g.questions.length} question{g.questions.length > 1 ? "s" : ""}
                      {g.questions[0]?.auteur ? ` · auteur : ${g.questions[0].auteur}` : ""}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
            {questions.length < total && (
              <button type="button" className="secondaire" onClick={suite}>Charger la suite ({total - questions.length})</button>
            )}
          </nav>
          <article className="file-detail carte" aria-labelledby="titre-question">
            <div className="file-detail-entete">
              <h3 id="titre-question">
                {question.code ?? "Question"} · question {position + 1} sur {courant.questions.length}
              </h3>
              <span className="badge neutre">{TYPES[question.type] ?? question.type} · difficulté {question.difficulte}</span>
            </div>
            <p className="doux petit">{question.competence}</p>
            {question.motif_correction && (
              <p className="avertissement" role="note"><strong>Motif du renvoi :</strong> {question.motif_correction}</p>
            )}
            <ApercuEleve question={question} />
            <Corrige question={question} />
            <p className="doux petit">
              Auteur : {question.auteur ?? "—"} · source : {question.source}
              {question.licence_source ? ` (${question.licence_source})` : ""}
              {question.valide_par ? ` · décision : ${question.valide_par}` : ""}
            </p>
            <Decision question={question} statut={statut} onDecider={decider} envoi={envoi} />
            <div className="actions file-navigation">
              <button type="button" className="secondaire" disabled={position === 0} onClick={() => setRang(position - 1)}>
                ← Question précédente
              </button>
              <button type="button" className="secondaire" disabled={position >= courant.questions.length - 1} onClick={() => setRang(position + 1)}>
                Question suivante →
              </button>
            </div>
          </article>
        </div>
      )}
    </section>
  );
}
