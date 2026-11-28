// Issue #102 — Accès à la préparation Français depuis la navigation adulte (Codex)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import App from "../App.jsx";
import { PageSimple } from "../enseignant/EspaceEnseignant.jsx";
import { fausseApi } from "./setup.js";

const PROFESSEUR = {
  jeton: "session-professeur", nom: "Compte Français", role: "enseignant",
  mdp_provisoire: false, enseigne_maths: false, enseigne_anglais: false,
};

const SYNTHESE_VIDE = {
  domaines: [{ code: "francais-college", libelle: "Français collège", actif: true, public: false }],
  chiffres: { cours: 0, cours_prets: 0, questions: 0, questions_validees: 0, classes_pilotes: 0, eleves_pilotes: 0 },
  niveaux: [], cours: [], classes: [], fonctions: [], alertes: [],
};

describe("navigation vers le Français en préparation", () => {
  it("propose le Français à la connexion maths sans l'ajouter au cadre partagé avec les parents", async () => {
    window.history.replaceState(null, "", "/enseignant");
    fausseApi({});
    const vue = render(<App />);
    expect(await screen.findByRole("heading", { name: "Connexion professeur" })).toBeInTheDocument();
    // #231 : un seul compte pour les deux matières ; la matière se choisit après la connexion.
    expect(screen.getByText(/choisissez la matière après la connexion/)).toBeInTheDocument();
    vue.unmount();
    render(<PageSimple><p>Connexion parent</p></PageSimple>);
    expect(screen.queryByRole("link", { name: /Français/ })).not.toBeInTheDocument();
  });

  it("propose une sortie vers le Français quand le compte est refusé en maths", async () => {
    window.history.replaceState(null, "", "/enseignant");
    sessionStorage.setItem("pkp.enseignant", JSON.stringify(PROFESSEUR));
    const appels = fausseApi({});
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Espace réservé aux professeurs de mathématiques" })).toBeInTheDocument();
    expect(screen.getByRole("link", { name: "Aller à l'espace Français (préparation)" })).toHaveAttribute("href", "/francais");
    expect(appels).toHaveLength(0);
  });

  it("ouvre les dossiers de français depuis la page Français de l'administration (#231)", async () => {
    window.history.replaceState(null, "", "/admin");
    sessionStorage.setItem("pkp.admin", JSON.stringify({ jeton: "session-admin", nom: "Admin", expire_le: Date.now() + 600_000 }));
    sessionStorage.setItem("pkp.enseignant", JSON.stringify(PROFESSEUR));
    const appels = fausseApi({
      "GET /admin/moi": { json: { permissions: ["pilotage.global", "contenu.lire"] } },
      "GET /admin/domaines": { json: [] },
      "GET /admin/statistiques?periode=30": { json: null },
      "GET /francais/dossiers": { json: [] },
      "GET /admin/francais/synthese": { json: SYNTHESE_VIDE },
    });
    render(<App />);
    const navigation = await screen.findByRole("navigation", { name: "Navigation Administration" });
    await userEvent.click(within(navigation).getByRole("link", { name: "Boussole Français" }));
    await userEvent.click(await screen.findByRole("link", { name: /Dossiers, validation et PDF/ }));
    expect(await screen.findByRole("heading", { name: "Dossiers de français" })).toBeInTheDocument();
    expect(window.location.pathname).toBe("/francais");
    expect(screen.getByText(/lue par les élèves/)).toBeInTheDocument();
    expect(appels.some((a) => a.cle === "GET /francais/dossiers")).toBe(true);
    expect(appels.some((a) => a.cle.startsWith("GET /enseignants/"))).toBe(false);
  });

  it("reprend la session d'administration si aucune session professeur n'existe (#217)", async () => {
    window.history.replaceState(null, "", "/francais");
    sessionStorage.setItem("pkp.admin", JSON.stringify({ jeton: "session-admin", nom: "Admin", expire_le: Date.now() + 600_000 }));
    const appels = fausseApi({
      "GET /francais/dossiers": { json: [] },
      "GET /francais/etat": { json: { domaines: [], dossiers: 0 } },
      "GET /francais/validation": { json: [] },
    });
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Dossiers de français" })).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Connexion — Français (préparation)" })).not.toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: /Administration · Français/ })[0]).toHaveAttribute("href", "/admin/francais");
    expect(screen.queryByRole("link", { name: "Espace professeur" })).toBeNull();
    expect(appels.some((a) => a.cle === "GET /francais/validation")).toBe(true);
  });

  it("#231 : depuis les dossiers, retour à l'espace professeur (plus d'impasse)", async () => {
    window.history.replaceState(null, "", "/francais");
    sessionStorage.setItem("pkp.enseignant", JSON.stringify({ ...PROFESSEUR, enseigne_maths: true, enseigne_francais: true }));
    fausseApi({
      "GET /francais/dossiers": { json: [] },
      "GET /francais/etat": { json: { domaines: [], dossiers: 0 } },
      "GET /francais/validation": { status: 403, json: { detail: "Réservé aux validateurs de français." } },
    });
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Dossiers de français" })).toBeInTheDocument();
    expect(screen.getAllByRole("link", { name: "Espace professeur" })[0]).toHaveAttribute("href", "/enseignant/francais");
    expect(screen.queryByRole("link", { name: /Administration/ })).toBeNull();
    sessionStorage.removeItem("pkp.enseignant");
  });

  it("demande une connexion professeur si la session admin a expiré", async () => {
    window.history.replaceState(null, "", "/francais");
    sessionStorage.setItem("pkp.admin", JSON.stringify({ jeton: "session-admin", nom: "Admin", expire_le: Date.now() - 1 }));
    const appels = fausseApi({});
    render(<App />);
    expect(await screen.findByRole("heading", { name: "Connexion — Français (préparation)" })).toBeInTheDocument();
    expect(appels).toHaveLength(0);
  });

  it("l'espace professeur mène à la validation du français (#217)", async () => {
    window.history.replaceState(null, "", "/enseignant");
    sessionStorage.setItem("pkp.enseignant", JSON.stringify({ ...PROFESSEUR, enseigne_francais: true }));
    fausseApi({ "GET /enseignants/classes": { json: [] }, "GET /francais/classes": { json: [] } });
    render(<App />);
    // Issue #231 : les dossiers sont une entrée du groupe « Français » de l'espace professeur.
    const navigation = await screen.findByRole("navigation", { name: "Navigation Espace professeur" });
    expect(within(navigation).getByRole("link", { name: "Dossiers et PDF" })).toHaveAttribute("href", "/francais");
  });
});
