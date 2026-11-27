// Issue #231 — Brouillon de rédaction gardé sur l'appareil, pour une durée réglable (Claude)
//
// Décision du propriétaire du 27/11/2026 (RGPD-2, docs/DECISIONS.md) : tant que la rédaction en ligne est fermée,
// l'élève peut préparer son texte dans l'atelier ; il reste **sur cet appareil seulement** (rien n'est envoyé au
// serveur), puis il est **effacé N jours après sa dernière modification**, N étant réglé sur le serveur
// (`PKP_REDACTION_BROUILLON_JOURS`, 10 par défaut, 0 le désactive). Les familles en sont informées une fois
// pour toutes par la charte d'utilisation (#183), pas à chaque action.
// Une clé par élève et par sujet : sur un poste partagé, un élève ne retrouve que ses propres brouillons.

export const PREFIXE = "pkp.redaction.brouillon.";
const JOUR_MS = 24 * 60 * 60 * 1000;

const cle = (eleveId, questionId) => `${PREFIXE}${eleveId}.${questionId}`;

function stockage() {
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

/** Un brouillon est périmé à sa date d'expiration, ou plus tôt si la durée réglée a été raccourcie depuis. */
function perime(b, jours, maintenant) {
  if (!b || !(b.expire_le > maintenant)) return true;
  return jours != null && !(b.enregistre_le + jours * JOUR_MS > maintenant);
}

/** Efface les brouillons périmés, de tous les élèves de l'appareil ; `jours` : durée réglée, si elle est connue. */
export function purgerBrouillons(jours = null, maintenant = Date.now()) {
  const s = stockage();
  if (!s) return;
  try {
    const cles = [];
    for (let i = 0; i < s.length; i++) {
      const k = s.key(i);
      if (k?.startsWith(PREFIXE)) cles.push(k);
    }
    for (const k of cles) {
      let b = null;
      try {
        b = JSON.parse(s.getItem(k));
      } catch {
        b = null;
      }
      if (perime(b, jours, maintenant)) s.removeItem(k);
    }
  } catch {
    // Stockage indisponible (navigation privée, quota) : rien à purger.
  }
}

/** Brouillon de l'élève pour ce sujet, ou null (absent, périmé ou illisible). */
export function lireBrouillon(eleveId, questionId, jours = null, maintenant = Date.now()) {
  const s = stockage();
  if (!s) return null;
  try {
    const b = JSON.parse(s.getItem(cle(eleveId, questionId)));
    if (perime(b, jours, maintenant) || typeof b.texte !== "string") {
      s.removeItem(cle(eleveId, questionId));
      return null;
    }
    return b;
  } catch {
    return null;
  }
}

/** Enregistre le brouillon pour `jours` jours à partir de maintenant ; un texte vide (ou une durée nulle) l'efface.
 * Renvoie l'entrée, ou null. */
export function ecrireBrouillon(eleveId, questionId, texte, jours, maintenant = Date.now()) {
  if (!texte.trim() || !(jours > 0)) {
    effacerBrouillon(eleveId, questionId);
    return null;
  }
  const s = stockage();
  if (!s) return null;
  const entree = { texte, enregistre_le: maintenant, expire_le: maintenant + jours * JOUR_MS };
  try {
    s.setItem(cle(eleveId, questionId), JSON.stringify(entree));
    return entree;
  } catch {
    return null;
  }
}

export function effacerBrouillon(eleveId, questionId) {
  try {
    stockage()?.removeItem(cle(eleveId, questionId));
  } catch {
    // Rien à faire.
  }
}
