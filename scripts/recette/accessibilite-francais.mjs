#!/usr/bin/env node
// Issue #231 — Audit d'accessibilité des écrans Français, sur pile locale jetable (Claude)
//
// Pour #154 : contrôle automatique axe-core (WCAG 2.1 A et AA) de chaque écran Français de l'élève, du professeur,
// du validateur, de l'administrateur et du parent, sur ordinateur (1 366 px), tablette (820 px) et mobile (390 px) ;
// zoom à 200 % (683 px) et recomposition à 320 px (aucun défilement horizontal) ; parcours au clavier seul : connexion → accueil → cours → exercice → réponse →
// correction → progression. Un contrôle automatique ne remplace ni un lecteur d'écran ni un essai avec des élèves.
//
// RÉSERVÉ à une pile locale jetable (comptes fictifs, validations et ouvertures dans une base temporaire) : refuse
// toute adresse non locale. Lancer après `bash scripts/recette/pile-locale.sh` ou sur une pile équivalente.
//
//   BASE_URL=http://127.0.0.1:5765 SORTIE=rapport-a11y node scripts/recette/accessibilite-francais.mjs
//   CAPTURES=1 : une capture de chaque écran audité, dans SORTIE/captures (passe finale #231).

import { createRequire } from "node:module";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const RACINE = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const AXE = readFileSync(join(RACINE, "web", "node_modules", "axe-core", "axe.min.js"), "utf8");

const BASE = (process.env.BASE_URL ?? "http://127.0.0.1:5765").replace(/\/$/, "");
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(BASE)) throw new Error("Pile locale jetable uniquement (AGENTS.md § 1).");
const SORTIE = process.env.SORTIE ?? "rapport-accessibilite-francais";
mkdirSync(SORTIE, { recursive: true });
const DOMAINE = "francais-college";
const MDP = "Accessibilite-231-Fictif!";
const TAILLES = { ordinateur: { width: 1366, height: 900 }, tablette: { width: 820, height: 1180 }, mobile: { width: 390, height: 844 } };
const CAPTURES = process.env.CAPTURES === "1";
if (CAPTURES) mkdirSync(join(SORTIE, "captures"), { recursive: true });

// --- API et données fictives ----------------------------------------------------------------------------------
async function api(chemin, { methode = "GET", corps, jeton } = {}) {
  const r = await fetch(`${BASE}/api${chemin}`, {
    method: methode,
    headers: { "Content-Type": "application/json", ...(jeton ? { Authorization: `Bearer ${jeton}` } : {}) },
    body: corps ? JSON.stringify(corps) : undefined,
  });
  const texte = await r.text();
  if (r.status >= 400) throw new Error(`${methode} ${chemin} → ${r.status} ${texte.slice(0, 200)}`);
  return texte ? JSON.parse(texte) : null;
}

async function professeur(admin, suffixe, habilitations) {
  const email = `a11y-231-${suffixe}@exemple.test`;
  const c = await api("/admin/enseignants", { methode: "POST", jeton: admin, corps: { nom: `Prof. ${suffixe} (fictif)`, email, role: "enseignant", habilitations } });
  const { jeton } = await api("/enseignants/connexion", { methode: "POST", corps: { email, mot_de_passe: c.mot_de_passe_provisoire } });
  await api("/enseignants/mot-de-passe", { methode: "POST", jeton, corps: { actuel: c.mot_de_passe_provisoire, nouveau: MDP } });
  return { id: c.enseignant.id, email };
}

