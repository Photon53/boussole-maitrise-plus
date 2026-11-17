<!-- Issue #162 — Diagnostic des acquis antérieurs, note de cadrage (Claude) -->
# Diagnostic des acquis antérieurs

Suivi : issue #162. Statut : **banque transcrite (lot 1), à relire par un professeur** ; le moteur ne lit pas encore
ces fichiers (lot 2). Ils sont rangés dans `docs/diagnostic/banque/` et rejoindront `contenu/` au lot 2.

## 1. Objectif

Repérer, en début d'utilisation de Boussole, les acquis **des années précédentes** dont l'élève a besoin, sans
l'interroger sur des chapitres qu'il n'a pas encore étudiés. Un élève de 3e commence par les acquis de 4e ; en cas
de difficulté, on redescend vers la 5e puis la 6e.

| Classe de l'élève | Premier niveau interrogé | Retour possible |
|---|---|---|
| 6e | CM2 | CM1, puis cycle 2 |
| 5e | 6e | CM2 |
| 4e | 5e | 6e, puis CM2 |
| 3e | 4e | 5e, puis 6e |
| 2nde | 3e | 4e, puis plus ancien |
| 1re | 2nde | 3e, puis plus ancien |
| Terminale | socle + module de l'enseignement suivi en 1re | 2nde, puis plus ancien |

Le bilan se fait **par compétence**, jamais sous la forme « niveau de 5e ». Les observations du diagnostic restent
séparées du taux de maîtrise : une réussite isolée ne déclare pas une compétence maîtrisée.

## 2. Décisions du propriétaire (16/11/2026)

1. **Nature de chapitre « diagnostic »** (option B), distincte de `mise-a-niveau`, exemptée de la règle « cours +
   difficultés 1 à 5 » ; passation dédiée et bilan stocké à part du taux de maîtrise.
2. **Nouveau type `choix_multiples`** (plusieurs bonnes réponses), le type `qcm` étant conservé.
3. **Questions rédigées** (`redaction`) : corrigées dans l'interface par le professeur, ou sur papier après export
   PDF. L'élève répond par du texte ou **dépose une image ou un PDF**.

## 3. Quel programme interroger

Ce qui compte est le programme **que l'élève a suivi l'année précédente**, pas celui de l'année en cours. Pour
2026-2027 (`programme_prerequis` de chaque fichier) :

| Entrée en | Année précédente suivie en 2025-2026 sous | Code |
|---|---|---|
| 6e | programme du cycle 3 de 2025, **si appliqué en CM2 dès 2025-2026 : à vérifier** | `cm2-2020` provisoire |
| 5e | programme du cycle 3 de 2025 (6e, en vigueur le 01/09/2025) | `6e-2025` |
| 4e | repères de 2020 (le programme de 5e de 2026 commence en 2026-2027) | `5e-2020` |
| 3e | repères de 2020 | `4e-2020` |
| 2nde | repères de 2020 | `3e-2020` |
| 1re | programme de 2nde de 2019 | `2nde-2019` |
| Terminale | programmes de 1re de 2019 | `1re-specialite-2019`, `1re-technologique-2019` |

En 2027-2028, l'entrée en 4e, 1re et Terminale passera aux programmes de 2026 : il faudra une version de la
banque par programme, choisie selon l'année scolaire de passation. Les référentiels `5e-2020`, `2nde-2019` et
`1re-*-2019` ne sont pas dans `referentiels/` : les codes sont posés, les attendus ne sont pas encore rattachés.

## 4. Format des fichiers

Identique à `contenu/` (`docs/CONTENU.md`), avec :

```yaml
chapitre:
  code: 3E-DIAG-4E
  niveau: 3e
  nature: diagnostic                 # remplace `parcours` et `ordre`
  programme_prerequis: 4e-2020       # programme suivi l'année précédente
  publics: [tronc-commun]            # parcours des classes concernées
competences:
- code: 3E-DIAG-TRIANGLE
  prerequis: [4E-PYTHAGORE, 4E-THALES, 4E-COSINUS]   # chapitres où reprendre en cas de difficulté
  questions:
  - type: choix_multiples            # solution : lettres en ordre alphabétique, « AC »
  - type: redaction                  # solution : réponse attendue, pour le professeur
```

