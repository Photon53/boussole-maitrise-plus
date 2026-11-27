// Issue #231 — Espace administrateur Français (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import FrancaisAdmin from "../admin/FrancaisAdmin.jsx";
import { fausseApi } from "./setup.js";

const SYNTHESE = {
  domaines: [
    { code: "francais-college", libelle: "Français collège", actif: true, public: false },
    { code: "francais-lycee", libelle: "Français lycée", actif: false, public: false },
  ],
  chiffres: { cours: 3, cours_prets: 1, questions: 27, questions_validees: 9, classes_pilotes: 1, eleves_pilotes: 24 },
  niveaux: [
    { niveau: "5e", cours: 2, cours_prets: 1, questions: 18, questions_validees: 9, validateurs: ["Mme Leroy"], professeurs: [], classes_pilotes: ["5E-FR-K7Q2"] },
    { niveau: "6e", cours: 1, cours_prets: 0, questions: 9, questions_validees: 0, validateurs: [], professeurs: [], classes_pilotes: [] },
  ],
  cours: [
    { type: "chapitre", id: 1, code: "FR6-NATURE", titre: "La nature des mots", niveau: "6e", rubrique: "grammaire",
      questions: { total: 9, validees: 0, a_valider: 9, a_corriger: 0 }, statut: "a_valider", classes: [] },
    { type: "chapitre", id: 2, code: "FR5-FONCTIONS", titre: "Les fonctions", niveau: "5e", rubrique: "grammaire",
      questions: { total: 9, validees: 9, a_valider: 0, a_corriger: 0 }, statut: "pret", classes: ["5E-FR-K7Q2"] },
    { type: "dossier", id: 3, code: "FR3-DNB27-01", titre: "Comprendre un texte", niveau: "5e", rubrique: "lire",
      version: { courante: 2, statut_courante: "soumis", validee: 1 }, statut: "revision_a_valider", classes: [] },
  ],
  classes: [{ id: 7, code: "5E-FR-K7Q2", niveau: "5e", domaine: "francais-college", enseignant: "Mme Martin", eleves: 24, pilote: true, cours_ouverts: 1 }],
  fonctions: [
    { code: "redaction", libelle: "Rédaction en ligne des élèves", active: false, reglage: "PKP_REDACTION_ACTIVE", decision: "RGPD-2" },
    { code: "pdf", libelle: "PDF de « Mon cours »", active: false, reglage: "PKP_PDF_FRANCAIS_OUVERT", decision: "V2-D12 (A5)" },
  ],
  alertes: [
    { gravite: "a_faire", action: "validation-questions", message: "9 questions à valider dans 1 cours : un cours n'est proposé aux élèves qu'une fois ses questions validées." },
    { gravite: "attention", action: "equipe", message: "Aucun professeur validateur en 6e : seul l'administrateur peut valider les 1 cours de ce niveau." },
  ],
};

describe("page Français de l'administration (#231)", () => {
  it("montre d'abord ce qu'il reste à traiter, avec l'écran qui le traite", async () => {
    fausseApi({ "GET /admin/francais/synthese": { json: SYNTHESE } });
    render(<FrancaisAdmin jeton="j" onExpire={vi.fn()} />);
    const aTraiter = (await screen.findByRole("heading", { name: "À traiter" })).closest("section");
    const lignes = within(aTraiter).getAllByRole("listitem");
    expect(lignes).toHaveLength(2);
    expect(lignes[0]).toHaveTextContent("À faire");
    expect(within(lignes[0]).getByRole("button", { name: "Valider les questions" })).toBeInTheDocument();
    expect(within(lignes[1]).getByRole("button", { name: "Gérer l'équipe" })).toBeInTheDocument();
  });

  it("présente chapitres et dossiers ensemble, par niveau, avec leur rubrique et leur état", async () => {
    fausseApi({ "GET /admin/francais/synthese": { json: SYNTHESE } });
    render(<FrancaisAdmin jeton="j" onExpire={vi.fn()} />);
    const cours = (await screen.findByRole("heading", { name: "Cours" })).closest("section");
    expect(within(cours).getByRole("heading", { name: "6e" })).toBeInTheDocument();
    const dossier = within(cours).getByText("Comprendre un texte").closest("tr");
    expect(dossier).toHaveTextContent("Lire et comprendre");
    expect(dossier).toHaveTextContent("Révision à valider");
    expect(dossier).toHaveTextContent("v1");
    const pret = within(cours).getByText("Les fonctions").closest("tr");
    expect(pret).toHaveTextContent("Prêt");
    expect(pret).toHaveTextContent("5E-FR-K7Q2");
    expect(within(pret).queryByRole("button")).not.toBeInTheDocument();

    await userEvent.click(within(cours).getByRole("button", { name: "Lire et comprendre" }));
    expect(within(cours).queryByText("Les fonctions")).not.toBeInTheDocument();
    expect(within(cours).getByText("Comprendre un texte")).toBeInTheDocument();
  });

  it("signale les niveaux sans validateur et affiche les fonctions sensibles en lecture seule", async () => {
    fausseApi({ "GET /admin/francais/synthese": { json: SYNTHESE } });
    render(<FrancaisAdmin jeton="j" onExpire={vi.fn()} />);
    const niveaux = (await screen.findByRole("heading", { name: "Par niveau" })).closest("section");
    expect(within(niveaux).getByRole("rowheader", { name: "6e" }).closest("tr")).toHaveTextContent("Aucun");
    const sensibles = screen.getByRole("heading", { name: "Fonctions sensibles" }).closest("section");
    expect(within(sensibles).getAllByText("Désactivée")).toHaveLength(2);
    expect(within(sensibles).queryByRole("button")).not.toBeInTheDocument();
    expect(within(sensibles).queryByRole("checkbox")).not.toBeInTheDocument();
  });

  it("passe en Français collège avant d'ouvrir la validation des questions", async () => {
    fausseApi({ "GET /admin/francais/synthese": { json: SYNTHESE } });
    const onDomaine = vi.fn();
    window.history.replaceState(null, "", "/admin/francais");
    render(<FrancaisAdmin jeton="j" onExpire={vi.fn()} onDomaine={onDomaine} />);
    const actions = await screen.findByRole("group", { name: "Actions du français" });
    await userEvent.click(within(actions).getByRole("button", { name: /Valider les questions/ }));
    expect(onDomaine).toHaveBeenCalledWith("francais-college");
    expect(window.location.pathname + window.location.search).toBe("/admin/exercices?statut=a-valider");
  });
});
