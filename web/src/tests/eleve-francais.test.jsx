// Issue #231 — Accueil et cours Français de l'élève (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import EspaceEleve from "../eleve/EspaceEleve.jsx";
import { AccueilFrancais, CoursFrancais } from "../eleve/FrancaisEleve.jsx";
import { fausseApi } from "./setup.js";

const ETAPES = ["Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider"];
const FONCTIONS = {
  cle: "chapitre-4", type: "chapitre", id: 4, titre: "Les fonctions : sujet, COD, COI et complément du nom", rubrique: "grammaire",
  competence_id: 40, a_une_lecon: true, nb_questions: 9, etat: "en_cours", maitrise: 0.4, reponses: 4, etape: 4,
  derniere_activite: "2026-11-27T10:00:00+00:00",
};
const IMPARFAIT = {
  cle: "chapitre-5", type: "chapitre", id: 5, titre: "L'imparfait et le passé simple", rubrique: "conjugaison",
  competence_id: 50, a_une_lecon: true, nb_questions: 9, etat: "pas_commence", maitrise: 0, reponses: 0, etape: 1,
  derniere_activite: null,
};
const RECIT = {
  cle: "chapitre-6", type: "chapitre", id: 6, titre: "Rédaction : raconter un événement passé", rubrique: "redaction",
  competence_id: 60, a_une_lecon: true, nb_questions: 1, etat: "pas_commence", maitrise: 0, reponses: 0, etape: 1,
  derniere_activite: null,
};
const ACCUEIL = {
  eleve: { prenom: "Lina", classe: "5E-FR-K7Q2", niveau: "5e" }, acces: true, presentation: { mode: "guide", origine: "defaut" },
  etapes: ETAPES, cours: [FONCTIONS, IMPARFAIT, RECIT], reprise: "chapitre-4",
  rubriques: { lire: 0, grammaire: 1, conjugaison: 1, redaction: 1 }, redaction_ouverte: false,
};
const LIEN = { id: 9, type: "lien", titre: "Les pronoms COD et COI", description: "", url: "https://exemple.test", domaine: "exemple.test", taille_octets: null, portee: "classe" };

describe("accueil Français de l'élève (#231)", () => {
  it("propose de reprendre le cours en cours, à la bonne étape des sept", async () => {
    fausseApi({ "GET /francais/eleve/accueil": { json: ACCUEIL }, "GET /cours/mon-cours": { json: [{ id: 4, titre: "Les fonctions", ressources: [LIEN] }] } });
    const onOuvrir = vi.fn();
    render(<AccueilFrancais jeton="j" onExpire={vi.fn()} prenom="Lina" onOuvrir={onOuvrir} onRubrique={vi.fn()} onAller={vi.fn()} />);
    const reprise = (await screen.findByRole("heading", { name: FONCTIONS.titre, level: 3 })).closest("section");
    expect(reprise).toHaveTextContent("Reprendre ton cours");
    expect(reprise).toHaveTextContent("étape 4 sur 7 : S'entraîner");
    expect(within(reprise).getByRole("img", { name: "Étape 4 sur 7" })).toBeInTheDocument();
    await userEvent.click(within(reprise).getByRole("button", { name: /Continuer/ }));
    expect(onOuvrir).toHaveBeenCalledWith(FONCTIONS);
    expect(screen.getByText("Les pronoms COD et COI")).toBeInTheDocument();
  });

  it("montre les quatre rubriques, dont Lire et comprendre, et la rédaction sur copie", async () => {
    fausseApi({ "GET /francais/eleve/accueil": { json: ACCUEIL }, "GET /cours/mon-cours": { json: [] } });
    const onRubrique = vi.fn();
    render(<AccueilFrancais jeton="j" onExpire={vi.fn()} prenom="Lina" onOuvrir={vi.fn()} onRubrique={onRubrique} onAller={vi.fn()} />);
    const rubriques = (await screen.findByRole("heading", { name: "Les quatre rubriques" })).closest("section");
    const boutons = within(rubriques).getAllByRole("button");
    expect(boutons.map((b) => b.querySelector(".fr-rubrique-titre").textContent)).toEqual(["Lire et comprendre", "Grammaire", "Conjugaison", "Rédaction"]);
    expect(boutons[0]).toHaveTextContent("Pas encore de cours");
    expect(boutons[3]).toHaveTextContent("Sur copie");
    await userEvent.click(boutons[2]);
    expect(onRubrique).toHaveBeenCalledWith("conjugaison");
  });

  it("annonce une classe sans accès au français", async () => {
    fausseApi({ "GET /francais/eleve/accueil": { json: { ...ACCUEIL, acces: false, cours: [], reprise: null } }, "GET /cours/mon-cours": { json: [] } });
    render(<AccueilFrancais jeton="j" onExpire={vi.fn()} prenom="Lina" onOuvrir={vi.fn()} onRubrique={vi.fn()} onAller={vi.fn()} />);
    expect(await screen.findByRole("note")).toHaveTextContent("pas encore ouvert à ta classe");
  });
});

