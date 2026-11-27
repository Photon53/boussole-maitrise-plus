// Issue #231 — Atelier de rédaction de l'écran de cours (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import AtelierRedaction, { criteresDuCours } from "../eleve/AtelierRedaction.jsx";
import { compter, RAPPEL } from "../eleve/Redaction.jsx";
import { fausseApi } from "./setup.js";

const ENONCE = "Raconte, au présent, une aventure inventée.\n\nTon récit comprend une situation initiale et un dénouement.";
const CRITERES = [{ titre: "Mes critères de réussite", texte: "- Mon récit a un début, des péripéties et une fin.\n- J’écris au présent.\n- J’ai fait au moins quatre paragraphes." }];
const RELIRE = [{ titre: "Relire et réécrire", texte: "Relis une fois pour le sens, une fois pour les accords." }];
const SUJETS = (ouverte) => ({ json: { ouverte, sujets: [{ question_id: 7, enonce: ENONCE }] } });

function ouvrir(props = {}) {
  render(<AtelierRedaction jeton="j" onExpire={vi.fn()} competenceId={12} criteres={CRITERES} relire={RELIRE} {...props} />);
}

describe("atelier de rédaction (#231)", () => {
  it("extrait les critères de réussite du cours", () => {
    expect(criteresDuCours(CRITERES)).toEqual([
      "Mon récit a un début, des péripéties et une fin.", "J’écris au présent.", "J’ai fait au moins quatre paragraphes.",
    ]);
    expect(compter("Il était une fois.\n\nPuis un dragon.")).toEqual({ mots: 7, paragraphes: 2 });
    expect(compter("  ")).toEqual({ mots: 0, paragraphes: 0 });
  });

  it("fermée : consigne et critères, rédaction sur copie, aucun champ de saisie ni appel aux rédactions", async () => {
    const appels = fausseApi({ "GET /francais/eleve/redaction/12": SUJETS(false) });
    ouvrir();
    expect(await screen.findByText("Raconte, au présent, une aventure inventée.")).toHaveClass("consigne-texte");
    expect(screen.getByText(/situation initiale et un dénouement/)).toBeInTheDocument();
    expect(screen.getByText(/La rédaction en ligne n'est pas encore ouverte\./).closest(".etat-ferme")).toHaveTextContent("Rédige sur ta copie");
    expect(screen.getByText(RAPPEL)).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).toBeNull();
    expect(appels.map((a) => a.cle)).toEqual(["GET /francais/eleve/redaction/12"]);
  });

  it("les critères se cochent pour se relire ; rien n'est envoyé", async () => {
    const appels = fausseApi({ "GET /francais/eleve/redaction/12": SUJETS(false) });
    ouvrir();
    const aside = await screen.findByRole("complementary", { name: "Pour t'aider à écrire" });
    const cases = within(aside).getAllByRole("checkbox");
    expect(cases).toHaveLength(3);
    await userEvent.click(within(aside).getByLabelText("J’écris au présent."));
    expect(within(aside).getByText("1 critère vérifié sur 3")).toBeInTheDocument();
    expect(within(aside).getByRole("heading", { name: "Relire et réécrire" })).toBeInTheDocument();
    expect(appels).toHaveLength(1);
  });

  it("ouverte : l'éditeur de #179 avec compteur de mots et de paragraphes, puis la remise", async () => {
    const detail = (versions) => ({ question_id: 7, enonce: ENONCE, versions, conserver_jusqu_au: "2027-08-31" });
    const v = (statut) => ({ id: 1, version: 1, texte: "Il était une fois.", statut, commentaire: null, maj_le: "2026-11-27T08:00:00Z", remise_le: null, corrigee_le: null });
    fausseApi({
      "GET /francais/eleve/redaction/12": SUJETS(true),
      "GET /eleves/moi/redactions/7": { json: detail([]) },
      "PUT /eleves/moi/redactions/7": { json: detail([v("brouillon")]) },
      "POST /eleves/moi/redactions/7/remise": { json: detail([v("remise")]) },
    });
    ouvrir();
    const champ = await screen.findByLabelText("Ta rédaction");
    await userEvent.type(champ, "Il était une fois.{Enter}{Enter}Un dragon arrive.");
    expect(screen.getByText(/7 mots · 2 paragraphes/)).toBeInTheDocument();
    await userEvent.click(screen.getByRole("button", { name: "Remettre à ma professeure" }));
    expect(await screen.findByText("Ta rédaction est remise : ta professeure va la corriger.")).toBeInTheDocument();
  });

  it("aucun sujet ouvert pour ce cours", async () => {
    fausseApi({ "GET /francais/eleve/redaction/12": { json: { ouverte: false, sujets: [] } } });
    ouvrir();
    expect(await screen.findByText("Pas encore de sujet de rédaction ouvert pour ce cours.")).toBeInTheDocument();
  });
});
