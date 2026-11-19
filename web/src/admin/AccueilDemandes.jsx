// Issue #171 — Candidatures de professeurs et demandes de partenariat (Claude)
import { useCallback, useEffect, useState } from "react";
import { telechargerFichier } from "../api.js";
import { MATIERES, TYPES_STRUCTURE } from "../Collaborer.jsx";
import { Erreur, Onglets } from "../composants.jsx";
import { useApi } from "../enseignant/useApi.js";

export const FILES = [
  ["candidature", "Candidatures de professeurs"],
  ["partenariat", "Partenariats de structures"],
];
export const STATUTS = { nouveau: "Nouveau", "a-traiter": "À traiter", traite: "Traité" };
export const ISSUES = { "suite-demandee": "Suite demandée", refus: "Refus", cloture: "Clôture" };
const LIBELLES_MATIERES = Object.fromEntries(MATIERES);
const LIBELLES_STRUCTURES = Object.fromEntries(TYPES_STRUCTURE);

/**
 * Accueil et demandes (issue #171) : deux files distinctes, candidatures et partenariats. Traiter une demande ne
 * crée ni compte, ni habilitation, ni contrat : la suite (sélection, préparation des intervenants) relève de #21.
 */
export default function AccueilDemandes({ jeton, onExpire }) {
  const { appeler, erreur } = useApi(jeton, onExpire);
  const [file, setFile] = useState("candidature");
  const [filtres, setFiltres] = useState({ statut: "", q: "", depuis: "" });
  const [page, setPage] = useState(1);
  const [resultat, setResultat] = useState(null);
  const [ouverte, setOuverte] = useState(null);

  const charger = useCallback(() => {
    const p = new URLSearchParams({ type: file, page: String(page) });
    if (filtres.statut) p.set("statut", filtres.statut);
    if (filtres.q.trim()) p.set("q", filtres.q.trim());
    if (filtres.depuis) p.set("depuis", new Date(filtres.depuis).toISOString());
    appeler(`/admin/accueil/demandes?${p}`).then(setResultat, () => {});
  }, [appeler, file, page, filtres]);

  useEffect(() => {
    charger();
  }, [charger]);

  const changer = (cle) => (e) => {
    setFiltres({ ...filtres, [cle]: e.target.value });
    setPage(1);
  };
  const pages = resultat ? Math.max(1, Math.ceil(resultat.total / resultat.taille_page)) : 1;

  return (
    <section className="carte">
      <Onglets
        valeur={file}
        options={FILES}
        onChange={(f) => {
          setFile(f);
          setPage(1);
          setOuverte(null);
        }}
      />
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "end" }}>
        <label>
          Rechercher
          <input type="search" value={filtres.q} onChange={changer("q")} maxLength={100} placeholder="Référence, nom, e-mail, structure" />
        </label>
        <label>
          Statut
          <select value={filtres.statut} onChange={changer("statut")}>
            <option value="">Tous</option>
            {Object.entries(STATUTS).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </label>
        <label>
          Depuis le
          <input type="date" value={filtres.depuis} onChange={changer("depuis")} />
        </label>
      </div>
      <Erreur message={erreur} />
      {resultat === null && !erreur && <p className="doux">Chargement…</p>}
      {resultat?.total === 0 && <p className="doux">Aucune demande dans cette file.</p>}
      {resultat?.demandes.length > 0 && (
        <div className="tableau-defilant">
          <table>
            <thead>
              <tr>
                <th>Référence</th>
                <th>Date</th>
                <th>{file === "candidature" ? "Candidat" : "Structure"}</th>
                <th>Statut</th>
                <th>Responsable</th>
              </tr>
            </thead>
            <tbody>
              {resultat.demandes.map((d) => (
                <tr key={d.id}>
                  <td>
                    <button className="lien" aria-expanded={ouverte === d.id} onClick={() => setOuverte(ouverte === d.id ? null : d.id)}>
                      {d.reference}
                    </button>
                  </td>
                  <td>{new Date(d.cree_le).toLocaleDateString("fr-FR")}</td>
                  <td>{file === "candidature" ? d.contact : `${d.structure_nom} (${d.contact})`}</td>
                  <td>
                    {STATUTS[d.statut]}
                    {d.issue && ` · ${ISSUES[d.issue]}`}
                  </td>
                  <td>{d.responsable ?? "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {pages > 1 && (
        <div className="actions">
          <button className="secondaire" disabled={page <= 1} onClick={() => setPage(page - 1)}>
            Précédentes
          </button>
          <span className="doux">
            Page {page} sur {pages}
          </span>
          <button className="secondaire" disabled={page >= pages} onClick={() => setPage(page + 1)}>
            Suivantes
          </button>
        </div>
      )}
      {ouverte && (
        <Fiche
          key={ouverte}
          id={ouverte}
          jeton={jeton}
          onExpire={onExpire}
          onChange={charger}
          onSupprimee={() => {
            setOuverte(null);
            charger();
          }}
        />
      )}
    </section>
  );
}

function Fiche({ id, jeton, onExpire, onChange, onSupprimee }) {
  const { appeler, erreur, setErreur } = useApi(jeton, onExpire);
  const [d, setD] = useState(null);
  const [moi, setMoi] = useState(null);
  const [notes, setNotes] = useState("");
  const [issue, setIssue] = useState("");

  useEffect(() => {
    appeler(`/admin/accueil/demandes/${id}`).then((x) => {
      setD(x);
      setNotes(x.notes_internes ?? "");
      setIssue(x.issue ?? "");
    }, () => {});
    appeler("/admin/moi").then(setMoi, () => {});
  }, [appeler, id]);

  async function traiter(changements) {
    try {
      const maj = await appeler(`/admin/accueil/demandes/${id}`, { methode: "POST", corps: changements });
      setD(maj);
      setIssue(maj.issue ?? "");
      onChange();
    } catch {
      // Message affiché par useApi.
    }
  }

  async function telecharger(chemin, nom) {
    try {
      await telechargerFichier(chemin, jeton, nom);
    } catch (e) {
      setErreur(e.message);
    }
  }

  async function supprimer() {
    if (!window.confirm(`Supprimer définitivement la demande ${d.reference}${d.a_un_cv ? " et son CV" : ""} ?`)) return;
    try {
      await appeler(`/admin/accueil/demandes/${id}`, { methode: "DELETE" });
      onSupprimee();
    } catch {
      // Message affiché par useApi.
    }
  }

  if (!d) return <Erreur message={erreur} />;
  return (
    <article className="carte" aria-label={`Demande ${d.reference}`}>
      <h3>
        {d.reference} — {d.type === "candidature" ? "candidature" : "partenariat"}
      </h3>
      <dl>
        {d.type === "partenariat" && (
          <>
            <dt>Structure</dt>
            <dd>
              {d.structure_nom} ({LIBELLES_STRUCTURES[d.structure_type] ?? d.structure_type})
            </dd>
          </>
        )}
        <dt>Contact</dt>
        <dd>
          {d.prenom} {d.nom}
          {d.fonction && `, ${d.fonction}`}
        </dd>
        <dt>E-mail</dt>
        <dd>{d.email}</dd>
        {d.telephone && (
          <>
            <dt>Téléphone</dt>
            <dd>{d.telephone}</dd>
          </>
        )}
        {d.type === "candidature" && (
          <>
            <dt>Matières</dt>
            <dd>{d.matieres.map((m) => LIBELLES_MATIERES[m] ?? m).join(", ")}</dd>
            <dt>Niveaux</dt>
            <dd>{d.niveaux.join(", ")}</dd>
            <dt>Disponibilités</dt>
            <dd>{d.disponibilites ?? "—"}</dd>
          </>
        )}
        <dt>{d.type === "candidature" ? "Message" : "Partenariat envisagé"}</dt>
        <dd style={{ whiteSpace: "pre-wrap" }}>{d.message ?? "—"}</dd>
        <dt>Reçue le</dt>
        <dd>{new Date(d.cree_le).toLocaleString("fr-FR")}</dd>
      </dl>
      <div className="actions">
        {d.a_un_cv && (
          <button className="secondaire" onClick={() => telecharger(`/admin/accueil/demandes/${id}/cv`, `CV-${d.reference}.pdf`)}>
            Télécharger le CV
          </button>
        )}
        <button className="secondaire" onClick={() => telecharger(`/admin/accueil/demandes/${id}/export`, `demande-${d.reference}.json`)}>
          Exporter (droit d'accès)
        </button>
      </div>

      <h4>Traitement</h4>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 12, alignItems: "end" }}>
        <label>
          Statut
          <select aria-label="Statut" value={d.statut} onChange={(e) => e.target.value !== "traite" && traiter({ statut: e.target.value })}>
            {Object.entries(STATUTS).map(([v, l]) => (
              <option key={v} value={v} disabled={v === "traite"}>
                {l}
              </option>
            ))}
          </select>
        </label>
        <label>
          Issue
          <select aria-label="Issue" value={issue} onChange={(e) => setIssue(e.target.value)}>
            <option value="">Choisir…</option>
            {Object.entries(ISSUES).map(([v, l]) => (
              <option key={v} value={v}>
                {l}
              </option>
            ))}
          </select>
        </label>
        <button disabled={!issue} onClick={() => traiter({ statut: "traite", issue })}>
          Marquer traitée
        </button>
        {moi?.id && d.responsable_id !== moi.id && (
          <button className="lien" onClick={() => traiter({ responsable_id: moi.id })}>
            M'en charger
          </button>
        )}
      </div>
      <label>
        Notes internes (visibles des administrateurs seulement)
        <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3} maxLength={3000} />
      </label>
      <div className="actions">
        <button className="secondaire" onClick={() => traiter({ notes_internes: notes })}>
          Enregistrer les notes
        </button>
        <button className="danger" onClick={supprimer}>
          Supprimer la demande{d.a_un_cv ? " et le CV" : ""}
        </button>
      </div>
      <p className="doux petit">
        Traiter une demande ne crée ni compte, ni habilitation, ni contrat. Une demande de suppression de la personne se traite ici.
      </p>
      <Erreur message={erreur} />
    </article>
  );
}
