// Issue #231 — Rail des sept étapes, commun aux dossiers et aux cours de français (Claude)
//
// Méthode commune de #177 (FR-UI-D2) : Découvrir, Comprendre, Appliquer, S'entraîner, Approfondir, Réinvestir,
// Consolider. Une étape sans activité dans ce cours est affichée, grisée, pour que l'élève voie toujours la même
// méthode. Ce rail ne choisit aucune question : il range ce que le cours contient déjà (FR-UI-D3).

export const SEPT_ETAPES = ["Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider"];

/**
 * `etapes` : [{ numero (1 à 7), titre, detail?, disponible }] ; `active` : numéro de l'étape affichée ;
 * `faites` : numéros des étapes déjà vues ; `onChoisir(numero)`.
 */
export default function RailEtapes({ titreCours, rubrique, etapes, active, faites = [], onChoisir, onRetour, libelleRetour = "Mes cours" }) {
  const courante = etapes.find((e) => e.numero === active);
  return (
    <nav className="rail-etapes" aria-label="Étapes du cours">
      {onRetour && (
        <button className="lien rail-retour" onClick={onRetour}>
          ← {libelleRetour}
        </button>
      )}
      <div className="rail-titre">
        {rubrique && <span className="rail-rubrique">{rubrique}</span>}
        <strong>{titreCours}</strong>
      </div>
      <p className="rail-mobile" aria-hidden="true">
        Étape {active} sur 7 · {courante?.titre}
      </p>
      <ol className="rail-liste">
        {etapes.map((e) => {
          const fait = faites.includes(e.numero) && e.numero !== active;
          return (
            <li key={e.numero}>
              <button
                type="button"
                className={`rail-etape${e.numero === active ? " active" : ""}${fait ? " faite" : ""}`}
                aria-current={e.numero === active ? "step" : undefined}
                disabled={!e.disponible}
                onClick={() => onChoisir(e.numero)}
              >
                <span className="rail-rond" aria-hidden="true">{fait ? "✓" : e.numero}</span>
                <span className="rail-texte">
                  <span>{e.titre}</span>
                  <small>{e.disponible ? e.detail : "Pas d'activité dans ce cours"}</small>
                </span>
              </button>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/** Boutons « étape précédente / suivante » sous le contenu d'une étape. */
export function NavigationEtapes({ etapes, active, onChoisir }) {
  const disponibles = etapes.filter((e) => e.disponible);
  const i = disponibles.findIndex((e) => e.numero === active);
  const avant = disponibles[i - 1];
  const apres = disponibles[i + 1];
  return (
    <div className="navigation-etapes">
      {avant ? (
        <button type="button" className="secondaire" onClick={() => onChoisir(avant.numero)}>
          ← {avant.titre}
        </button>
      ) : <span />}
      {apres && (
        <button type="button" onClick={() => onChoisir(apres.numero)}>
          {apres.titre} →
        </button>
      )}
    </div>
  );
}
