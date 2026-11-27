// Issue #180 — Mon cours : fiches de la professeure au fil du cours (Claude)
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import EspaceEleve from "../eleve/EspaceEleve.jsx";
import MonCours from "../eleve/MonCours.jsx";
import { fausseApi } from "./setup.js";

const LIEN = {
  id: 9, type: "lien", titre: "Tableau de conjugaison", description: "", url: "https://fr.wikipedia.org/wiki/Conjugaison",
  domaine: "fr.wikipedia.org", taille_octets: null, portee: "classe",
};

describe("Mon cours (#180)", () => {
  it("montre les chapitres ouverts dans l'ordre, avec les liens de la professeure", async () => {
    fausseApi({
      "GET /cours/mon-cours": {
        json: [
          { id: 1, titre: "Le présent", ressources: [LIEN] },
          { id: 2, titre: "L'imparfait", ressources: [] },
        ],
      },
    });
    render(<MonCours jeton="j" onExpire={vi.fn()} />);
    expect(await screen.findByRole("heading", { name: "Le présent" })).toBeInTheDocument();
    const lien = screen.getByRole("link", { name: "Tableau de conjugaison" });
    expect(lien).toHaveAttribute("href", "https://fr.wikipedia.org/wiki/Conjugaison");
    expect(lien).toHaveAttribute("rel", "noopener noreferrer");
    expect(screen.getByRole("heading", { name: "L'imparfait" })).toBeInTheDocument();
    expect(screen.getByText("Pas encore de fiche pour ce chapitre.")).toBeInTheDocument();
  });

  it("annonce qu'aucun chapitre n'est encore ouvert", async () => {
    fausseApi({ "GET /cours/mon-cours": { json: [] } });
    render(<MonCours jeton="j" onExpire={vi.fn()} />);
    expect(await screen.findByText("Ta professeure n'a pas encore ouvert de chapitre.")).toBeInTheDocument();
  });
});

const ACCUEIL_VIDE = {
  eleve: { prenom: "Lina", classe: "5E-FR-AAAAA", niveau: "5e" }, acces: true, presentation: { mode: "guide", origine: "defaut" },
  etapes: ["Découvrir", "Comprendre", "Appliquer", "S'entraîner", "Approfondir", "Réinvestir", "Consolider"],
  cours: [], reprise: null, rubriques: { lire: 0, grammaire: 0, conjugaison: 0, redaction: 0 }, redaction_ouverte: false,
};
const DOSSIER = {
  cle: "dossier-FR3-DNB27-01", type: "dossier", code: "FR3-DNB27-01", titre: "Comprendre un texte", rubrique: "lire",
  nb_quiz: 6, etat: "pas_commence", score: null, total: null, tentatives: 0, etape: 1, derniere_activite: null,
};

describe("onglet « Mon cours » selon la matière (#180)", () => {
  const session = (matiere) =>
    sessionStorage.setItem(
      "pkp.eleve",
      JSON.stringify({ jeton: "j", eleve: { id: 1, prenom: "Lina", code_classe: "5E-FR-AAAAA", niveau: "5e", matiere } }),
    );

  // Issue #231 : « Mon cours » devient « Ressources de ta professeure », sous « Plus » (FR-UI-D1, FR-UI-D5).
  it("apparaît sous « Plus » pour une classe de français", async () => {
    session("francais");
    fausseApi({
      "GET /francais/eleve/accueil": { json: ACCUEIL_VIDE },
      "GET /cours/mon-cours": { json: [{ id: 1, titre: "Le présent", ressources: [LIEN] }] },
    });
    render(<EspaceEleve />);
    await userEvent.click(await screen.findByRole("tab", { name: "Plus" }));
    await userEvent.click(screen.getByRole("button", { name: /Ressources de ta professeure/ }));
    expect(await screen.findByRole("heading", { name: "Mon cours" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "Plus" })).toHaveAttribute("aria-selected", "true");
    sessionStorage.clear();
  });

  it("les dossiers ouverts à la classe sont dans « Mes cours », avec les chapitres (#217, #231)", async () => {
    session("francais");
    fausseApi({
      "GET /francais/eleve/accueil": { json: { ...ACCUEIL_VIDE, cours: [DOSSIER], rubriques: { lire: 1, grammaire: 0, conjugaison: 0, redaction: 0 } } },
      "GET /cours/mon-cours": { json: [] },
      "GET /francais/eleve/dossiers": { json: [{ code: "FR3-DNB27-01", titre: "Comprendre un texte", niveau: "3e", version: 1 }] },
    });
    render(<EspaceEleve />);
    await userEvent.click(await screen.findByRole("tab", { name: "Mes cours" }));
    expect(await screen.findByRole("heading", { name: "Comprendre un texte" })).toBeInTheDocument();
    expect(screen.getByText("Lire et comprendre")).toBeInTheDocument();
    sessionStorage.clear();
  });

  it("n'apparaît pas pour une classe de maths", async () => {
    session("maths");
    fausseApi({});
    render(<EspaceEleve />);
    expect(await screen.findByRole("tab", { name: "S'entraîner" })).toBeInTheDocument();
    expect(screen.queryByRole("tab", { name: "Mon cours" })).not.toBeInTheDocument();
    sessionStorage.clear();
  });
});
