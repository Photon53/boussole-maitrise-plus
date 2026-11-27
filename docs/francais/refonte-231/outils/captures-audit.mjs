// Issue #231 — Captures d'audit des écrans Français actuels, pile locale jetable uniquement (Claude)
//
// RÉSERVÉ à une pile locale jetable (base SQLite temporaire, comptes de démonstration) : le script crée des comptes
// fictifs, valide un dossier et ouvre des contenus à une classe pilote. Il refuse toute adresse non locale.
// Préparation : voir README.md § 2 (base temporaire, migrations, seed, import, API sur 8765, front sur 5765).
//
//   node docs/francais/refonte-231/outils/captures-audit.mjs <dossier-de-sortie>
import { createRequire } from "node:module";
import { mkdirSync, writeFileSync } from "node:fs";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");

const BASE = process.env.BASE_URL ?? "http://127.0.0.1:5765";
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(BASE)) throw new Error("Pile locale jetable uniquement (AGENTS.md § 1).");
const SORTIE = process.argv[2];
mkdirSync(SORTIE, { recursive: true });
const MDP = "Audit-231-Fictif!";
const DOMAINE = "francais-college";
const TAILLES = { ordinateur: { width: 1366, height: 900 }, tablette: { width: 820, height: 1180 }, mobile: { width: 390, height: 844 } };
const journal = [];

async function api(chemin, { methode = "GET", corps, jeton } = {}) {
  const r = await fetch(`${BASE}/api${chemin}`, {
    method: methode,
    headers: { "Content-Type": "application/json", ...(jeton ? { Authorization: `Bearer ${jeton}` } : {}) },
    body: corps ? JSON.stringify(corps) : undefined,
  });
  const t = await r.text();
  let j; try { j = JSON.parse(t); } catch { j = t; }
  if (r.status >= 400) throw new Error(`${methode} ${chemin} → ${r.status} ${t.slice(0, 300)}`);
  return j;
}

async function prof(admin, suffixe, habilitations) {
  const email = `audit-231-${suffixe}@exemple.test`;
  const c = await api("/admin/enseignants", { methode: "POST", jeton: admin, corps: { nom: `Prof. ${suffixe} (fictif)`, email, role: "enseignant", habilitations } });
  const { jeton } = await api("/enseignants/connexion", { methode: "POST", corps: { email, mot_de_passe: c.mot_de_passe_provisoire } });
  await api("/enseignants/mot-de-passe", { methode: "POST", jeton, corps: { actuel: c.mot_de_passe_provisoire, nouveau: MDP } });
  return { id: c.enseignant.id, email };
}

// --- Données fictives -------------------------------------------------------------------------------------
const { jeton: admin } = await api("/admin/connexion", { methode: "POST", corps: { email: "admin@pkp.test", mot_de_passe: "demo-pkp-2026" } });
await api(`/admin/domaines/${DOMAINE}`, { methode: "POST", jeton: admin, corps: { actif: true, public: false } });
const p3 = await prof(admin, "francais-3e", [{ role: "professeur", domaine: DOMAINE, niveau: "3e" }]);
const val = await prof(admin, "validatrice", [
  { role: "professeur", domaine: DOMAINE, niveau: "4e" }, { role: "validateur", domaine: DOMAINE, niveau: "4e" },
  { role: "validateur", domaine: DOMAINE, niveau: "3e" },
]);
const { jeton: jp } = await api("/enseignants/connexion", { methode: "POST", corps: { email: p3.email, mot_de_passe: MDP } });
const cp = await api("/admin/classes-pilotes", { methode: "POST", jeton: admin, corps: { matiere: "francais", niveau: "3e", enseignant_id: p3.id, motif: "Audit #231 (données fictives)" } });
const el = await api(`/enseignants/classes/${cp.classe_id}/eleves`, { methode: "POST", jeton: jp, corps: { prenoms: ["Lina", "Yanis", "Inès"] } });
const lina = el.crees.find((e) => e.prenom === "Lina");
// Dossier validé (admin ≠ auteur) puis ouvert à la classe ; chapitres de 3e proposés à la classe.
await api("/francais/dossiers/FR3-DNB27-01/valider", { methode: "POST", jeton: admin }).catch((e) => journal.push(`validation dossier : ${e.message}`));
await api(`/francais/dossiers/FR3-DNB27-01/classes/${cp.classe_id}`, { methode: "PUT", jeton: jp }).catch((e) => journal.push(`ouverture dossier : ${e.message}`));
const prog = await api(`/admin/classes/${cp.classe_id}/chapitres`, { jeton: admin });
await api(`/admin/classes/${cp.classe_id}/chapitres`, { methode: "PUT", jeton: admin, corps: { chapitre_ids: prog.map((c) => c.id) } })
  .catch((e) => journal.push(`programme : ${e.message}`));
