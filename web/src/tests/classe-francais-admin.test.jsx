// Issue #231 — Créer une classe de français depuis « Élèves et classes » (Claude)
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import NouvelleClasseFrancais from "../admin/NouvelleClasseFrancais.jsx";
import { api } from "../api.js";
import { fausseApi } from "./setup.js";

const DOMAINE = (extra = {}) => ({
  code: "francais-college", matiere: "francais", cycle: "college", libelle: "Français collège", niveaux: ["6e", "5e", "4e", "3e"],
  actif: true, public: false, nb_professeurs: 1, nb_validateurs: 1, ...extra,
});
const MATHS = { code: "maths-lycee", matiere: "maths", cycle: "lycee", libelle: "Maths lycée", niveaux: ["2nde"], actif: true, public: true, nb_professeurs: 2, nb_validateurs: 1 };
const appeler = (chemin, options) => api(chemin, { ...options, jeton: "j" });

function ouvrir(domaines, extra = {}) {
  const appels = fausseApi({
    "GET /admin/domaines": { json: domaines },
    "GET /admin/enseignants?domaine=francais-college": { json: [{ id: 4, nom: "Mme Leroy (fictif)", actif: true }, { id: 5, nom: "Ancien compte", actif: false }] },
    ...extra,
  });
  const onCreee = vi.fn();
  render(<NouvelleClasseFrancais appeler={appeler} onFermer={vi.fn()} onCreee={onCreee} />);
  return { appels, onCreee };
}

describe("nouvelle classe de français (#231)", () => {
  it("domaine fermé au public : classe pilote avec motif (SEC-D6)", async () => {
    const { appels, onCreee } = ouvrir([MATHS, DOMAINE()], {
      "POST /admin/classes-pilotes": { status: 201, json: { classe_id: 9, code: "3E-FR-ABCDE" } },
    });
    expect(await screen.findByText(/sera une/)).toHaveTextContent("classe pilote");
    await userEvent.selectOptions(screen.getByLabelText("Niveau"), "3e");
    const prof = screen.getByLabelText("Professeur de français");
    expect([...prof.options].map((o) => o.textContent)).toEqual(["Choisir…", "Mme Leroy (fictif)"]); // comptes actifs
    await userEvent.selectOptions(prof, "4");
    const creer = screen.getByRole("button", { name: "Créer la classe" });
    expect(creer).toBeDisabled(); // motif requis
    await userEvent.type(screen.getByLabelText("Motif du pilote"), "Pilote de janvier 2027");
    await userEvent.click(creer);
    expect(appels.find((a) => a.cle === "POST /admin/classes-pilotes").corps).toEqual({
      matiere: "francais", niveau: "3e", enseignant_id: 4, motif: "Pilote de janvier 2027",
    });
    expect(onCreee).toHaveBeenCalledWith(expect.objectContaining({ code: "3E-FR-ABCDE", pilote: true }));
  });

  it("domaine ouvert au public : classe ordinaire, sans motif", async () => {
    const { appels, onCreee } = ouvrir([DOMAINE({ public: true })], {
      "POST /admin/classes": { status: 201, json: { id: 9, code: "6E-FR-ABCDE" } },
    });
    await userEvent.selectOptions(await screen.findByLabelText("Niveau"), "6e");
    await userEvent.selectOptions(screen.getByLabelText("Professeur de français"), "4");
    expect(screen.queryByLabelText("Motif du pilote")).toBeNull();
    await userEvent.click(screen.getByRole("button", { name: "Créer la classe" }));
    expect(appels.find((a) => a.cle === "POST /admin/classes").corps).toEqual({
      matiere: "francais", niveau: "6e", enseignant_id: 4, parcours: "tronc-commun",
    });
    expect(onCreee).toHaveBeenCalledWith(expect.objectContaining({ code: "6E-FR-ABCDE", pilote: false }));
  });

  it("français inactif : rien à créer, renvoi vers la configuration", async () => {
    ouvrir([MATHS, DOMAINE({ actif: false })]);
    expect(await screen.findByRole("note")).toHaveTextContent("Le français n'est pas activé");
    expect(screen.getByRole("button", { name: "Ouvrir la configuration" })).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Créer la classe" })).toBeNull();
  });

  it("le refus de l'API est affiché (professeur non habilité)", async () => {
    ouvrir([DOMAINE()], {
      "POST /admin/classes-pilotes": { status: 422, json: { detail: "Ce professeur n'est pas habilité en Français collège (3e)." } },
    });
    await userEvent.selectOptions(await screen.findByLabelText("Niveau"), "3e");
    await userEvent.selectOptions(screen.getByLabelText("Professeur de français"), "4");
    await userEvent.type(screen.getByLabelText("Motif du pilote"), "Essai");
    await userEvent.click(screen.getByRole("button", { name: "Créer la classe" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("n'est pas habilité");
  });
});
