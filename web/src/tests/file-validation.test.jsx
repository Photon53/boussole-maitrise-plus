// Issue #231 — File de validation du français (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import FileValidation, { grouperParChapitre } from "../enseignant/FileValidation.jsx";
import Validation from "../enseignant/Validation.jsx";
import { fausseApi } from "./setup.js";

const Q = (id, extra = {}) => ({
  id, code: `FR6-NAT-0${id}`, competence_id: 3, competence: "Identifier la classe d'un mot", chapitre: "La nature des mots",
  niveau: "6e", rubrique: "grammaire", domaine: "francais-college", type: "qcm", difficulte: 1,
  enonce: "Quelle est la classe du mot souligné ? « Le chat dort. » A) nom  B) verbe  C) adjectif",
  solution: "A", correction: { methode: "Chercher si le mot peut être précédé d'un déterminant.", etapes: ["« le chat » : déterminant + nom."] },
  auteur: "Brouillon IA (Claude)", source: "Boussole", licence_source: null, statut_validation: "a-valider",
  valide_par: null, peut_valider: true, motif_correction: null, ...extra,
});
const url = (statut, page = 1) => `GET /enseignants/validation/questions?domaine=francais-college&statut=${statut}&page=${page}`;
const page = (elements, total = elements.length) => ({ json: { total, elements } });

function routes(aValider, extra = {}) {
  return {
    [url("a-valider")]: page(aValider),
    [url("a-corriger")]: page([Q(9, { statut_validation: "a-corriger", motif_correction: "Énoncé ambigu." })]),
    [url("validee")]: page([], 27),
    ...extra,
  };
}
const ouvrir = () => render(<FileValidation jeton="j" onExpire={vi.fn()} domaines={["francais-college"]} />);

describe("file de validation du français (#231)", () => {
  it("regroupe les questions par chapitre", () => {
    const g = grouperParChapitre([Q(1), Q(2), Q(3, { chapitre: "Le présent", rubrique: "conjugaison" })]);
    expect(g.map((x) => [x.chapitre, x.questions.length])).toEqual([["La nature des mots", 2], ["Le présent", 1]]);
  });

  it("montre les compteurs, l'aperçu élève sans solution, puis le corrigé séparé", async () => {
    fausseApi(routes([Q(1), Q(2), Q(3, { chapitre: "Le présent", rubrique: "conjugaison", type: "texte", enonce: "Conjugue : « Nous (chanter) ensemble. »", solution: "chantons" })]));
    ouvrir();
    expect(await screen.findByRole("tab", { name: /À valider\s*3/ })).toHaveAttribute("aria-selected", "true");
    expect(await screen.findByRole("tab", { name: /Validées\s*27/ })).toBeInTheDocument();
    const chapitres = screen.getByRole("navigation", { name: "Chapitres" });
    expect(within(chapitres).getAllByRole("button")).toHaveLength(2);
    expect(screen.getByRole("heading", { name: "FR6-NAT-01 · question 1 sur 2" })).toBeInTheDocument();

    const apercu = screen.getByRole("region", { name: "Aperçu élève" });
    expect(within(apercu).getByText("Le chat dort.").closest("p")).toHaveClass("phrase-exercice");
    expect(within(apercu).getAllByRole("listitem")).toHaveLength(3);
    expect(apercu).not.toHaveTextContent("déterminant"); // ni méthode ni solution dans l'aperçu
    const corrige = screen.getByRole("region", { name: "Corrigé" });
    expect(corrige).toHaveTextContent("Réponse : A) nom");
    expect(corrige).toHaveTextContent("« le chat » : déterminant + nom.");

    await userEvent.click(screen.getByRole("button", { name: "Question suivante →" }));
    expect(screen.getByRole("heading", { name: "FR6-NAT-02 · question 2 sur 2" })).toBeInTheDocument();
    await userEvent.click(within(chapitres).getByRole("button", { name: /Le présent/ }));
    expect(screen.getByRole("heading", { name: "FR6-NAT-03 · question 1 sur 1" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Corrigé" })).toHaveTextContent("Réponse : chantons");
  });

  it("« À corriger » exige un motif, envoyé avec la décision ; la question quitte la file", async () => {
    const appels = fausseApi(routes([Q(1), Q(2)], {
      "POST /enseignants/validation/questions/1/validation": { json: Q(1, { statut_validation: "a-corriger" }) },
    }));
    ouvrir();
    const bouton = await screen.findByRole("button", { name: "À corriger" });
    expect(bouton).toBeDisabled();
    await userEvent.type(screen.getByLabelText("Motif (obligatoire pour « À corriger »)"), "Deux réponses possibles.");
    await userEvent.click(bouton);
    expect(appels.find((a) => a.cle.startsWith("POST")).corps).toEqual({ statut: "a-corriger", motif: "Deux réponses possibles." });
    expect(await screen.findByRole("status")).toHaveTextContent("FR6-NAT-01 renvoyée à l'auteur");
    expect(screen.getByRole("heading", { name: "FR6-NAT-02 · question 1 sur 1" })).toBeInTheDocument();
  });

  it("valider sans motif ; le refus de l'API (auteur) est affiché tel quel", async () => {
    const appels = fausseApi(routes([Q(1)], {
      "POST /enseignants/validation/questions/1/validation": { status: 422, json: { detail: "Vous êtes l'auteur de cette question : un autre professeur doit la valider." } },
    }));
    ouvrir();
    await userEvent.click(await screen.findByRole("button", { name: "✓ Valider" }));
    expect(appels.find((a) => a.cle.startsWith("POST")).corps).toEqual({ statut: "validee" });
    expect(await screen.findByText(/Vous êtes l'auteur de cette question/)).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: /FR6-NAT-01/ })).toBeInTheDocument();
  });

  it("file « À corriger » : motif du renvoi affiché, remise à valider possible", async () => {
    fausseApi(routes([Q(1)]));
    ouvrir();
    await userEvent.click(await screen.findByRole("tab", { name: /À corriger/ }));
    expect(await screen.findByText("Énoncé ambigu.")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Remettre à valider" })).toBeInTheDocument();
    expect(screen.queryByLabelText(/Motif/)).toBeNull();
  });

  it("hors périmètre : lecture seule, sans bouton de décision", async () => {
    fausseApi(routes([Q(1, { peut_valider: false })]));
    ouvrir();
    expect(await screen.findByText(/hors de votre périmètre de validation/)).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "✓ Valider" })).toBeNull();
  });
});

describe("page Validation", () => {
  it("un validateur de français seul arrive sur la file ; la banque d'exercices reste accessible", async () => {
    window.history.replaceState(null, "", "/enseignant/validation");
    fausseApi({
      "GET /enseignants/validation/perimetre": { json: [{ domaine: "francais-college", libelle: "Français collège", niveau: "6e" }] },
      ...routes([Q(1)]),
    });
    render(<Validation jeton="j" onExpire={vi.fn()} chemin="/enseignant/validation" />);
    expect(await screen.findByRole("heading", { name: "File de validation" })).toBeInTheDocument();
    expect(screen.getByRole("tab", { name: "File de validation (français)" })).toHaveAttribute("aria-selected", "true");
    expect(screen.getByRole("tab", { name: "Banque d'exercices" })).toBeInTheDocument();
  });
});
