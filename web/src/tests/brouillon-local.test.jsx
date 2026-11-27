// Issue #231 — Brouillon de rédaction gardé sur l'appareil, durée réglable (Claude)
import { act, render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import AtelierRedaction from "../eleve/AtelierRedaction.jsx";
import { ecrireBrouillon, lireBrouillon, PREFIXE, purgerBrouillons } from "../eleve/brouillonLocal.js";
import { fausseApi } from "./setup.js";

const JOUR = 24 * 60 * 60 * 1000;
const T0 = Date.UTC(2026, 10, 27, 8);
const reponse = (jours, ouverte = false) => ({ json: { ouverte, brouillon_jours: jours, sujets: [{ question_id: 7, enonce: "Raconte une aventure." }] } });

afterEach(() => {
  localStorage.clear();
  vi.useRealTimers();
});

describe("brouillon local : stockage", () => {
  it("garde le texte N jours après la dernière modification, par élève et par sujet", () => {
    ecrireBrouillon(1, 7, "Il était une fois.", 10, T0);
    expect(lireBrouillon(1, 7, 10, T0 + 9 * JOUR).texte).toBe("Il était une fois.");
    expect(lireBrouillon(2, 7, 10, T0)).toBeNull(); // un autre élève du même poste
    expect(lireBrouillon(1, 7, 10, T0 + 10 * JOUR)).toBeNull();
    expect(localStorage.getItem(`${PREFIXE}1.7`)).toBeNull(); // effacé à la lecture
  });

  it("une modification repart pour N jours ; un texte vide ou une durée nulle efface", () => {
    ecrireBrouillon(1, 7, "a", 10, T0);
    ecrireBrouillon(1, 7, "ab", 10, T0 + 8 * JOUR);
    expect(lireBrouillon(1, 7, 10, T0 + 15 * JOUR).texte).toBe("ab");
    ecrireBrouillon(1, 7, "  ", 10, T0 + 15 * JOUR);
    expect(lireBrouillon(1, 7, 10, T0 + 15 * JOUR)).toBeNull();
    expect(ecrireBrouillon(1, 7, "texte", 0, T0)).toBeNull();
    expect(localStorage.length).toBe(0);
  });

  it("la purge efface les brouillons périmés, et plus tôt si la durée a été raccourcie", () => {
    ecrireBrouillon(1, 7, "ancien", 10, T0);
    ecrireBrouillon(2, 7, "récent", 10, T0 + 5 * JOUR);
    localStorage.setItem("pkp.autre", "garde");
    purgerBrouillons(null, T0 + 11 * JOUR);
    expect(localStorage.getItem(`${PREFIXE}1.7`)).toBeNull();
    expect(localStorage.getItem(`${PREFIXE}2.7`)).not.toBeNull();
    purgerBrouillons(3, T0 + 11 * JOUR); // durée ramenée à 3 jours
    expect(localStorage.getItem(`${PREFIXE}2.7`)).toBeNull();
    expect(localStorage.getItem("pkp.autre")).toBe("garde");
  });
});

describe("brouillon local : atelier fermé", () => {
  it("l'élève écrit, le brouillon est enregistré sur l'appareil, retrouvé, puis effacé à sa demande ; rien n'est envoyé", async () => {
    const appels = fausseApi({ "GET /francais/eleve/redaction/12": reponse(10) });
    const { unmount } = render(<AtelierRedaction jeton="j" onExpire={vi.fn()} competenceId={12} eleveId={1} />);
    const champ = await screen.findByLabelText("Mon brouillon");
    expect(screen.getByText("Gardé 10 jours sur cet appareil seulement")).toBeInTheDocument();
    await userEvent.type(champ, "Il était une fois.");
    expect(await screen.findByText(/Enregistré sur cet appareil seulement, jusqu'au/, {}, { timeout: 2000 })).toBeInTheDocument();
    expect(JSON.parse(localStorage.getItem(`${PREFIXE}1.7`)).texte).toBe("Il était une fois.");
    unmount();

    render(<AtelierRedaction jeton="j" onExpire={vi.fn()} competenceId={12} eleveId={1} />);
    expect(await screen.findByLabelText("Mon brouillon")).toHaveValue("Il était une fois.");
    await userEvent.click(screen.getByRole("button", { name: "Effacer mon brouillon" }));
    expect(screen.getByLabelText("Mon brouillon")).toHaveValue("");
    expect(localStorage.getItem(`${PREFIXE}1.7`)).toBeNull();
    expect(appels.every((a) => a.cle === "GET /francais/eleve/redaction/12")).toBe(true);
  });

  it("durée réglée à 0, ou simulation par un adulte (sans élève) : pas de brouillon", async () => {
    fausseApi({ "GET /francais/eleve/redaction/12": reponse(0) });
    render(<AtelierRedaction jeton="j" onExpire={vi.fn()} competenceId={12} eleveId={1} />);
    expect(await screen.findByText(/Rédige sur ta copie/)).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).toBeNull();
  });

  it("sans identifiant d'élève : pas de brouillon", async () => {
    fausseApi({ "GET /francais/eleve/redaction/12": reponse(10) });
    render(<AtelierRedaction jeton="j" onExpire={vi.fn()} competenceId={12} />);
    expect(await screen.findByText(/Rédige sur ta copie/)).toBeInTheDocument();
    expect(screen.queryByRole("textbox")).toBeNull();
    await act(async () => {});
  });
});
