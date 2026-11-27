// Issue #217 — Cours de français visibles dans l'espace Français (Claude)
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { api } from "../api.js";
import CoursFrancais from "../francais/CoursFrancais.jsx";
import { fausseApi } from "./setup.js";

const appeler = (chemin, options = {}) => api(chemin, { ...options, jeton: "j" });
const CHAPITRE = {
  id: 12,
  code: "FR3-ACCORDS",
  titre: "Accords et réécriture",
  niveau: "3e",
  domaine: "francais-college",
  rubrique: "grammaire",
  nb_questions: 9,
  nb_validees: 2,
  nb_a_valider: 7,
  nb_a_corriger: 0,
  ouvert_dans: ["3E-FR-A"],
  peut_valider: true,
  competences: [{ id: 1, code: "FR3-ACC-1", libelle: "Accorder le verbe", a_une_lecon: true, nb_questions: 1 }],
};

describe("Espace Français : onglet Cours (#217)", () => {
  it("liste les cours par niveau avec leur état de validation", async () => {
    fausseApi({
      "GET /francais/chapitres": {
        json: [CHAPITRE, { ...CHAPITRE, id: 13, niveau: "6e", titre: "La nature des mots", ouvert_dans: [] }],
      },
    });
    render(<CoursFrancais appeler={appeler} />);
    expect(await screen.findByRole("heading", { name: "Troisième" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Sixième" })).toBeInTheDocument();
    expect(screen.getByText(/Grammaire · FR3-ACCORDS · 2\/9 questions validées · ouvert dans 3E-FR-A/)).toBeInTheDocument();
  });

  it("affiche le cours et ses questions, avec le lien de validation", async () => {
    fausseApi({
      "GET /francais/chapitres": { json: [CHAPITRE] },
      "GET /francais/chapitres/12": {
        json: {
          ...CHAPITRE,
          competences: [
            {
              ...CHAPITRE.competences[0],
              cours: "Le verbe s'accorde avec son sujet.",
              resume: "Sujet → verbe.",
              objectifs: [],
              questions: [
                {
                  id: 5,
                  code: "FR3-ACC-1-01",
                  type: "qcm",
                  difficulte: 1,
                  enonce: "Choisis la forme.",
                  solution: "B",
                  statut: "a-valider",
                },
              ],
            },
          ],
        },
      },
    });
    render(<CoursFrancais appeler={appeler} />);
    await userEvent.click(await screen.findByRole("button", { name: "Lire le cours" }));
    expect(await screen.findByText("Le verbe s'accorde avec son sujet.")).toBeInTheDocument();
    expect(screen.getByText(/À valider\) — réponse : B/)).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Valider ces questions" })).toHaveAttribute("href", "/enseignant/validation");
  });

  it("aucun cours : message de périmètre", async () => {
    fausseApi({ "GET /francais/chapitres": { json: [] } });
    render(<CoursFrancais appeler={appeler} admin />);
    expect(await screen.findByText(/Aucun cours de français dans votre périmètre/)).toBeInTheDocument();
  });
});