async function preparer() {
  const { jeton: admin } = await api("/admin/connexion", { methode: "POST", corps: { email: "admin@pkp.test", mot_de_passe: "demo-pkp-2026" } });
  await api(`/admin/domaines/${DOMAINE}`, { methode: "POST", jeton: admin, corps: { actif: true, public: false } });
  const prof = await professeur(admin, "prof3e", [{ role: "professeur", domaine: DOMAINE, niveau: "3e" }]);
  const val = await professeur(admin, "validatrice", [
    { role: "professeur", domaine: DOMAINE, niveau: "4e" }, { role: "validateur", domaine: DOMAINE, niveau: "4e" },
  ]);
  const { jeton: jp } = await api("/enseignants/connexion", { methode: "POST", corps: { email: prof.email, mot_de_passe: MDP } });
  const cp = await api("/admin/classes-pilotes", { methode: "POST", jeton: admin, corps: { matiere: "francais", niveau: "3e", enseignant_id: prof.id, motif: "Audit d'accessibilité #231 (fictif)" } });
  const { crees } = await api(`/enseignants/classes/${cp.classe_id}/eleves`, { methode: "POST", jeton: jp, corps: { prenoms: ["Lina", "Yanis"] } });
  // Base jetable : l'administrateur valide les questions de 3e et le dossier, puis la professeure ouvre le dossier.
  for (let p = 1; ; p += 1) {
    const r = await api(`/admin/questions?domaine=${DOMAINE}&niveau=3e&statut=a-valider&page=1`, { jeton: admin });
    for (const q of r.elements) await api(`/admin/questions/${q.id}/validation`, { methode: "POST", jeton: admin, corps: { statut: "validee" } });
    if (!r.elements.length || p > 10) break;
  }
  await api("/francais/validation/FR3-DNB27-01/valider", { methode: "POST", jeton: admin }).catch(() => {});
  await api(`/francais/dossiers/FR3-DNB27-01/classes/${cp.classe_id}`, { methode: "PUT", jeton: jp });
  const eleves = await api(`/admin/classes/${cp.classe_id}/eleves`, { jeton: admin });
  const lina = eleves.find((e) => e.prenom === "Lina");
  const famille = await api("/admin/parents", { methode: "POST", jeton: admin, corps: { eleve_id: lina.id, email: "a11y-parent@exemple.test" } });
  const c = await api("/parents/connexion", { methode: "POST", corps: { email: "a11y-parent@exemple.test", mot_de_passe: famille.mot_de_passe_provisoire } });
  await api("/parents/mot-de-passe", { methode: "POST", jeton: c.jeton, corps: { actuel: famille.mot_de_passe_provisoire, nouveau: MDP } });
  return { classe: cp.code, code: (p) => crees.find((e) => e.prenom === p).code, prof, val, parent: "a11y-parent@exemple.test" };
}

// --- Navigateur -----------------------------------------------------------------------------------------------
async function connexionEleve(page, d, prenom) {
  await page.goto(`${BASE}/eleve`);
  await page.getByRole("heading", { name: "Connexion élève" }).waitFor({ timeout: 15000 });
  const lien = page.getByRole("button", { name: /me connecter avec mon prénom/ });
  if (await lien.isVisible()) await lien.click();
  await page.getByLabel("Prénom").fill(prenom);
  await page.getByLabel("Code classe").fill(d.classe);
  await page.getByLabel("Code personnel").fill(d.code(prenom));
  await page.getByRole("button", { name: "Commencer" }).click();
  await page.getByRole("heading", { name: "Mon espace Français" }).waitFor({ timeout: 15000 });
}

async function connexionAdulte(page, chemin, email, mdp = MDP) {
  await page.goto(`${BASE}${chemin}`);
  await page.getByLabel("Email").fill(email);
  await page.getByLabel("Mot de passe").fill(mdp);
  await page.getByRole("button", { name: /Se connecter/ }).click();
  await page.waitForTimeout(1500);
}

const rail = (page) => page.getByRole("navigation", { name: "Étapes du cours" });

