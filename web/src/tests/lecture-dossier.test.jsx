// Issue #231 — Dossier de lecture : sept étapes, texte et questions côte à côte (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import LectureDossier, { lignesCitees } from "../eleve/LectureDossier.jsx";

const LIGNES = Array.from({ length: 14 }, (_, i) => `Ligne ${i + 1} du texte.`);
const DOSSIER = {
  code: "FR3-DNB27-01", titre: "Comprendre un texte et justifier sa réponse", niveau: "3e", version: 1,
  mode_correction: "apres_chaque_question", saisie_ouverte: false, reponses: [], auto_evaluation: [],
  eleve: {
    presentation: [], objectifs: ["À la fin du travail, tu sauras repérer une information."],
    lecon: [{ titre: "1. Je comprends", markdown: "Une information **explicite** est donnée directement." }],
    textes: [
      { code: "TEXTE-1", titre: "La place près de la fenêtre", lignes: LIGNES, mention: null },
      { code: "TEXTE-2", titre: "Le banc", lignes: ["Un autre texte."], mention: null },
    ],
    consignes_questions: ["Réponds avant de consulter les corrigés."],
    questions: [
      { code: "Q1", partie: "entrainement", texte: "TEXTE-1", difficulte_proposee: 1, consigne: "Quel projet ? Relève une expression de la ligne 5.", coup_de_pouce: null, retour: "humain" },
      { code: "Q3", partie: "entrainement", texte: "TEXTE-1", difficulte_proposee: 2, consigne: "Relève deux gestes, dans les lignes 4 à 12.", coup_de_pouce: "Cherche les mains.", retour: "humain" },
      { code: "T1", partie: "transfert", texte: "TEXTE-2", difficulte_proposee: 3, consigne: "Compare les deux textes.", coup_de_pouce: null, retour: "humain" },
    ],
    je_verifie: "Ai-je cité le texte ?", je_sais: ["Je sais citer une ligne."],
    quiz: [{ question: "Qui dit « je » ?", texte: "TEXTE-1", choix: ["La narratrice", "L'autrice"] }],
  },
};

describe("lignes citées par une consigne", () => {
  it("reconnaît une ligne, une plage et l'abréviation l.", () => {
    expect(lignesCitees("Relève une expression de la ligne 5.")).toEqual([[5, 5]]);
    expect(lignesCitees("dans les lignes 4 à 12")).toEqual([[4, 12]]);
    expect(lignesCitees("Ligne 2, que signifie… ; voir l. 7-9")).toEqual([[2, 2], [7, 9]]);
    expect(lignesCitees("Explique avec tes mots.")).toEqual([]);
  });
});

describe("dossier de lecture (#231)", () => {
  it("range le dossier en sept étapes ; celles sans activité sont grisées", () => {
    render(<LectureDossier dossier={DOSSIER} jeton="j" onExpire={vi.fn()} onFermer={vi.fn()} />);
    const rail = screen.getByRole("navigation", { name: "Étapes du cours" });
    const etapes = within(rail).getAllByRole("button").filter((b) => b.classList.contains("rail-etape"));
    expect(etapes.map((b) => b.querySelector(".rail-texte span").textContent)).toEqual(
      ["Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider"]);
    expect(etapes[0]).toHaveAttribute("aria-current", "step");
    expect(etapes[5]).toBeDisabled(); // réponse en ligne fermée (RGPD-2)
    expect(etapes[5]).toHaveTextContent("Pas d'activité dans ce cours");
    expect(screen.getByRole("heading", { name: "Découvrir", level: 2 })).toBeInTheDocument();
  });

  it("met le texte à côté des questions et repère les lignes citées par la question en cours", async () => {
    render(<LectureDossier dossier={DOSSIER} jeton="j" onExpire={vi.fn()} onFermer={vi.fn()} />);
    await userEvent.click(within(screen.getByRole("navigation", { name: "Étapes du cours" })).getByRole("button", { name: /S'entraîner/ }));
    const texte = screen.getByRole("article", { name: "La place près de la fenêtre" });
    const lignes = within(texte).getAllByRole("listitem");
    expect(lignes).toHaveLength(14);
    expect(lignes.filter((l) => l.classList.contains("citee")).map((l) => l.value)).toEqual([5]);
    await userEvent.click(screen.getByRole("button", { name: /Q3/ }));
    expect(lignes.filter((l) => l.classList.contains("citee")).map((l) => l.value)).toEqual([4, 5, 6, 7, 8, 9, 10, 11, 12]);
    expect(screen.getByText("Coup de pouce")).toBeInTheDocument();
    expect(screen.getByRole("note")).toHaveTextContent("Réponds dans ton cahier");
  });

  it("l'étape Approfondir montre l'autre texte ; Consolider, « Je vérifie » et « Je sais »", async () => {
    render(<LectureDossier dossier={DOSSIER} jeton="j" onExpire={vi.fn()} onFermer={vi.fn()} />);
    await userEvent.click(within(screen.getByRole("navigation", { name: "Étapes du cours" })).getByRole("button", { name: /Approfondir/ }));
    expect(screen.getByRole("article", { name: "Le banc" })).toBeInTheDocument();
    const rail = screen.getByRole("navigation", { name: "Étapes du cours" });
    await userEvent.click(within(rail).getByRole("button", { name: /Consolider/ }));
    expect(screen.getByText("Ai-je cité le texte ?")).toBeInTheDocument();
    expect(screen.getByText("Je sais citer une ligne.")).toBeInTheDocument();
  });

  it("étape suivante et retour à « Mes cours »", async () => {
    const onFermer = vi.fn();
    render(<LectureDossier dossier={DOSSIER} jeton="j" onExpire={vi.fn()} onFermer={onFermer} libelleRetour="Mes cours" />);
    await userEvent.click(screen.getByRole("button", { name: "Comprendre →" }));
    expect(screen.getByRole("heading", { name: "Comprendre", level: 2 })).toBeInTheDocument();
    expect(screen.getByText(/est donnée directement/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "← Mes cours" }));
    expect(onFermer).toHaveBeenCalled();
  });

  it("le quiz garde le texte à côté (étape Appliquer)", async () => {
    render(<LectureDossier dossier={DOSSIER} jeton="j" onExpire={vi.fn()} onFermer={vi.fn()} />);
    await userEvent.click(within(screen.getByRole("navigation", { name: "Étapes du cours" })).getByRole("button", { name: /Appliquer/ }));
    expect(screen.getByRole("heading", { name: "Quiz" })).toBeInTheDocument();
    expect(screen.getByRole("article", { name: "La place près de la fenêtre" })).toBeInTheDocument();
  });
});
