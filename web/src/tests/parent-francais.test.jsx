// Issue #231 — Espace parent : bilan Français de l'enfant (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import EspaceParent from "../parent/EspaceParent.jsx";
import BilanFrancais from "../parent/BilanFrancais.jsx";
import { fausseApi } from "./setup.js";

const BILAN = {
  eleve: { id: 12, prenom: "Lina", classe: "5E-FR-K7Q2", niveau: "5e" }, acces: true,
  indicateurs: { cours: 3, commences: 2, termines: 1, minutes_7_jours: 65, derniere_activite: "2026-11-27T10:00:00+00:00" },
  cours: [
    { titre: "Les fonctions", type: "chapitre", rubrique: "grammaire", etat: "maitrise", etape: 7, score: undefined, total: undefined, derniere_activite: null },
    { titre: "L'imparfait et le passé simple", type: "chapitre", rubrique: "conjugaison", etat: "a_reprendre", etape: 4, derniere_activite: null },
    { titre: "Comprendre un texte", type: "dossier", rubrique: "lire", etat: "reussi", etape: 7, score: 8, total: 9, derniere_activite: null },
  ],
  a_revoir: ["L'imparfait et le passé simple"],
  retours: { remis: 1, relus: 2 },
};
const appelerAvec = (json) => vi.fn(async () => json);

describe("bilan Français pour le parent (#231)", () => {
  it("montre les cours, leur état, l'étape et le score du quiz", async () => {
    render(<BilanFrancais eleveId={12} appeler={appelerAvec(BILAN)} />);
    expect(await screen.findByRole("heading", { name: /Le français de Lina/ })).toBeInTheDocument();
    expect(screen.getByText("2 / 3")).toBeInTheDocument();
    expect(screen.getByText("1 h 05")).toBeInTheDocument();
    const dossier = screen.getByText("Comprendre un texte").closest("li");
    expect(dossier).toHaveTextContent("Lire et comprendre · étape 7 sur 7 · quiz 8/9");
    expect(dossier).toHaveTextContent("Réussi");
    const cours = screen.getByRole("heading", { name: "Cours ouverts par la professeure" }).closest("section");
    expect(within(cours).getByText("L'imparfait et le passé simple").closest("li")).toHaveTextContent("À revoir");
  });

  it("dit comment aider, compte les retours, et rappelle que les textes de l'enfant ne sont pas montrés", async () => {
    render(<BilanFrancais eleveId={12} appeler={appelerAvec(BILAN)} />);
    const aider = (await screen.findByRole("heading", { name: "Comment l'aider" })).closest("section");
    expect(within(aider).getByRole("listitem")).toHaveTextContent("L'imparfait et le passé simple");
    expect(screen.getByText(/2 textes relus par la professeure · 1 en attente de relecture/)).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent("ses textes et ses réponses rédigées ne sont pas montrés");
  });

  it("annonce une classe sans accès au français", async () => {
    render(<BilanFrancais eleveId={12} appeler={appelerAvec({ ...BILAN, acces: false, cours: [], a_revoir: [] })} />);
    expect(await screen.findByText(/n'est pas ouvert à la classe de Lina/)).toBeInTheDocument();
    expect(screen.getByText("Aucun cours de français n'est ouvert pour l'instant.")).toBeInTheDocument();
  });

  it("un enfant d'une classe de français rattaché par le professeur voit le bilan Français, pas le tableau des maths", async () => {
    sessionStorage.setItem("pkp.parent", JSON.stringify({ jeton: "j", email: "p@x.fr", mdp_provisoire: false }));
    const appels = fausseApi({
      "GET /parents/famille": { json: [] },
      "GET /parents/enfants": { json: [{ id: 12, prenom: "Lina", code_classe: "5E-FR-K7Q2", niveau: "5e", parcours: "tronc-commun", matiere: "francais" }] },
      "GET /parents/enfants/12/francais": { json: BILAN },
    });
    render(<EspaceParent />);
    expect(await screen.findByRole("heading", { name: /Le français de Lina/ })).toBeInTheDocument();
    expect(appels.some((a) => a.cle === "GET /parents/enfants/12")).toBe(false);
    sessionStorage.clear();
  });

  it("dans une famille, l'onglet Français montre le bilan de chaque classe de français", async () => {
    sessionStorage.setItem("pkp.parent", JSON.stringify({ jeton: "j", email: "p@x.fr", mdp_provisoire: false }));
    const suivi = {
      enfant: { id: 7, prenom: "Lina", niveau: "5e", identifiant: "Lina4", a_un_code: true, derniere_connexion: null, maths: [], anglais: [] },
      matieres: [{ code: "maths", libelle: "Boussole Maths", disponible: true }, { code: "francais", libelle: "Boussole Français", disponible: true }],
      maths: [], anglais: [], francais: [{ id: 12, prenom: "Lina", code_classe: "5E-FR-K7Q2", niveau: "5e", parcours: "tronc-commun", matiere: "francais" }],
    };
    fausseApi({
      "GET /parents/famille": { json: [suivi] },
      "GET /parents/enfants": { json: [] },
      "GET /parents/enfants/12/francais": { json: BILAN },
    });
    render(<EspaceParent />);
    await userEvent.click(await screen.findByRole("tab", { name: "Boussole Français" }));
    expect(await screen.findByRole("heading", { name: /Le français de Lina/ })).toBeInTheDocument();
    sessionStorage.clear();
  });
});