/** Écrans audités : nom, rôle et chemin pour y arriver depuis une page connectée. */
const ECRANS = [
  ["eleve", "Accueil Français", async () => {}],
  ["eleve", "Mes cours", async (p) => { await p.getByRole("tab", { name: "Mes cours" }).click(); await p.waitForTimeout(500); }],
  ["eleve", "Dossier · Découvrir", async (p) => {
    await p.locator("article").filter({ hasText: "Lire et comprendre" }).first().getByRole("button", { name: /Commencer|Reprendre|Revoir/ }).click();
    await rail(p).waitFor();
  }],
  ["eleve", "Dossier · Appliquer (quiz)", async (p) => { await rail(p).getByRole("button", { name: /Appliquer/ }).click(); }],
  ["eleve", "Dossier · S'entraîner (texte et questions)", async (p) => { await rail(p).getByRole("button", { name: /S'entraîner/ }).click(); }],
  ["eleve", "Dossier · Consolider", async (p) => { await rail(p).getByRole("button", { name: /Consolider/ }).click(); }],
  ["eleve", "Cours · Comprendre", async (p) => {
    await p.getByRole("tab", { name: "Mes cours" }).click(); await p.waitForTimeout(500);
    await p.locator("article").filter({ hasText: "Grammaire" }).first().getByRole("button").last().click();
    await rail(p).waitFor();
    const comprendre = rail(p).getByRole("button", { name: /Comprendre/ });
    if (await comprendre.isEnabled()) await comprendre.click();
  }],
  ["eleve", "Cours · S'entraîner", async (p) => { await rail(p).getByRole("button", { name: /S'entraîner/ }).click(); }],
  ["eleve", "Exercice", async (p) => { await p.getByRole("button", { name: /Commencer les exercices|Continuer l'entraînement/ }).click(); await p.waitForTimeout(1200); }],
  ["eleve", "Correction", async (p) => {
    // QCM : un bouton par choix (le clic répond) ; sinon une réponse courte puis « Valider ».
    const choix = p.locator(".options button").first();
    if (await choix.count()) await choix.click();
    else {
      await p.getByRole("textbox").first().fill("x");
      await p.getByRole("button", { name: /^Valider/ }).click();
    }
    await p.waitForTimeout(1000);
  }],
  ["eleve", "Rédaction · atelier", async (p) => {
    await p.getByRole("tab", { name: "Mes cours" }).click(); await p.waitForTimeout(500);
    await p.locator("article").filter({ hasText: "Rédaction" }).filter({ hasText: "sujet" }).first().getByRole("button").last().click();
    await rail(p).waitFor();
    await rail(p).getByRole("button", { name: /Appliquer/ }).click();
    await p.locator(".consigne-redaction").first().waitFor();
  }],
  ["eleve", "Ma progression", async (p) => { await p.getByRole("tab", { name: "Ma progression" }).click(); await p.waitForTimeout(800); }],
  ["eleve", "Plus", async (p) => { await p.getByRole("tab", { name: "Plus" }).click(); }],
];

async function auditer(page, nom, taille) {
  await page.addScriptTag({ content: AXE });
  const r = await page.evaluate(async () => {
    // eslint-disable-next-line no-undef
    const res = await axe.run(document, { runOnly: { type: "tag", values: ["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"] } });
    return res.violations.map((v) => ({ id: v.id, impact: v.impact, aide: v.help, noeuds: v.nodes.length,
      exemples: v.nodes.slice(0, 3).map((n) => n.target.join(" ")) }));
  });
  const largeur = await page.evaluate(() => document.documentElement.scrollWidth);
  if (CAPTURES) {
    const fichier = `${taille}-${nom}`.normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/[^A-Za-z0-9]+/g, "-").toLowerCase();
    await page.screenshot({ path: join(SORTIE, "captures", `${fichier}.png`), fullPage: true }).catch(() => {});
  }
  return { ecran: nom, taille, violations: r, debordement: largeur > (TAILLES[taille]?.width ?? 0) };
}

async function recomposition(navigateur, d, largeurEcran = 320) {
  // 320 px de large ≈ 1 280 px affichés à 400 % (WCAG 1.4.10) ; 683 px ≈ 1 366 px à 200 % (WCAG 1.4.4) :
  // aucun défilement horizontal de la page.
  const page = await (await navigateur.newContext({ viewport: { width: largeurEcran, height: 700 } })).newPage();
  await connexionEleve(page, d, "Yanis");
  const resultats = [];
  for (const [, nom, aller] of ECRANS.slice(0, 8)) {
    try {
      await aller(page);
      await page.waitForTimeout(300);
      const l = await page.evaluate(() => document.documentElement.scrollWidth);
      resultats.push({ ecran: nom, largeur: l, ok: l <= largeurEcran });
    } catch (e) {
      resultats.push({ ecran: nom, erreur: e.message.split("\n")[0], ok: false });
    }
  }
  return resultats;
}

/** Appuie sur Tab jusqu'à ce que l'élément actif vérifie `critere` (l'élément déjà actif compte : un écran peut
 * placer le focus lui-même, comme le champ de réponse d'un exercice) ; décrit l'élément atteint. */
async function tabulerJusqua(page, critere, max = 80) {
  for (let i = 0; i < max; i += 1) {
    if (i > 0) await page.keyboard.press("Tab");
    const actif = await page.evaluate(() => {
      const e = document.activeElement;
      const style = e ? getComputedStyle(e) : null;
      return e ? { texte: (e.innerText || e.value || e.getAttribute("aria-label") || "").trim().slice(0, 80), role: e.getAttribute("role") ?? e.tagName.toLowerCase(),
        focusVisible: style.outlineStyle !== "none" && style.outlineWidth !== "0px" || style.boxShadow !== "none" } : null;
    });
    if (actif && critere(actif)) return { ...actif, appuis: i };
  }
  throw new Error("élément jamais atteint au clavier");
}

async function parcoursClavier(navigateur, d) {
  const page = await (await navigateur.newContext({ viewport: TAILLES.ordinateur })).newPage();
  const etapes = [];
  const etape = async (nom, fn) => {
    try { etapes.push({ nom, ok: true, detail: await fn() }); } catch (e) {
      const capture = `clavier-${etapes.length + 1}.png`;
      await page.screenshot({ path: join(SORTIE, capture), fullPage: true }).catch(() => {});
      etapes.push({ nom, ok: false, detail: `${e.message.split("\n")[0]} (capture ${capture})` });
    }
  };
  await page.goto(`${BASE}/eleve`);
  await page.getByRole("heading", { name: "Connexion élève" }).waitFor({ timeout: 15000 });
  await etape("Connexion au clavier", async () => {
    const lien = page.getByRole("button", { name: /me connecter avec mon prénom/ });
    if (await lien.isVisible()) { await lien.focus(); await page.keyboard.press("Enter"); }
    await page.getByLabel("Prénom").focus();
    await page.keyboard.type("Lina");
    await page.keyboard.press("Tab"); await page.keyboard.type(d.classe);
    await page.keyboard.press("Tab"); await page.keyboard.type(d.code("Lina"));
    await page.keyboard.press("Enter");
    await page.getByRole("heading", { name: "Mon espace Français" }).waitFor({ timeout: 15000 });
    return "prénom, code classe, code personnel, Entrée";
  });
  await etape("Accueil → reprendre le cours (Tab, Entrée)", async () => {
    const b = await tabulerJusqua(page, (a) => /^(Commencer|Continuer)/.test(a.texte));
    await page.keyboard.press("Enter");
    await rail(page).waitFor({ timeout: 10000 });
    return `${b.appuis} appuis ; focus visible : ${b.focusVisible ? "oui" : "NON"}`;
  });
  await etape("Rail des étapes au clavier", async () => {
    const b = await tabulerJusqua(page, (a) => /Comprendre/.test(a.texte));
    await page.keyboard.press("Enter");
    await page.getByRole("heading", { name: "Comprendre", level: 2 }).waitFor();
    return `${b.appuis} appuis ; focus visible : ${b.focusVisible ? "oui" : "NON"}`;
  });
  await etape("Aller à l'entraînement", async () => {
    // Après un changement d'étape, le focus est sur le titre de l'étape : on avance par « Étape suivante → »
    // (après le contenu) ou par le rail, jamais par l'onglet « S'entraîner » du haut de page.
    const s = await tabulerJusqua(page, (a) => /S'entraîner/.test(a.texte) && (/→/.test(a.texte) || /Exercices adaptés/.test(a.texte)));
    await page.keyboard.press("Enter");
    const b = await tabulerJusqua(page, (a) => /Commencer les exercices|Continuer l'entraînement/.test(a.texte));
    await page.keyboard.press("Enter");
    await page.waitForTimeout(1500);
    return `${s.appuis + b.appuis} appuis`;
  });
  await etape("Répondre au clavier", async () => {
    // Réponse courte : un champ (le focus y est déjà) puis « Valider » ; QCM : un bouton par choix (A, B, C…).
    const champ = await tabulerJusqua(page, (a) => ["input", "textarea"].includes(a.role) || /^[A-F]\s/.test(a.texte));
    let detail;
    if (["input", "textarea"].includes(champ.role)) {
      await page.keyboard.type("x");
      await tabulerJusqua(page, (a) => /^Valider/.test(a.texte));
      detail = champ.appuis === 0 ? "focus déjà dans le champ de réponse, puis « Valider »" : `${champ.appuis} appuis jusqu'au champ`;
    } else {
      detail = `QCM : ${champ.appuis} appuis jusqu'au choix « ${champ.texte.replace(/\s+/g, " ").slice(0, 20)} » ; focus visible : ${champ.focusVisible ? "oui" : "NON"}`;
    }
    await page.keyboard.press("Enter");
    await page.waitForTimeout(1200);
    const focus = await page.evaluate(() => (document.activeElement?.innerText || document.activeElement?.tagName || "").slice(0, 60));
    const correction = await page.getByText(/Bonne réponse|Pas tout à fait|Réponse attendue|correction|Bravo|Pas encore/i).count();
    if (!correction) throw new Error("aucune correction affichée après la réponse");
    return `${detail} ; correction affichée ; focus ensuite sur « ${focus.trim()} »`;
  });
  await etape("Progression au clavier", async () => {
    const b = await tabulerJusqua(page, (a) => a.texte === "Ma progression");
    await page.keyboard.press("Enter");
    await page.waitForTimeout(800);
    return `${b.appuis} appuis`;
  });
  return etapes;
}

// --- Exécution ------------------------------------------------------------------------------------------------
const d = await preparer();
const navigateur = await chromium.launch();
const audits = [];
try {
  for (const taille of Object.keys(TAILLES)) {
    const page = await (await navigateur.newContext({ viewport: TAILLES[taille], reducedMotion: "reduce" })).newPage();
    await connexionEleve(page, d, taille === "ordinateur" ? "Lina" : "Yanis");
    for (const [role, nom, aller] of ECRANS) {
      try { await aller(page); await page.waitForTimeout(400); audits.push({ role, ...(await auditer(page, nom, taille)) }); }
      catch (e) { audits.push({ role, ecran: nom, taille, erreur: e.message.split("\n")[0] }); }
    }
    const adultes = [
      ["professeur", "Tableau de bord", "/enseignant", d.prof.email, async () => {}],
      ["professeur", "Mes classes", "/enseignant", d.prof.email, async (p) => { await p.goto(`${BASE}/enseignant/classes`); await p.waitForTimeout(1000); }],
      ["professeur", "Rédactions", "/enseignant", d.prof.email, async (p) => { await p.goto(`${BASE}/enseignant/redactions`); await p.waitForTimeout(1200); }],
      ["validateur", "File de validation", "/enseignant", d.val.email, async (p) => {
        await p.goto(`${BASE}/enseignant/validation`);
        await p.getByRole("heading", { name: "File de validation" }).waitFor({ timeout: 15000 });
        await p.waitForTimeout(600);
      }],
      ["administrateur", "Page Français", "/admin", "admin@pkp.test", async (p) => { await p.goto(`${BASE}/admin/francais`); await p.getByRole("heading", { name: "À traiter" }).waitFor(); }],
      ["parent", "Bilan Français", "/parent", d.parent, async () => {}],
    ];
    for (const [role, nom, chemin, email, aller] of adultes) {
      const p = await (await navigateur.newContext({ viewport: TAILLES[taille], reducedMotion: "reduce" })).newPage();
      try {
        await connexionAdulte(p, chemin, email, email === "admin@pkp.test" ? "demo-pkp-2026" : MDP);
        await aller(p); await p.waitForTimeout(500);
        audits.push({ role, ...(await auditer(p, nom, taille)) });
      } catch (e) { audits.push({ role, ecran: nom, taille, erreur: e.message.split("\n")[0] }); }
    }
  }
  var reflow = await recomposition(navigateur, d);
  var zoom = await recomposition(navigateur, d, 683);
  var clavier = await parcoursClavier(navigateur, d);
} finally {
  await navigateur.close();
}

const total = audits.reduce((n, a) => n + (a.violations?.length ?? 0), 0);
writeFileSync(join(SORTIE, "rapport.json"), JSON.stringify({ base: BASE, audits, reflow, zoom, clavier }, null, 2));
const ligne = (a) => `| ${a.role} | ${a.ecran} | ${a.taille} | ${a.erreur ? `erreur : ${a.erreur}` : a.violations.length
  ? a.violations.map((v) => `${v.id} (${v.impact}, ${v.noeuds})`).join(" ; ") : "aucune"} | ${a.debordement ? "OUI" : "non"} |`;
writeFileSync(join(SORTIE, "rapport.md"), [
  `# Accessibilité des écrans Français — ${total ? `${total} violation(s) axe` : "aucune violation axe"}`, "",
  "Contrôle automatique axe-core 4.14.0 (WCAG 2.1 A et AA), pile locale jetable, comptes fictifs.", "",
  "| Rôle | Écran | Taille | Violations axe | Débordement horizontal |", "|---|---|---|---|---|",
  ...audits.map(ligne), "", "## Recomposition à 320 px", "", "| Écran | Largeur de page | Résultat |", "|---|---|---|",
  ...reflow.map((r) => `| ${r.ecran} | ${r.largeur ?? "—"} | ${r.ok ? "OK" : `KO ${r.erreur ?? ""}`} |`), "",
  "## Zoom à 200 % (683 px)", "", "| Écran | Largeur de page | Résultat |", "|---|---|---|",
  ...zoom.map((r) => `| ${r.ecran} | ${r.largeur ?? "—"} | ${r.ok ? "OK" : `KO ${r.erreur ?? ""}`} |`), "",
  "## Parcours au clavier seul", "", "| Étape | Résultat | Détail |", "|---|---|---|",
  ...clavier.map((e) => `| ${e.nom} | ${e.ok ? "OK" : "KO"} | ${e.detail} |`), "",
].join("\n"));
console.log(`Audit terminé : ${total} violation(s) axe ; rapport dans ${SORTIE}/rapport.md`);
