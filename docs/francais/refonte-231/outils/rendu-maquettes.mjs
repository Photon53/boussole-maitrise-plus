// Issue #231 — Rendu des maquettes en images, ordinateur et mobile (Claude)
// Aucun réseau hors polices : ouvre prototype.html en fichier local.
//   node docs/francais/refonte-231/outils/rendu-maquettes.mjs "$PWD/docs/francais/refonte-231/prototype.html" docs/francais/refonte-231/maquettes
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
const [,, fichier, sortie, filtre] = process.argv;
const ECRANS = ["accueil","catalogue","lecon","grammaire","conjugaison","comprehension","correction","bilan","redaction","professeur","validateur","administrateur","parent"];
const MOBILE = new Set(["accueil","catalogue","lecon","grammaire","conjugaison","comprehension","correction","bilan","redaction","professeur","parent"]);
const nav = await chromium.launch();
const page = await nav.newPage({ viewport: { width: 1640, height: 1000 }, deviceScaleFactor: 1 });
for (const [i, id] of ECRANS.entries()) {
  if (filtre && !filtre.split(",").includes(id)) continue;
  const n = String(i + 1).padStart(2, "0");
  for (const t of ["ordinateur", "mobile"]) {
    if (t === "mobile" && !MOBILE.has(id)) continue;
    await page.goto(`file://${fichier}?taille=${t === "mobile" ? "mobile" : "ordi"}#${id}`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(400);
    await page.locator("#appareil").screenshot({ path: `${sortie}/${n}-${id}-${t}.png` });
  }
}
await nav.close();