// Parent fictif rattaché à Lina.
let parent = null;
try {
  const eleves = await api(`/admin/classes/${cp.classe_id}/eleves`, { jeton: admin });
  const idLina = eleves.find((e) => e.prenom === "Lina").id;
  const f = await api("/admin/parents", { methode: "POST", jeton: admin, corps: { eleve_id: idLina, email: "parent-audit-231@exemple.test" } });
  const c = await api("/parents/connexion", { methode: "POST", corps: { email: "parent-audit-231@exemple.test", mot_de_passe: f.mot_de_passe_provisoire } });
  await api("/parents/mot-de-passe", { methode: "POST", jeton: c.jeton, corps: { actuel: f.mot_de_passe_provisoire, nouveau: MDP } });
  parent = "parent-audit-231@exemple.test";
} catch (e) { journal.push(`parent : ${e.message}`); }

// --- Captures ---------------------------------------------------------------------------------------------
const nav = await chromium.launch();
async function capture(page, nom) {
  await page.waitForTimeout(600);
  await page.screenshot({ path: `${SORTIE}/${nom}.png`, fullPage: true });
  journal.push(`capture ${nom}`);
}
async function contexte(taille) { return (await nav.newContext({ viewport: TAILLES[taille], deviceScaleFactor: 1 })).newPage(); }
async function connexionAdulte(page, chemin, email, mdp = MDP) {
  await page.goto(`${BASE}${chemin}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Mot de passe").fill(mdp);
  await page.getByRole("button", { name: /Se connecter/ }).click();
  await page.waitForTimeout(1500);
}
async function essai(nom, fn) { try { await fn(); } catch (e) { journal.push(`ÉCHEC ${nom} : ${e.message.split("\n")[0]}`); } }

for (const taille of Object.keys(TAILLES)) {
  // Élève pilote
  await essai(`élève ${taille}`, async () => {
    const page = await contexte(taille);
    await page.goto(`${BASE}/eleve`);
    await page.getByRole("heading", { name: "Connexion élève" }).waitFor({ timeout: 15000 });
    const lien = page.getByRole("button", { name: /me connecter avec mon prénom/ });
    if (await lien.isVisible()) await lien.click();
    await page.getByLabel("Prénom").fill("Lina");
    await page.getByLabel("Code classe").fill(cp.code);
    await page.getByLabel("Code personnel").fill(lina.code);
    await page.getByRole("button", { name: "Commencer" }).click();
    await page.getByRole("tab", { name: "Cours", exact: true }).waitFor({ timeout: 15000 });
    const onglets = taille === "ordinateur"
      ? ["S'entraîner", "Cours", "Mon cours", "Rédaction", "Fiches et PDF", "Mon historique", "Ma progression"]
      : ["S'entraîner", "Cours", "Ma progression"];
    for (const o of onglets) {
      const t = page.getByRole("tab", { name: o, exact: true });
      if (!(await t.count())) { journal.push(`onglet absent : ${o}`); continue; }
      await t.click();
      await capture(page, `eleve-${taille}-${o.toLowerCase().normalize("NFD").replace(/[^a-z]+/g, "-")}`);
    }
    if (taille === "ordinateur") {
      // Ouvrir un chapitre interactif et le dossier.
      await page.getByRole("tab", { name: "Cours", exact: true }).click();
      await page.waitForTimeout(800);
      const boutons = page.getByRole("button", { name: /Lire|Ouvrir|Accords|outils/i });
      journal.push(`boutons cours : ${await boutons.count()}`);
      await page.locator("section").filter({ has: page.getByRole("heading", { name: "Mes dossiers" }) }).getByRole("button").first().click().catch(() => {});
      await capture(page, "eleve-ordinateur-dossier-ouvert");
    }
  });
  // Parent
  if (parent && taille !== "tablette") await essai(`parent ${taille}`, async () => {
    const page = await contexte(taille);
    await connexionAdulte(page, "/parent", parent);
    await capture(page, `parent-${taille}`);
  });
}

// Adultes, ordinateur (+ mobile pour le professeur)
for (const taille of ["ordinateur", "mobile"]) {
  await essai(`prof ${taille}`, async () => {
    const page = await contexte(taille);
    await connexionAdulte(page, "/enseignant", p3.email);
    await capture(page, `professeur-${taille}-accueil`);
    await page.goto(`${BASE}/francais`); await page.waitForTimeout(1200);
    await capture(page, `professeur-${taille}-francais-dossiers`);
    if (taille === "ordinateur") for (const o of ["Mes classes", "Suivi des classes", "Cours", "Rédactions"]) {
      const t = page.getByRole("tab", { name: o, exact: true });
      if (await t.count()) { await t.click(); await capture(page, `professeur-ordinateur-francais-${o.toLowerCase().replace(/[^a-z]+/g, "-")}`); }
      else journal.push(`onglet prof absent : ${o}`);
    }
  });
}
await essai("validateur", async () => {
  const page = await contexte("ordinateur");
  await connexionAdulte(page, "/francais", val.email);
  const t = page.getByRole("tab", { name: "Validation" });
  if (await t.count()) { await t.click(); await capture(page, "validateur-ordinateur-francais-validation"); }
  await page.goto(`${BASE}/enseignant/validation`); await page.waitForTimeout(1500);
  await capture(page, "validateur-ordinateur-validation-questions");
});
for (const taille of ["ordinateur", "tablette", "mobile"]) {
  await essai(`administrateur ${taille}`, async () => {
    const page = await contexte(taille);
    await connexionAdulte(page, "/admin", "admin@pkp.test", "demo-pkp-2026");
    if (taille === "ordinateur") await capture(page, "administrateur-ordinateur-accueil");
    // Issue #231 : page « Boussole Français » de l'administration (avant : lien vers l'espace des dossiers).
    await page.goto(`${BASE}/admin/francais`);
    await page.getByRole("heading", { name: "À traiter" }).waitFor({ timeout: 15000 });
    await capture(page, `administrateur-${taille}-francais`);
  });
}
// Non-régression visuelle : Maths (Lina démo) et Anglais
await essai("maths", async () => {
  const page = await contexte("ordinateur");
  await page.goto(`${BASE}/eleve`);
  await page.getByRole("heading", { name: "Connexion élève" }).waitFor({ timeout: 15000 });
  const lien = page.getByRole("button", { name: /me connecter avec mon prénom/ });
  if (await lien.isVisible()) await lien.click();
  await page.getByLabel("Prénom").fill("Lina");
  await page.getByLabel("Code classe").fill("2NDE-A-DEMO");
  await page.getByLabel("Code personnel").fill("PKP222");
  await page.getByRole("button", { name: "Commencer" }).click();
  await page.waitForTimeout(2500);
  await capture(page, "reference-maths-eleve-ordinateur");
});
await nav.close();
writeFileSync(`${SORTIE}/journal.txt`, journal.join("\n") + "\n");
console.log(journal.join("\n"));
