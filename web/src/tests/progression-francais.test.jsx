// Issue #231 — « Ma progression » de l'élève de français (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import ProgressionFrancais, { quand, resumeRubrique } from "../eleve/ProgressionFrancais.jsx";
import { fausseApi } from "./setup.js";

const ETAPES = ["Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider"];
const chapitre = (id, titre, rubrique, etat, extra = {}) => ({
  cle: `chapitre-${id}`, type: "chapitre", id, titre, rubrique, competence_id: id * 10, a_une_lecon: true, nb_questions: 9,
  etat, maitrise: etat === "pas_commence" ? null : 0.5, reponses: 3, etape: etat === "maitrise" ? 7 : 3, derniere_activite: null, ...extra,
});
const ACCUEIL = {
  eleve: { prenom: "Lina", classe: "5E-FR-AAAAA", niveau: "5e" }, acces: true, etapes: ETAPES, redaction_ouverte: false,
  cours: [
    chapitre(1, "Les fonctions", "grammaire", "maitrise", { maitrise: 0.84, derniere_activite: "2026-11-27T09:00:00+00:00" }),
    chapitre(2, "Le présent", "conjugaison", "a_reprendre", { maitrise: 0.3, derniere_activite: "2026-11-15T09:00:00+00:00" }),
    chapitre(3, "L'imparfait", "conjugaison", "en_cours"),
    chapitre(4, "Raconter", "redaction", "pas_commence"),
  ],
};
const routes = (extra = {}) => ({
  "GET /francais/eleve/accueil": { json: ACCUEIL },
  "GET /eleves/moi/competences/10/avancement": { json: { competence_id: 10, reponses: 8, reussies_bases: 3, objectif_bases: 3, reussies_avancees: 1, objectif_avancees: 2, maitrise: 0.84, maitrisee: true } },
  "GET /cours/10": { json: { competence_id: 10, resume: "**COD** : complète le verbe sans préposition.", objectifs: [], methodes: [], erreurs_frequentes: [], ressources: [] } },
  ...extra,
});

describe("« Ma progression » en français (#231)", () => {
  it("résume une rubrique et date une activité", () => {
    expect(resumeRubrique([])).toMatchObject({ libelle: "Pas encore" });
    expect(resumeRubrique([{ etat: "maitrise" }, { etat: "reussi" }])).toMatchObject({ libelle: "Maîtrisé", termines: 2 });
    expect(resumeRubrique([{ etat: "a_reprendre" }, { etat: "en_cours" }])).toMatchObject({ libelle: "À revoir", termines: 0 });
    const t = new Date(2026, 10, 27, 12).getTime();
    expect(quand(new Date(2026, 10, 27, 8).toISOString(), t)).toBe("Aujourd'hui");
    expect(quand(new Date(2026, 10, 26, 8).toISOString(), t)).toBe("Hier");
    expect(quand(new Date(2026, 10, 15, 8).toISOString(), t)).toBe("Il y a 12 jours");
  });

  it("bilan du dernier cours, rubriques, à retravailler et dernières activités ; la rédaction sans pourcentage", async () => {
    const onOuvrir = vi.fn();
    fausseApi(routes());
    render(<ProgressionFrancais jeton="j" onExpire={vi.fn()} onOuvrir={onOuvrir} />);
    expect(await screen.findByText(/n'entrent pas dans ce calcul/)).toBeInTheDocument();
    const bilan = await screen.findByRole("region", { name: "Les fonctions" });
    expect(within(bilan).getByText("Bilan · étape 7 · Consolider")).toBeInTheDocument();
    expect(await within(bilan).findByText("Compétence maîtrisée · 84 %")).toBeInTheDocument();
    expect(within(bilan).getByText("3 / 3")).toBeInTheDocument();
    expect(within(bilan).getByText("1 / 2")).toBeInTheDocument();
    expect(await within(bilan).findByText(/complète le verbe sans préposition/)).toBeInTheDocument();
    await userEvent.click(within(bilan).getByRole("button", { name: "Revoir le cours" }));
    expect(onOuvrir).toHaveBeenCalledWith(ACCUEIL.cours[0]);

    const rubriques = screen.getByRole("region", { name: "Par rubrique" });
    const lignes = within(rubriques).getAllByRole("listitem");
    expect(lignes).toHaveLength(4);
    expect(lignes[0]).toHaveTextContent("Pas encore de cours ouvert en 5e"); // Lire et comprendre
    expect(lignes[1]).toHaveTextContent("Maîtrisé");
    expect(lignes[2]).toHaveTextContent("À revoir");
    expect(lignes[2]).toHaveTextContent("Le présent : à revoir · L'imparfait : en cours");
    expect(lignes[3]).toHaveTextContent("Sur copie");
    expect(lignes[3]).toHaveTextContent("sans pourcentage");
    expect(within(lignes[3]).queryByRole("img")).toBeNull();

    const aRevoir = screen.getByRole("region", { name: "À retravailler" });
    await userEvent.click(within(aRevoir).getByRole("button", { name: "Réviser" }));
    expect(onOuvrir).toHaveBeenLastCalledWith(ACCUEIL.cours[1], 2);
    const activites = within(screen.getByRole("region", { name: "Dernières activités" })).getAllByRole("listitem");
    expect(activites.map((li) => li.querySelector("strong").textContent)).toEqual(["Les fonctions", "Le présent"]);
  });

  it("sans activité : pas de bilan, une invitation", async () => {
    fausseApi(routes({ "GET /francais/eleve/accueil": { json: { ...ACCUEIL, cours: ACCUEIL.cours.map((c) => ({ ...c, derniere_activite: null })) } } }));
    render(<ProgressionFrancais jeton="j" onExpire={vi.fn()} onOuvrir={vi.fn()} />);
    expect(await screen.findByText(/ton bilan apparaîtra ici/)).toBeInTheDocument();
    expect(screen.getByText("Pas encore d'activité.")).toBeInTheDocument();
  });
});
