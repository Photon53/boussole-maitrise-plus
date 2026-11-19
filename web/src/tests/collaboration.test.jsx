// Issue #171 — Candidatures de professeurs et demandes de partenariat (Claude)
import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import Accueil from "../Accueil.jsx";
import AccueilDemandes from "../admin/AccueilDemandes.jsx";
import Collaborer from "../Collaborer.jsx";
import { fausseApi } from "./setup.js";

const OUVERT = { ouvert: true, formats_cv: ["pdf"], cv_taille_max_mo: 5, conservation_jours: 180 };

async function coordonnees() {
  await userEvent.type(screen.getByLabelText("Prénom (obligatoire)"), "Camille");
  await userEvent.type(screen.getByLabelText("Nom (obligatoire)"), "Fictif");
  await userEvent.type(screen.getByLabelText(/^E-mail/), "camille@exemple.test");
}

describe("Enseigner ou collaborer avec nous", () => {
  it.each([[true], [false]])("accueil : l'entrée n'apparaît que si la collecte est ouverte (%s)", async (ouvert) => {
    fausseApi({ "GET /collaboration/etat": { json: { ...OUVERT, ouvert } } });
    render(<Accueil />);
    await screen.findByRole("heading", { level: 1 });
    await new Promise((r) => setTimeout(r, 0));
    const lien = screen.queryByRole("link", { name: "Enseigner ou collaborer avec nous" });
    if (ouvert) expect(lien).toHaveAttribute("href", "/collaborer");
    else expect(lien).not.toBeInTheDocument();
  });

  it("fermé : aucun formulaire", async () => {
    fausseApi({ "GET /collaboration/etat": { json: { ...OUVERT, ouvert: false } } });
    render(<Collaborer />);
    expect(await screen.findByText(/ne sont pas encore ouvertes/)).toBeInTheDocument();
    expect(screen.queryByRole("radio")).not.toBeInTheDocument();
  });

  it("professeur : information, champs minimisés, envoi unique et référence", async () => {
    // Réponse différée : le bouton reste désactivé pendant l'envoi (pas de double demande).
    let resoudre;
    const appels = [];
    vi.stubGlobal("fetch", vi.fn(async (url, { method = "GET", body } = {}) => {
      const cle = `${method} ${url.replace(/^\/api/, "")}`;
      appels.push({ cle, corps: body ? JSON.parse(body) : undefined });
      if (cle === "GET /collaboration/etat") return { ok: true, status: 200, json: async () => OUVERT };
      return new Promise((r) => {
        resoudre = () => r({ ok: true, status: 201, json: async () => ({ reference: "C-ABCD2345", type: "candidature" }) });
      });
    }));
    render(<Collaborer />);
    await userEvent.click(await screen.findByLabelText(/Professeur ou/));
    expect(screen.getByText(/supprimés 180 jours après/)).toBeInTheDocument();
    await coordonnees();
    await userEvent.click(screen.getByLabelText("Mathématiques"));
    await userEvent.click(screen.getByLabelText("2nde"));
    const envoyer = screen.getByRole("button", { name: "Envoyer ma demande" });
    expect(envoyer).toBeDisabled(); // information pas encore lue
    await userEvent.click(screen.getByLabelText(/J'ai lu comment/));
    await userEvent.click(envoyer);
    expect(screen.getByRole("button", { name: "Envoi en cours…" })).toBeDisabled();
    const envoi = appels.filter((a) => a.cle === "POST /collaboration/candidatures");
    expect(envoi).toHaveLength(1);
    expect(envoi[0].corps).toMatchObject({
      prenom: "Camille", nom: "Fictif", email: "camille@exemple.test", telephone: null, matieres: ["maths"], niveaux: ["2nde"],
      information_lue: true, site_web: "", cv_base64: null,
    });
    resoudre();
    expect(await screen.findByText("C-ABCD2345")).toBeInTheDocument();
    expect(screen.getByText(/n'est pas automatique/)).toBeInTheDocument();
  });

  it("CV : un fichier trop gros ou d'un autre type est refusé avant l'envoi", async () => {
    fausseApi({ "GET /collaboration/etat": { json: { ...OUVERT, cv_taille_max_mo: 1 } } });
    render(<Collaborer />);
    await userEvent.click(await screen.findByLabelText(/Professeur ou/));
    const champ = screen.getByLabelText(/^CV \(facultatif\)/);
    await userEvent.upload(champ, new File([new Uint8Array(2 * 1024 * 1024)], "cv.pdf", { type: "application/pdf" }));
    expect(screen.getByRole("alert")).toHaveTextContent("Le CV dépasse 1 Mo.");
    await userEvent.upload(champ, new File(["x"], "cv.docx", { type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document" }), {
      applyAccept: false,
    });
    expect(screen.getByRole("alert")).toHaveTextContent("Le CV doit être un fichier PDF.");
  });

  it("structure : formulaire adapté et erreur du serveur affichée", async () => {
    const appels = fausseApi({
      "GET /collaboration/etat": { json: OUVERT },
      "POST /collaboration/partenariats": { status: 429, json: { detail: "Trop de tentatives. Réessayez dans 60 minutes." } },
    });
    render(<Collaborer />);
    await userEvent.click(await screen.findByLabelText(/Une école, un/));
    expect(screen.queryByLabelText(/^CV/)).not.toBeInTheDocument();
    await userEvent.type(screen.getByLabelText("Nom de la structure (obligatoire)"), "Association Fictive");
    await userEvent.selectOptions(screen.getByLabelText("Type de structure (obligatoire)"), "association");
    await coordonnees();
    await userEvent.type(screen.getByLabelText("Partenariat envisagé (obligatoire)"), "Soutien scolaire de nos adhérents.");
    await userEvent.click(screen.getByLabelText(/J'ai lu comment/));
    await userEvent.click(screen.getByRole("button", { name: "Envoyer ma demande" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("Trop de tentatives");
    expect(appels.find((a) => a.cle === "POST /collaboration/partenariats").corps).toMatchObject({
      structure_nom: "Association Fictive", structure_type: "association", partenariat: "Soutien scolaire de nos adhérents.",
    });
    expect(screen.getByRole("button", { name: "Envoyer ma demande" })).toBeEnabled(); // on peut réessayer
  });
});

describe("Accueil et demandes", () => {
  const resume = { id: 1, reference: "C-ABCD2345", type: "candidature", contact: "Camille Fictif", structure_nom: null, statut: "nouveau", issue: null, a_un_cv: true, responsable: null, cree_le: "2026-11-19T08:00:00Z" };
  const detail = { ...resume, prenom: "Camille", nom: "Fictif", email: "camille@exemple.test", telephone: null, matieres: ["maths"], niveaux: ["2nde"], disponibilites: null, structure_type: null, fonction: null, message: "Bonjour", cv_taille_octets: 1000, notes_internes: null, responsable_id: null, maj_le: "2026-11-19T08:00:00Z" };

  it("deux files distinctes ; l'issue est exigée pour marquer une demande traitée", async () => {
    const appels = fausseApi({
      "GET /admin/accueil/demandes?type=candidature&page=1": { json: { demandes: [resume], total: 1, page: 1, taille_page: 50 } },
      "GET /admin/accueil/demandes?type=partenariat&page=1": { json: { demandes: [], total: 0, page: 1, taille_page: 50 } },
      "GET /admin/accueil/demandes/1": { json: detail },
      "GET /admin/moi": { json: { id: 2, nom: "Admin" } },
      "POST /admin/accueil/demandes/1": (corps) => ({ json: { ...detail, ...corps } }),
    });
    render(<AccueilDemandes jeton="j" onExpire={vi.fn()} />);
    await userEvent.click(await screen.findByRole("button", { name: "C-ABCD2345" }));
    const fiche = await screen.findByRole("article", { name: "Demande C-ABCD2345" });
    expect(within(fiche).getByText("camille@exemple.test")).toBeInTheDocument();
    expect(within(fiche).getByRole("button", { name: "Télécharger le CV" })).toBeInTheDocument();
    const marquer = within(fiche).getByRole("button", { name: "Marquer traitée" });
    expect(marquer).toBeDisabled();
    await userEvent.selectOptions(within(fiche).getByLabelText("Issue"), "suite-demandee");
    await userEvent.click(marquer);
    expect(appels.find((a) => a.cle === "POST /admin/accueil/demandes/1").corps).toEqual({ statut: "traite", issue: "suite-demandee" });

    await userEvent.click(screen.getByRole("tab", { name: "Partenariats de structures" }));
    expect(await screen.findByText("Aucune demande dans cette file.")).toBeInTheDocument();
  });
});