Chaque question rappelle en commentaire son identifiant de la banque initiale (`# 3E-08`).

## 5. Contenu de la banque

| Fichier | Publics | Questions | dont rédaction | dont choix multiples |
|---|---|---:|---:|---:|
| `6e-acquis-cm2.yaml` | 6e | 18 | 3 | 0 |
| `5e-acquis-6e.yaml` | 5e | 17 | 3 | 1 |
| `4e-acquis-5e.yaml` | 4e | 20 | 1 | 1 |
| `3e-acquis-4e.yaml` | 3e | 20 | 2 | 0 |
| `2nde-acquis-3e.yaml` | 2nde GT et pro | 20 | 1 | 0 |
| `1re-acquis-2nde.yaml` | 1re (toutes voies) | 20 | 1 | 0 |
| `tle-socle.yaml` | Terminale (tous parcours) | 6 | 0 | 0 |
| `tle-module-specialite.yaml` | spécialité, expertes, complémentaires | 6 | 0 | 0 |
| `tle-module-technologique.yaml` | voie technologique | 6 | 0 | 0 |
| **Total** | | **133** | **11** | **2** |

Les questions automatisables sont vérifiées par `app.contenu` (solution lisible, corrigé cohérent, prérequis
existants) ; les deux types nouveaux par un contrôle de structure en attendant le lot 2.

## 6. Corrections apportées à la banque fusionnée (152 questions)

Vérifiées contre `referentiels/` et les calculs refaits.

**Hors du programme de l'année précédente** :

| ID | Problème | Traitement |
|---|---|---|
| 3E-14 | Réciproque de Thalès : programme de 3e (`3E-2020-GEOM-01`) | Déplacée en entrée en 2nde |
| 2N-13 | Systèmes d'équations : programme de 2nde | Retirée |
| 2N-14 | Inéquations : programme de 2nde | Remplacée par « 3 vérifie-t-il l'inégalité ? » |
| 4E-13, 4E-14, 4E-16 | Produit de relatifs, puissances, produit de fractions : 4e | Retirées (reprises à l'entrée en 3e) |
| 4E-R2 | $2/3 + 1/4$ : dénominateurs non multiples, 4e | Retirée |
| 4E-R6 | Médiane : 4e | Moyenne seulement |
| 5E-15 | Parallélogramme : 5e | Retirée (couvert par 4E-20) |
| 6E-12 | Produit de deux décimaux : 6e | Déplacée en entrée en 5e ; en 6e, « 0,4 × 10 » |

**Fausses, ambiguës ou mal posées** :

| ID | Problème | Traitement |
|---|---|---|
| 4E-15 | Deux bonnes réponses ($3/5 = 0{,}6$) | $3/5$ remplacé par $5/8$ |
| 1R-19 | Trois valeurs ne prouvent pas un zéro unique | Énoncé reformulé |
| 3E-20 | « Combien de graduations… » mal posée | Retirée |
| 6E-16, 5E-13 | Pas de lecture réelle de droite graduée | Abscisse d'un point à lire |

**Doublons** : 2N-08 / 3E-13 et 2N-09 / 3E-15 (valeurs changées en 2nde, tangente au lieu de cosinus) ; 1R-14 /
MC-02 et 1R-20 / TE-06 (valeurs changées).

**Terminale** : les élèves de maths complémentaires ont suivi la spécialité en 1re ; ils reçoivent le module
spécialité. Le module MC-01 à MC-06 ne correspond à aucun parcours de 1re : il n'est pas transcrit ; il pourrait
servir aux élèves de 1re sans spécialité (à décider).

## 7. Limites connues

- Pas de figure : les questions « graphique » (5E-16, 2N-18…) donnent les données en texte. Les figures demandent
  une prise en charge des images dans l'énoncé.
- Une seule variante par question : les trois variantes (gabarits `gabarit:` à valeurs tirées) viendront ensuite.
- Difficultés à recalibrer après le pilote ; **aucune question n'est validée pédagogiquement**.
- Dépôt d'images ou de PDF par l'élève (lot 4) : durée de conservation et accès à décider au titre du RGPD.