describe("Mes cours (#231)", () => {
  it("présente chapitres et dossiers avec la même carte, filtrables par rubrique", async () => {
    const dossier = { cle: "dossier-FR3", type: "dossier", code: "FR3", titre: "Comprendre un texte", rubrique: "lire", nb_quiz: 9,
      etat: "reussi", score: 8, total: 9, tentatives: 1, etape: 7, derniere_activite: null };
    fausseApi({ "GET /francais/eleve/accueil": { json: { ...ACCUEIL, cours: [...ACCUEIL.cours, dossier], rubriques: { ...ACCUEIL.rubriques, lire: 1 } } } });
    const onRubrique = vi.fn();
    const { rerender } = render(<CoursFrancais jeton="j" onExpire={vi.fn()} rubrique="" onRubrique={onRubrique} onOuvrir={vi.fn()} onLecon={vi.fn()} />);
    const carte = (await screen.findByRole("heading", { name: "Comprendre un texte" })).closest("article");
    expect(carte).toHaveTextContent("Lire et comprendre");
    expect(carte).toHaveTextContent("Réussi");
    expect(carte).toHaveTextContent("Quiz : 8/9");
    expect(carte).toHaveTextContent("Étape 7 sur 7 : Consolider");
    await userEvent.click(screen.getByRole("button", { name: "Grammaire (1)" }));
    expect(onRubrique).toHaveBeenCalledWith("grammaire");
    rerender(<CoursFrancais jeton="j" onExpire={vi.fn()} rubrique="grammaire" onRubrique={onRubrique} onOuvrir={vi.fn()} onLecon={vi.fn()} />);
    expect(screen.queryByRole("heading", { name: "Comprendre un texte" })).not.toBeInTheDocument();
    expect(screen.getByRole("heading", { name: FONCTIONS.titre })).toBeInTheDocument();
  });

  it("propose la leçon seulement une fois le cours commencé ; sinon « Commencer »", async () => {
    fausseApi({ "GET /francais/eleve/accueil": { json: ACCUEIL } });
    const onLecon = vi.fn();
    render(<CoursFrancais jeton="j" onExpire={vi.fn()} rubrique="" onRubrique={vi.fn()} onOuvrir={vi.fn()} onLecon={onLecon} />);
    const enCours = (await screen.findByRole("heading", { name: FONCTIONS.titre })).closest("article");
    await userEvent.click(within(enCours).getByRole("button", { name: "Leçon" }));
    expect(onLecon).toHaveBeenCalledWith(FONCTIONS);
    const nouveau = screen.getByRole("heading", { name: IMPARFAIT.titre }).closest("article");
    expect(within(nouveau).queryByRole("button", { name: "Leçon" })).not.toBeInTheDocument();
    expect(within(nouveau).getByRole("button", { name: "Commencer" })).toBeInTheDocument();
  });
});

describe("navigation de l'élève de français (#231, FR-UI-D5)", () => {
  const session = (matiere) => sessionStorage.setItem("pkp.eleve", JSON.stringify({
    jeton: "j", eleve: { id: 1, prenom: "Lina", code_classe: "5E-FR-K7Q2", niveau: "5e", matiere },
  }));

  it("cinq onglets au lieu de huit, accueil en premier", async () => {
    session("francais");
    fausseApi({ "GET /francais/eleve/accueil": { json: ACCUEIL }, "GET /cours/mon-cours": { json: [] } });
    render(<EspaceEleve />);
    expect(await screen.findByRole("heading", { name: "Mon espace Français" })).toBeInTheDocument();
    expect(screen.getAllByRole("tab").map((t) => t.textContent)).toEqual(["Accueil", "Mes cours", "S'entraîner", "Ma progression", "Plus"]);
    expect(screen.getByRole("tab", { name: "Accueil" })).toHaveAttribute("aria-selected", "true");
    sessionStorage.clear();
  });

  it("ouvrir un cours pas commencé mène à sa leçon", async () => {
    session("francais");
    fausseApi({
      "GET /francais/eleve/accueil": { json: { ...ACCUEIL, reprise: "chapitre-5" } },
      "GET /cours/mon-cours": { json: [] },
      "GET /cours": { json: [] },
      "GET /cours/50": { json: { competence_id: 50, code: "FR5-RECIT", libelle: "Imparfait et passé simple", chapitre: IMPARFAIT.titre, chapitre_id: 5, cours: "Le décor à l'imparfait.", resume: "", objectifs: [], methodes: [], erreurs_frequentes: [], ressources: [] } },
      "GET /cours/50/questions": { json: [] },
      "GET /eleves/moi/competences/50/avancement": { json: null },
    });
    render(<EspaceEleve />);
    const reprise = (await screen.findByRole("heading", { name: IMPARFAIT.titre, level: 3 })).closest("section");
    await userEvent.click(within(reprise).getByRole("button", { name: /Commencer/ }));
    expect(screen.getByRole("tab", { name: "Mes cours" })).toHaveAttribute("aria-selected", "true");
    expect(await screen.findByText(/Le décor à l'imparfait/)).toBeInTheDocument();
    sessionStorage.clear();
  });

  it("les élèves de maths gardent leurs onglets", async () => {
    session("maths");
    fausseApi({});
    render(<EspaceEleve />);
    expect(await screen.findByRole("tab", { name: "S'entraîner" })).toHaveAttribute("aria-selected", "true");
    expect(screen.queryByRole("tab", { name: "Accueil" })).not.toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Cours" })).toBeInTheDocument();
    sessionStorage.clear();
  });
});
