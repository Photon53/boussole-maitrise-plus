// Issue #231 — Espace professeur de français (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import EspaceEnseignant, { matiereDeLaPage } from "../enseignant/EspaceEnseignant.jsx";
import TableauFrancais from "../francais/TableauFrancais.jsx";
import { fausseApi } from "./setup.js";

const FRANCAIS_SEUL = {
  jeton: "j", nom: "Mme Martin", role: "enseignant", mdp_provisoire: false,
  enseigne_maths: false, enseigne_anglais: false, enseigne_francais: true, validateur_maths: true,
};
const CLASSES = [{ id: 7, code: "5E-FR-K7Q2", niveau: "5e", acces_eleves: true, dossiers: [] }];
const TABLEAU = {
  classe: { id: 7, code: "5E-FR-K7Q2", niveau: "5e", acces_eleves: true, pilote: true },
  presentation: { mode: "guide", origine: "defaut" },
  cours: [
    { cle: "chapitre-1", type: "chapitre", id: 1, titre: "Les fonctions", rubrique: "grammaire" },
    { cle: "dossier-FR3", type: "dossier", code: "FR3", titre: "Comprendre un texte", rubrique: "lire" },
  ],
  eleves: [
    { id: 1, prenom: "Lina", identifiant: "Lina4", derniere_activite: new Date().toISOString(), actif_7j: true, a_accompagner: false,
      cours: { "chapitre-1": { etat: "maitrise", maitrise: 0.84, reponses: 9 }, "dossier-FR3": { etat: "reussi", score: 8, total: 9, tentatives: 1 } } },
    { id: 2, prenom: "Sofia", identifiant: "Sofia8", derniere_activite: null, actif_7j: false, a_accompagner: true,
      cours: { "chapitre-1": { etat: "a_reprendre", maitrise: 0.3, reponses: 6 }, "dossier-FR3": { etat: "pas_commence", score: null, total: null, tentatives: 0 } } },
  ],
  indicateurs: { eleves: 2, actifs_7j: 1, cours_ouverts: 2, maitrise_moyenne: 0.57, a_accompagner: 1 },
  a_valider: [{ chapitre_id: 9, titre: "La phrase complexe", niveau: "4e", questions: 9 }],
  redaction_ouverte: false,
};

