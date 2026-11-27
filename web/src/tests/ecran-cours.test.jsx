// Issue #231 — Écran de cours de français en sept étapes (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import EcranCours, { partiesDuCours } from "../eleve/EcranCours.jsx";
import { fausseApi } from "./setup.js";

const COURS = [
  "## 1. Découvrir", "**Objectif** : savoir à quoi sert chaque groupe de la phrase.",
  "## 2. Comprendre", "Dans « Le récit de son voyage passionne la classe », le groupe sujet…",
  "## 3. Appliquer et s’entraîner", "Les premiers exercices demandent la fonction d'un groupe souligné.",
  "## 4. Approfondir", "Les pronoms compliquent l'analyse.",
  "## 5. Réinvestir", "Dans ton récit du sujet R2, souligne un COD.",
].join("\n");
const LECON = {
  competence_id: 40, code: "FR5-FONCTIONS-ID", libelle: "Identifier le sujet, le COD, le COI et le complément du nom",
  chapitre: "Les fonctions : sujet, COD, COI et complément du nom", chapitre_id: 4, cours: COURS,
  resume: "- **COD** : complète le verbe sans préposition.", objectifs: ["Identifier le sujet d'un verbe."],
  methodes: [], erreurs_frequentes: [{ erreur: "Prendre le premier groupe nominal pour le sujet.", explication: "Le sujet peut être inversé." }],
  ressources: [],
};
const routes = (lecon = LECON) => ({
  "GET /cours/40": { json: lecon },
  "GET /eleves/moi/competences/40/avancement": { json: { competence_id: 40, libelle: "x", reponses: 4, reussies_bases: 2, objectif_bases: 3, reussies_avancees: 0, objectif_avancees: 2, maitrise: 0.5, maitrisee: false } },
  "GET /eleves/moi/comprehension/40": { json: { competence_id: 40, compris: null } },
});
const rail = () => screen.getByRole("navigation", { name: "Étapes du cours" });

describe("découpage du cours rédigé", () => {
  it("range chaque partie à son étape ; la rédaction aussi", () => {
    const p = partiesDuCours(COURS);
    expect(Object.keys(p).map(Number)).toEqual([1, 2, 3, 5, 6]);
    expect(p[3][0].titre).toBe("Appliquer et s’entraîner");
    const redaction = partiesDuCours("## 2. Comprendre la méthode\nA\n## 3. Mes critères de réussite\nB\n## 4. Relire et réécrire\nC");
    expect(Object.keys(redaction).map(Number)).toEqual([2, 3, 5]);
    expect(partiesDuCours("Sans titre.")[2][0].texte).toBe("Sans titre.");
  });
});

describe("écran de cours (#231)", () => {
  it("s'ouvre à l'étape demandée et montre les sept étapes", async () => {
    fausseApi(routes());
    render(<EcranCours jeton="j" onExpire={vi.fn()} competenceId={40} etapeInitiale={2} rubrique="grammaire" nbQuestions={9}
      onRetour={vi.fn()} onEntrainer={vi.fn()} onVoirHistorique={vi.fn()} />);
    expect(await screen.findByRole("heading", { name: "Comprendre", level: 2 })).toBeInTheDocument();
    expect(screen.getByText(/Le récit de son voyage/)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "L'essentiel" })).toBeInTheDocument();
    // Le titre de partie « Comprendre » n'est pas répété sous le titre de l'étape.
    expect(screen.queryByRole("heading", { name: "Comprendre", level: 3 })).not.toBeInTheDocument();
    const etapes = within(rail()).getAllByRole("button").filter((b) => b.classList.contains("rail-etape"));
    expect(etapes).toHaveLength(7);
    expect(etapes[1]).toHaveAttribute("aria-current", "step");
    expect(etapes.every((b) => !b.disabled)).toBe(true);
  });

  it("les étapes d'exercices ouvrent l'entraînement du moteur, sans choisir les questions", async () => {
    fausseApi(routes());
    const onEntrainer = vi.fn();
    render(<EcranCours jeton="j" onExpire={vi.fn()} competenceId={40} etapeInitiale={3} rubrique="grammaire" nbQuestions={9}
      onRetour={vi.fn()} onEntrainer={onEntrainer} onVoirHistorique={vi.fn()} />);
    expect(await screen.findByText(/Exercices de base \(niveaux 1 à 3\)/)).toHaveTextContent("2 / 3");
    await userEvent.click(await screen.findByRole("button", { name: "Commencer les exercices" }));
    expect(onEntrainer).toHaveBeenCalledWith(40, LECON.libelle);
    await userEvent.click(within(rail()).getByRole("button", { name: /Approfondir/ }));
    expect(screen.getByText("Prendre le premier groupe nominal pour le sujet.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "M'entraîner encore" })).toBeInTheDocument();
  });

  it("un sujet de rédaction n'a pas d'étape d'exercices corrigés", async () => {
    const redaction = { ...LECON, cours: "## 1. Découvrir\nA\n## 2. Comprendre la méthode\nB\n## 3. Mes critères de réussite\nC\n## 4. Relire et réécrire\nD\n## 5. Réinvestir\nE" };
    fausseApi(routes(redaction));
    render(<EcranCours jeton="j" onExpire={vi.fn()} competenceId={40} rubrique="redaction" nbQuestions={1}
      onRetour={vi.fn()} onEntrainer={vi.fn()} onVoirHistorique={vi.fn()} />);
    await screen.findByRole("heading", { name: "Découvrir", level: 2 });
    const sentrainer = within(rail()).getByRole("button", { name: /S'entraîner/ });
    expect(sentrainer).toBeDisabled();
    await userEvent.click(within(rail()).getByRole("button", { name: /Appliquer/ }));
    expect(screen.getByRole("heading", { name: "Mes critères de réussite" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Commencer les exercices" })).not.toBeInTheDocument();
  });

  it("Consolider rappelle l'essentiel et mène à l'historique ; retour à Mes cours", async () => {
    fausseApi(routes());
    const onVoirHistorique = vi.fn();
    const onRetour = vi.fn();
    render(<EcranCours jeton="j" onExpire={vi.fn()} competenceId={40} etapeInitiale={7} rubrique="grammaire" nbQuestions={9}
      onRetour={onRetour} onEntrainer={vi.fn()} onVoirHistorique={onVoirHistorique} />);
    expect(await screen.findByRole("heading", { name: "À retenir" })).toBeInTheDocument();
    expect(await screen.findByRole("status")).toHaveTextContent("Maîtrise actuelle : 50 % (maîtrisée à partir de 80 %).");
    await userEvent.click(screen.getByRole("button", { name: "Revoir mes réponses" }));
    expect(onVoirHistorique).toHaveBeenCalledWith(40);
    await userEvent.click(within(rail()).getByRole("button", { name: "← Mes cours" }));
    expect(onRetour).toHaveBeenCalled();
  });
});
