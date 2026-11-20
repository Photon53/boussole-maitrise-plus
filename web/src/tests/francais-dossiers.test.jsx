// Issue #98 — Intégration du premier dossier Français 3e en DEV (Claude)
import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import EspaceFrancais, { causesAbsence } from "../francais/EspaceFrancais.jsx";
import { fausseApi } from "./setup.js";

const RESUME = {
  code: "FR3-DNB27-01", titre: "Comprendre un texte et justifier sa réponse", domaine: "francais-college", niveau: "3e",
  libelle_domaine: "Français collège", version: 1, statut: "soumis", motif_refus: null, version_validee: null,
  nb_questions: 11, cible: "DNB général, session 2027", competences_locales: ["FR3-L01"],
  attribution: { redaction: "Codex", redaction_issue: 55, integration: "Claude", integration_issue: 98 },
  registre: {}, auteur: null, validateur: null, decide_le: null, visible_eleves: false, peut_valider: false,
};
const ELEVE = {
  presentation: ["Français — 3e"], objectifs: ["Repérer une information."],
  lecon: [{ titre: "1. Je comprends", markdown: "Une information **explicite** est donnée directement." }],
  textes: [{ code: "TEXTE-1", titre: "La place près de la fenêtre", lignes: ["La porte de la salle était déjà ouverte."], mention: null }],
  consignes_questions: [],
  questions: [{ code: "Q1", partie: "entrainement", texte: "TEXTE-1", difficulte_proposee: 1, consigne: "Quel projet ?", coup_de_pouce: null, retour: "humain" }],
  je_verifie: null,
};
const PROFESSEUR = {
  presentation: [], deroulement: null, principes_correction: "Accepter une autre réponse cohérente.",
  questions: [{ code: "Q1", partie: "entrainement", consigne: "Quel projet ?", corrige: { question: "Q1", paragraphes: ["Un jardin avec des bancs."] } }],
  grille: null, controle_avant_utilisation: ["Relire le texte."], remarques: [], retour_seance: null,
};

function connecte() {
  sessionStorage.setItem("pkp.enseignant", JSON.stringify({ jeton: "j", nom: "Mme Martin", role: "enseignant", mdp_provisoire: false }));
}

describe("Français : préparation réservée aux adultes", () => {
  it("un compte sans habilitation française voit un accès réservé", async () => {
    connecte();
    const appels = fausseApi({
      "GET /francais/dossiers": { status: 403, json: { detail: "Réservé" } },
      "GET /francais/etat": { status: 403, json: { detail: "Réservé aux administrateurs." } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText("Espace réservé aux adultes habilités en français")).toBeInTheDocument();
    await waitFor(() => expect(appels.some((a) => a.cle === "GET /francais/etat")).toBe(true));
    expect(screen.queryByText("Diagnostic administrateur")).not.toBeInTheDocument();
  });

  it("l'aperçu élève ne montre pas le corrigé ; l'onglet professeur le montre", async () => {
    connecte();
    fausseApi({
      "GET /francais/dossiers": { json: [RESUME] },
      "GET /francais/dossiers/FR3-DNB27-01/eleve": { json: { ...RESUME, eleve: ELEVE } },
      "GET /francais/dossiers/FR3-DNB27-01/professeur": { json: { ...RESUME, professeur: PROFESSEUR } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText(/non publiés aux élèves/)).toBeInTheDocument();
    // La note est affichée avant le chargement de la liste : attendre la liste elle-même (sinon dépend du minutage).
    expect(await screen.findByText(/Non visible des élèves/)).toBeInTheDocument();
    expect(screen.getByText(/Rédaction : Codex/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Ouvrir" }));
    expect(await screen.findByText("La porte de la salle était déjà ouverte.")).toBeInTheDocument();
    expect(screen.getByText("Réponse rédigée : retour du professeur.")).toBeInTheDocument();
    expect(screen.queryByText("Un jardin avec des bancs.")).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole("tab", { name: "Supports professeur (corrigés)" }));
    expect(await screen.findByText("Un jardin avec des bancs.")).toBeInTheDocument();
  });
});

// Issue #212 : liste vide ou refus expliqués à l'administrateur, sans rien montrer de plus aux professeurs.
const domaines = (college, lycee) => [
  { code: "francais-college", libelle: "Français collège", actif: college[0], dossiers: college[1] },
  { code: "francais-lycee", libelle: "Français lycée", actif: lycee[0], dossiers: lycee[1] },
];

describe("Français : cause d'une liste vide (#212)", () => {
  it("dossier non importé sur l'instance", async () => {
    connecte();
    fausseApi({
      "GET /francais/dossiers": { json: [] },
      "GET /francais/etat": { json: { domaines: domaines([true, 0], [false, 0]), dossiers: 0 } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText(/Aucun dossier de français n'est importé dans la base de cette instance/)).toBeInTheDocument();
    expect(screen.getByText("Aucun dossier de français accessible avec vos habilitations.")).toBeInTheDocument();
  });

  it("dossier rangé dans un domaine non activé", async () => {
    connecte();
    fausseApi({
      "GET /francais/dossiers": { json: [] },
      "GET /francais/etat": { json: { domaines: domaines([false, 1], [true, 0]), dossiers: 1 } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText(/1 dossier\(s\) rangé\(s\) dans « Français collège »/)).toBeInTheDocument();
  });

  it("aucun domaine actif : le refus de l'administrateur est expliqué", async () => {
    connecte();
    fausseApi({
      "GET /francais/dossiers": { status: 403, json: { detail: "Réservé" } },
      "GET /francais/etat": { json: { domaines: domaines([false, 1], [false, 0]), dossiers: 1 } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText("Diagnostic administrateur")).toBeInTheDocument();
    expect(screen.getByText(/rangé\(s\) dans « Français collège », qui n'est pas activé/)).toBeInTheDocument();
  });

  it("professeur : liste vide sans diagnostic ni message d'erreur", async () => {
    connecte();
    const appels = fausseApi({
      "GET /francais/dossiers": { json: [] },
      "GET /francais/etat": { status: 403, json: { detail: "Réservé aux administrateurs." } },
    });
    render(<EspaceFrancais />);
    expect(await screen.findByText("Aucun dossier de français accessible avec vos habilitations.")).toBeInTheDocument();
    await waitFor(() => expect(appels.some((a) => a.cle === "GET /francais/etat")).toBe(true));
    expect(screen.queryByText("Diagnostic administrateur")).not.toBeInTheDocument();
    expect(screen.queryByText(/Réservé aux administrateurs/)).not.toBeInTheDocument();
  });

  it("causesAbsence : rien à expliquer quand l'état est inconnu ou cohérent", () => {
    expect(causesAbsence(null)).toEqual([]);
    expect(causesAbsence({ domaines: domaines([true, 1], [false, 0]), dossiers: 1 })).toEqual([]);
    expect(causesAbsence({ domaines: domaines([false, 0], [false, 0]), dossiers: 0 })).toHaveLength(2);
  });
});