describe("espace professeur de français (#231)", () => {
  it("accueille un professeur de français seul sur son tableau de bord, à la marque Boussole Français", async () => {
    sessionStorage.setItem("pkp.enseignant", JSON.stringify(FRANCAIS_SEUL));
    fausseApi({ "GET /francais/classes": { json: CLASSES }, "GET /francais/classes/7/tableau": { json: TABLEAU } });
    render(<EspaceEnseignant chemin="/enseignant" />);
    const navigation = screen.getByRole("navigation", { name: "Navigation Espace professeur" });
    expect(within(navigation).getByText("Français", { selector: "em" })).toBeInTheDocument();
    expect(within(navigation).getByRole("link", { name: "Tableau de bord" })).toHaveAttribute("aria-current", "page");
    expect(within(navigation).getByRole("link", { name: "Mes classes" })).toHaveAttribute("href", "/enseignant/classes");
    expect(within(navigation).getByRole("link", { name: "Validation" })).toBeInTheDocument();
    // Les pages propres aux maths disparaissent.
    expect(within(navigation).queryByRole("link", { name: /Boussole Maths/ })).not.toBeInTheDocument();
    expect(within(navigation).queryByRole("link", { name: "Banque de questions" })).not.toBeInTheDocument();
    expect(await screen.findByRole("heading", { name: "Suivi de la classe 5E-FR-K7Q2" })).toBeInTheDocument();
  });

  it("professeur des deux matières : un sélecteur, et le menu de la seule matière choisie", () => {
    sessionStorage.setItem("pkp.enseignant", JSON.stringify({ ...FRANCAIS_SEUL, enseigne_maths: true, enseigne_anglais: true }));
    fausseApi({ "GET /enseignants/classes": { json: [] } });
    const vue = render(<EspaceEnseignant chemin="/enseignant" />);
    let navigation = screen.getByRole("navigation", { name: "Navigation Espace professeur" });
    const selecteur = within(navigation).getByRole("group", { name: "Matière" });
    expect(within(selecteur).getByRole("button", { name: "Maths" })).toHaveAttribute("aria-pressed", "true");
    expect(within(selecteur).getByRole("link", { name: "Anglais" })).toHaveAttribute("href", "/anglais");
    expect(within(navigation).getByRole("link", { name: "Classes et élèves" })).toHaveAttribute("aria-current", "page");
    expect(within(navigation).getByRole("link", { name: "Boussole Maths (fiches PDF)" })).toBeInTheDocument();
    expect(within(navigation).queryByRole("link", { name: "Rédactions" })).toBeNull(); // rien du français ici
    vue.unmount();

    // Le français : son tableau de bord, ses pages, rien des maths.
    render(<EspaceEnseignant chemin="/enseignant/francais" />);
    navigation = screen.getByRole("navigation", { name: "Navigation Espace professeur" });
    expect(within(navigation).getByRole("button", { name: "Français" })).toHaveAttribute("aria-pressed", "true");
    expect(within(navigation).getByRole("link", { name: "Tableau de bord" })).toHaveAttribute("aria-current", "page");
    for (const nom of ["Mes classes", "Cours", "Dossiers et PDF", "Rédactions"]) {
      expect(within(navigation).getByRole("link", { name: nom })).toBeInTheDocument();
    }
    expect(within(navigation).queryByRole("link", { name: "Boussole Maths (fiches PDF)" })).toBeNull();
    expect(within(navigation).queryByRole("link", { name: "Banque de questions" })).toBeNull();
    expect(navigation).toHaveTextContent("Boussole Français");
  });

  it("une page commune (Mes classes) garde la matière choisie", () => {
    sessionStorage.setItem("pkp.enseignant", JSON.stringify({ ...FRANCAIS_SEUL, enseigne_maths: true }));
    sessionStorage.setItem("pkp.enseignant.matiere", JSON.stringify("francais"));
    fausseApi({ "GET /enseignants/classes": { json: [] } });
    render(<EspaceEnseignant chemin="/enseignant/classes" />);
    const navigation = screen.getByRole("navigation", { name: "Navigation Espace professeur" });
    expect(within(navigation).getByRole("link", { name: "Mes classes" })).toHaveAttribute("aria-current", "page");
    expect(within(navigation).getByRole("button", { name: "Français" })).toHaveAttribute("aria-pressed", "true");
    sessionStorage.removeItem("pkp.enseignant.matiere");
  });

  it("choisir la matière mémorise le choix et ouvre son accueil", async () => {
    sessionStorage.setItem("pkp.enseignant", JSON.stringify({ ...FRANCAIS_SEUL, enseigne_maths: true }));
    fausseApi({ "GET /enseignants/classes": { json: [] } });
    render(<EspaceEnseignant chemin="/enseignant" />);
    await userEvent.click(screen.getByRole("button", { name: "Français" }));
    expect(JSON.parse(sessionStorage.getItem("pkp.enseignant.matiere"))).toBe("francais");
    expect(window.location.pathname).toBe("/enseignant/francais");
    sessionStorage.removeItem("pkp.enseignant.matiere");
  });

  it("matière d'une page : propre à une matière, sinon le dernier choix", () => {
    expect(matiereDeLaPage("/enseignant/redactions", "maths")).toBe("francais");
    expect(matiereDeLaPage("/enseignant/pkp-math", "francais")).toBe("maths");
    expect(matiereDeLaPage("/enseignant/classes", "francais")).toBe("francais");
    expect(matiereDeLaPage("/enseignant/classes", null)).toBe("maths");
  });

  it("montre l'état de chaque élève dans chaque cours, sans couleur seule", async () => {
    fausseApi({ "GET /francais/classes": { json: CLASSES }, "GET /francais/classes/7/tableau": { json: TABLEAU } });
    render(<TableauFrancais jeton="j" onExpire={vi.fn()} validateur />);
    const suivi = (await screen.findByRole("heading", { name: "Suivi de la classe 5E-FR-K7Q2" })).closest("section");
    const lina = within(suivi).getByRole("rowheader", { name: "Lina" }).closest("tr");
    expect(lina).toHaveTextContent("Maîtrisé");
    expect(lina).toHaveTextContent("Réussi 8/9");
    expect(lina).toHaveTextContent("aujourd'hui");
    const sofia = within(suivi).getByRole("rowheader", { name: "Sofia" }).closest("tr");
    expect(sofia).toHaveTextContent("À reprendre");
    expect(sofia).toHaveTextContent("jamais");
    expect(within(suivi).getByRole("columnheader", { name: /Comprendre un texte/ })).toHaveTextContent("Lire et comprendre");
    expect(screen.getByText("57 %")).toBeInTheDocument();
  });

  it("liste le travail à faire et la présentation de la classe (parcours guidé par défaut)", async () => {
    fausseApi({ "GET /francais/classes": { json: CLASSES }, "GET /francais/classes/7/tableau": { json: TABLEAU } });
    render(<TableauFrancais jeton="j" onExpire={vi.fn()} validateur />);
    const aFaire = (await screen.findByRole("heading", { name: "À faire" })).closest("section");
    expect(aFaire).toHaveTextContent("9 questions à valider");
    expect(within(aFaire).getByRole("link", { name: "Valider" })).toHaveAttribute("href", "/enseignant/validation");
    expect(aFaire).toHaveTextContent("Sofia");
    expect(within(aFaire).getByText("Fermé")).toBeInTheDocument();
    const presentation = screen.getByRole("heading", { name: "Présentation pour 5E-FR-K7Q2" }).closest("section");
    const guide = within(presentation).getByText("Parcours guidé").closest("li");
    expect(guide).toHaveTextContent("Origine : par défaut");
    expect(guide).toHaveTextContent("Active");
    expect(within(presentation).getAllByText("Bientôt")).toHaveLength(2);
  });

  it("propose de créer une classe quand le professeur n'en a pas", async () => {
    fausseApi({ "GET /francais/classes": { json: [] } });
    render(<TableauFrancais jeton="j" onExpire={vi.fn()} />);
    expect(await screen.findByText(/pas encore de classe de français/)).toBeInTheDocument();
  });

  it("change de classe", async () => {
    const appels = fausseApi({
      "GET /francais/classes": { json: [...CLASSES, { id: 8, code: "4E-FR-P3D8", niveau: "4e", acces_eleves: true, dossiers: [] }] },
      "GET /francais/classes/7/tableau": { json: TABLEAU },
      "GET /francais/classes/8/tableau": { json: { ...TABLEAU, classe: { ...TABLEAU.classe, id: 8, code: "4E-FR-P3D8" } } },
    });
    render(<TableauFrancais jeton="j" onExpire={vi.fn()} />);
    await screen.findByRole("heading", { name: "Suivi de la classe 5E-FR-K7Q2" });
    await userEvent.selectOptions(screen.getByLabelText("Classe"), "8");
    expect(await screen.findByRole("heading", { name: "Suivi de la classe 4E-FR-P3D8" })).toBeInTheDocument();
    expect(appels.some((a) => a.cle === "GET /francais/classes/8/tableau")).toBe(true);
  });
});
