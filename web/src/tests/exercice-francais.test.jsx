// Issue #231 — Exercice et correction expliquée en français (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import Exercice from "../eleve/Exercice.jsx";
import { decouperEnonce } from "../eleve/ExerciceFrancais.jsx";
import { fausseApi } from "./setup.js";

const CONJUGAISON = {
  id: 21, type: "texte", difficulte: 1, competence_id: 4,
  enonce: "Conjugue le verbe entre parenthèses au présent : « Elles (finir) leur repas. »",
};
const QCM = {
  id: 22, type: "qcm", difficulte: 1, competence_id: 5,
  enonce: "Quel est le sujet du verbe ? « Les enfants jouent dans la cour. » A) Les enfants  B) la cour  C) jouent",
};
const CORRECTION = {
  methode: "Trouver le groupe du verbe, puis la terminaison.",
  etapes: ["« finir » est du 2e groupe.", "Avec « elles », la terminaison est -issent."],
  resultat: "Elles finissent leur repas.",
  erreurs_frequentes: ["Écrire « finisent » avec un seul s."],
};

function api(question, resultat) {
  return fausseApi({
    "POST /seances": { status: 201, json: { id: 3 } },
    "GET /seances/3/question": { json: question },
    "POST /seances/3/reponses": { json: { maitrise: 0.3, maitrisee: false, ...resultat } },
  });
}

async function commencer(props = {}) {
  render(<Exercice jeton="j" onExpire={vi.fn()} francais {...props} />);
  await userEvent.click(screen.getByRole("button", { name: "Commencer à travailler" }));
}

describe("decouperEnonce", () => {
  it("sépare la consigne de la phrase étudiée", () => {
    expect(decouperEnonce(CONJUGAISON.enonce)).toEqual({
      consigne: "Conjugue le verbe entre parenthèses au présent",
      phrase: "Elles (finir) leur repas.",
      apres: "",
    });
  });

  it("sans guillemets, tout reste dans la consigne", () => {
    expect(decouperEnonce("Donne l'infinitif de « » ?").phrase).toBeNull();
    expect(decouperEnonce("Donne un synonyme de rapide.")).toEqual({ consigne: "Donne un synonyme de rapide.", phrase: null, apres: "" });
  });
});

describe("exercice de français", () => {
  it("met la phrase en scène et souligne le verbe à conjuguer, sans solution avant la réponse", async () => {
    api(CONJUGAISON, {});
    await commencer();
    const phrase = await screen.findByText((_, el) => el?.classList.contains("phrase-exercice"));
    expect(phrase).toHaveTextContent("Elles (finir) leur repas.");
    expect(within(phrase).getByText("(finir)")).toHaveClass("cible");
    expect(screen.getByText("Conjugue le verbe entre parenthèses au présent")).toBeInTheDocument();
    expect(screen.queryByText(/finissent/)).toBeNull();
    expect(screen.queryByRole("region", { name: "Correction expliquée" })).toBeNull();
  });

  it("le clavier d'accents insère la lettre au curseur et garde le focus", async () => {
    api(CONJUGAISON, {});
    await commencer();
    const champ = await screen.findByLabelText("Ta réponse");
    await userEvent.type(champ, "fini");
    await userEvent.click(screen.getByRole("button", { name: "Insérer é" }));
    expect(champ).toHaveValue("finié");
    await new Promise((r) => requestAnimationFrame(r));
    expect(champ).toHaveFocus();
  });

  it("correction expliquée : réponse donnée et attendue, méthode et étapes visibles, retour à la leçon", async () => {
    const appels = api(CONJUGAISON, { correcte: false, solution: "finissent", correction: CORRECTION });
    const onVoirCours = vi.fn();
    await commencer({ onVoirCours });
    await userEvent.type(await screen.findByLabelText("Ta réponse"), "finisent{Enter}");
    expect(appels.at(-1).corps).toEqual({ question_id: 21, reponse_donnee: "finisent" });

    expect(await screen.findByText("Pas encore : regardons ensemble.")).toBeInTheDocument();
    expect(screen.getByText("Ta réponse", { selector: ".badge" }).closest("li")).toHaveTextContent("finisent");
    expect(screen.getByText("Bonne réponse").closest("li")).toHaveTextContent("finissent");
    const methode = screen.getByRole("region", { name: "Correction expliquée" });
    expect(within(methode).getAllByRole("listitem").length).toBeGreaterThanOrEqual(2);
    expect(within(methode).getByText(/terminaison est -issent/)).toBeVisible();
    expect(within(methode).getByText("Erreur fréquente")).toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Question suivante" })).toHaveFocus();

    await userEvent.click(screen.getByRole("button", { name: "Revoir la méthode dans la leçon" }));
    expect(onVoirCours).toHaveBeenCalledWith(4, { ancre: "lecon-cours" });
  });

  it("QCM : choix en liste, focus sur le premier choix, réponses affichées en clair", async () => {
    api(QCM, { correcte: false, solution: "A" });
    await commencer();
    const premier = await screen.findByRole("button", { name: /Les enfants/ });
    expect(premier).toHaveFocus();
    expect(screen.getByText("Les enfants jouent dans la cour.").closest("p")).toHaveClass("phrase-exercice");
    await userEvent.click(screen.getByRole("button", { name: /la cour/ }));
    expect((await screen.findByText("Ta réponse", { selector: ".badge" })).closest("li")).toHaveTextContent("B) la cour");
    expect(screen.getByText("Bonne réponse").closest("li")).toHaveTextContent("A) Les enfants");
  });

  it("réponse juste : un verdict sobre", async () => {
    api(CONJUGAISON, { correcte: true, solution: "finissent" });
    await commencer();
    await userEvent.type(await screen.findByLabelText("Ta réponse"), "finissent{Enter}");
    expect(await screen.findByText("Bravo, c'est juste.")).toBeInTheDocument();
    expect(screen.queryByText("Ta réponse", { selector: ".badge" })).toBeNull();
  });
});

describe("maths inchangées", () => {
  it("sans la présentation française : ni clavier d'accents, ni correction expliquée", async () => {
    api(CONJUGAISON, { correcte: false, solution: "finissent" });
    render(<Exercice jeton="j" onExpire={vi.fn()} />);
    await userEvent.click(screen.getByRole("button", { name: "Commencer à travailler" }));
    await screen.findByLabelText("Ta réponse");
    expect(screen.queryByRole("group", { name: "Lettres accentuées" })).toBeNull();
    await userEvent.type(screen.getByLabelText("Ta réponse"), "x{Enter}");
    expect(await screen.findByText("Pas tout à fait.")).toBeInTheDocument();
    expect(screen.queryByText("Pas encore : regardons ensemble.")).toBeNull();
  });
});
