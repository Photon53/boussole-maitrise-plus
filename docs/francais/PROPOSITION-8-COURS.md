# Huit cours pilotes et quatre sujets de rédaction — proposition à soumettre au professeur

Issue #175 / #177 — Claude — 26/11/2026.

**Statut au 27/11/2026 : thèmes retenus pour le pilote, contenus en production, AUCUNE validation pédagogique.**
Le propriétaire a donné le GO de production le 27/11 (`V2-D12 — production des contenus`,
[`../DECISIONS.md`](../DECISIONS.md) ; description de #177). Il s'appuie sur une revue pédagogique assistée par
ChatGPT, qui ne remplace pas la validation par un professeur. Chaque question est importée « à valider ». Elle n'est
servie qu'après validation par une personne différente de l'auteur (V2-D15), et seulement aux classes pilotes
(SEC-D6). Le professeur peut encore valider, modifier ou remplacer chaque cours et chaque sujet.

## 0. Mise à jour du 27/11 : prescriptions et références officielles

### Programmes applicables en 2026-2027

| Niveau | Programme de français applicable | Remarque pour le pilote |
|---|---|---|
| 6e | Cycle 3, arrêté du 10 avril 2025, BO n° 16 du 17 avril 2025 | |
| 5e | **Nouveau** cycle 4, arrêté du 18 février 2026, BO n° 10 du 5 mars 2026 | Les graphies ancienne et rectifiée (1990) sont acceptées à égalité : les réponses courtes acceptent les deux |
| 4e | Cycle 4, BO n° 31 du 30 juillet 2020 | Le nouveau programme ne s'applique en 4e qu'à la rentrée 2027 |
| 3e | Cycle 4, BO n° 31 du 30 juillet 2020 ; brevet 2027 | Le nouveau programme ne s'applique en 3e qu'à la rentrée 2028 |

Sources consultées le 27/11/2026 : page Éduscol « Enseigner au cycle 4 » et « Enseigner au cycle 3 » ; annexe 1 du
programme du cycle 3 (2025) et annexe 1 du programme du cycle 4 (2026), sur education.gouv.fr. Les références
précises et les écarts sont suivis dans #55.

### Écarts relevés, à faire trancher par le professeur

| Cours | Constat dans le programme applicable | Conséquence proposée |
|---|---|---|
| C1 (6e) | La section « Analyser le groupe nominal » demande de distinguer l'épithète et le complément du nom ; la distinction nature / fonction relève de la terminologie et du CM2 | Introduction du complément du nom dans le groupe nominal, conforme |
| C2 (6e) | Le présent n'est pas nommé dans les objectifs de 6e (traité en CM1 et CM2). La 6e consolide les marques des temps étudiés et vise les temps composés, l'impératif présent et le conditionnel présent | C2 est un cours de **consolidation**. Le professeur peut préférer élargir aux temps composés |
| C3 (5e) | Sujet, COD, COI, attribut et compléments circonstanciels sont nommés ; le complément du nom ne l'est pas : seul le « groupe nominal étendu » apparaît | Complément du nom traité comme constituant du groupe nominal étendu, pour le distinguer du COI |
| C4 (5e) | La morphologie de l'imparfait et du passé simple est au programme | Conforme |
| C5, C6 (4e) | Programme de 2020 : phrase complexe, temps et modes, sans répartition annuelle aussi fine que celle du nouveau programme | Attendus annuels à confirmer par le professeur. Le conditionnel est présenté comme un temps de l'indicatif, terminologie du nouveau programme de 3e |
| C7, C8 (3e) | Programme de 2020 et épreuve du brevet 2027 | Les longueurs de rédaction sont **indicatives** : aucune n'est présentée comme une exigence officielle sans source |

### Exercices associés aux dossiers de 3e (option M1)

| Cours | Chapitre YAML associé | Rubrique | Contenu |
|---|---|---|---|
| C7 | Accords et réécriture : exercices | Grammaire | Chaînes d'accord (sujet-verbe, groupe nominal, participe passé) et réécriture avec changements de temps, de personne, de genre et de nombre, ce qui intègre les révisions de conjugaison |
| C8 | Outils de la langue pour comprendre un texte : exercices | Grammaire | Compétences transférables d'un texte à l'autre : reprises nominales et pronominales, connecteurs logiques, valeur des temps, modalisation. **Plan à faire valider** : ces notions relèvent de l'étude de la langue, et non de la compréhension d'un texte donné |

Les 9 questions de chaque chapitre associé constituent le quota du cours. Les quiz des dossiers gardent un score
distinct. Les questions rédigées des dossiers restent au retour humain.

### Méthode en sept étapes, portée par les champs existants

| Étape | Champ du chapitre YAML | Dans un dossier |
|---|---|---|
| 1. Découvrir | `objectifs`, `prerequis`, durée indiquée dans `cours` | Fiche « objectifs » du dossier |
| 2. Comprendre | `cours`, `resume`, `methodes` avec un exemple résolu | Leçon et textes |
| 3. Appliquer | Questions de difficulté 1 et 2 | Quiz |
| 4. S'entraîner | Questions de difficulté 3, correction expliquée | Entraînement |
| 5. Approfondir | Questions de difficulté 4 et 5, `erreurs_frequentes` | Transfert |
| 6. Réinvestir | Rubrique « Réinvestir » du `cours`, renvoi au sujet de rédaction du niveau | Questions rédigées, réécriture |
| 7. Consolider | `resume`, reprise des erreurs ; progression et révisions par le moteur | « Je sais » |

## 1. Vue d'ensemble

| Niveau | Cours | Rubrique | Format (A1) | Existant |
|---|---|---|---|---|
| 6e | C1 — La nature des mots | Grammaire | Chapitre YAML | — |
| 6e | C2 — Le présent de l'indicatif | Conjugaison | Chapitre YAML | — |
| 5e | C3 — Les fonctions : sujet, COD, COI et complément du nom | Grammaire | Chapitre YAML | — |
| 5e | C4 — L'imparfait et le passé simple | Conjugaison | Chapitre YAML | — |
| 4e | C5 — La phrase complexe et les propositions subordonnées | Grammaire | Chapitre YAML | — |
| 4e | C6 — Les temps et les modes verbaux | Conjugaison | Chapitre YAML | — |
| 3e | C7 — Accords et réécriture (brevet) | Brevet | Dossier | `docs/francais/3e-brevet-2027/02-*` : 11 questions rédigées, **non importé** |
| 3e | C8 — Comprendre un texte (brevet) | Compréhension | Dossier | `FR3-DNB27-01` importé : 11 questions rédigées, quiz de 6 QCM, 4 « Je sais » |
| 6e à 3e | R1 à R4 — Sujets de rédaction | Rédaction | Chapitre YAML, rubrique `redaction` (circuit #187) | — |

**Exigences minimales (A2)** : 9 questions corrigées automatiquement par cours (3 faciles, 3 moyennes,
3 difficiles), soit 72 ; 4 sujets de rédaction ; PDF élève sans corrigé et PDF professeur ; validation avant
publication.

### Correspondance avec l'échelle de difficulté existante

L'échelle de `docs/CONTENU.md` va de 1 à 5 et le moteur demande au moins une question par niveau pour chaque
compétence. Proposition pour chaque cours de 9 questions :

| Groupe de #175 | Difficultés | Nombre |
|---|---|---|
| Faciles | 1, 1, 2 | 3 |
| Moyennes | 3, 3, 3 | 3 |
| Difficiles | 4, 4, 5 | 3 |

### Formats autocorrigés disponibles

En chapitre de français, deux types sont corrigés par la plateforme : **`qcm`** (une lettre) et **`texte`**
(réponse courte : un mot, une forme verbale, accents conservés, casse et espaces neutralisés). `choix_multiples` est
réservé au diagnostic. Dans un dossier, le quiz est un QCM.

## 2. Fiches des cours (cadrage à valider)

Pour chaque cours : objectifs, prérequis, plan des 9 questions, erreurs fréquentes visées, point à vérifier.
Les exemples sont des illustrations de forme, entièrement originaux.

### C1 — 6e — La nature des mots (grammaire)

- **Objectifs** : identifier la classe grammaticale d'un mot dans une phrase (nom, déterminant, adjectif, pronom,
  verbe, adverbe, préposition, conjonction de coordination) ; distinguer classe et fonction.
- **Prérequis** : repérer le verbe et le sujet (cycle 2).
- **Plan** : 1-1-2 : QCM sur un mot souligné dans une phrase simple ; 3-3-3 : `texte` (« Quelle est la classe du
  mot… ? ») avec un mot ambigu selon le contexte (« le » déterminant ou pronom) ; 4-4-5 : QCM sur des cas
  piégeux (« bien » adverbe ou nom, mot invariable), puis une phrase où identifier toutes les classes.
- **Erreurs fréquentes** : confondre déterminant et pronom ; prendre un adjectif employé comme nom pour un adjectif.
- **À vérifier (#55)** : liste des classes attendues en 6e.
- *Exemple (difficulté 1, QCM)* : « Dans « La chatte grise dort », quelle est la classe de « grise » ?
  A) nom  B) adjectif  C) verbe ».

### C2 — 6e — Le présent de l'indicatif (conjugaison)

- **Objectifs** : conjuguer au présent les verbes du 1er et du 2e groupe et les verbes fréquents du 3e groupe
  (être, avoir, aller, faire, dire, venir, pouvoir, vouloir, prendre) ; reconnaître le groupe d'un verbe.
- **Prérequis** : identifier le verbe et son infinitif.
- **Plan** : 1-1-2 : `texte`, conjugaison d'un verbe du 1er groupe à une personne donnée ; 3-3-3 : 2e groupe et
  verbes en -cer et -ger ; 4-4-5 : verbes irréguliers et accord avec un sujet éloigné ou inversé.
- **Erreurs fréquentes** : « il finit » ou « il finis » ; « nous mangons » ; accord avec le mauvais sujet.
- **Lien rédaction** : prépare R1.

### C3 — 5e — Les fonctions : sujet, COD, COI et complément du nom (grammaire)

- **Objectifs** : identifier sujet, COD et COI d'un verbe ; identifier le complément du nom dans un groupe nominal ;
  distinguer COI et complément du nom introduits par « de ».
- **Prérequis** : C1 (classes des mots).
- **Plan** : 1-1-2 : QCM sur la fonction d'un groupe souligné ; 3-3-3 : `texte` (« Recopie le COD ») ;
  4-4-5 : distinguer « Il parle de son voyage » (COI) et « le récit de son voyage » (complément du nom), sujet
  inversé.
- **Erreurs fréquentes** : prendre le premier groupe nominal pour le sujet ; confondre COI et complément du nom.
- **À vérifier (#55)** : le **positionnement du complément du nom** (6e ou 5e) et le volume de ce cours, qui réunit
  quatre fonctions ; le professeur peut préférer deux cours.

### C4 — 5e — L'imparfait et le passé simple (conjugaison)

- **Objectifs** : conjuguer à l'imparfait et au passé simple (3e personne du singulier et du pluriel au minimum) ;
  choisir le temps selon sa valeur (arrière-plan ou action de premier plan).
- **Prérequis** : C2.
- **Plan** : 1-1-2 : `texte`, imparfait d'un verbe du 1er groupe ; 3-3-3 : passé simple des 1er et 2e groupes ;
  4-4-5 : QCM sur le choix du temps dans un court récit, passé simple d'un verbe irrégulier.
- **Erreurs fréquentes** : « il chanta » et « il chantait » confondus ; terminaisons « -a » et « -ât ».
- **Lien rédaction** : prépare R2.

### C5 — 4e — La phrase complexe et les propositions subordonnées (grammaire)

- **Objectifs** : compter les propositions d'une phrase ; distinguer juxtaposition, coordination et
  subordination ; reconnaître une subordonnée relative et une subordonnée conjonctive.
- **Prérequis** : C1, C3.
- **Plan** : 1-1-2 : QCM « Combien de propositions ? » ; 3-3-3 : `texte` (« Recopie le mot subordonnant ») ;
  4-4-5 : distinguer « que » pronom relatif et « que » conjonction ; nature d'une subordonnée.
- **Erreurs fréquentes** : confondre les deux « que » ; oublier un verbe conjugué.

### C6 — 4e — Les temps et les modes verbaux (conjugaison)

- **Objectifs** : identifier le mode (indicatif, subjonctif, impératif, conditionnel) et le temps d'une forme
  verbale ; conjuguer au subjonctif présent et au conditionnel présent les verbes fréquents.
- **Prérequis** : C2, C4.
- **Plan** : 1-1-2 : QCM sur le mode d'une forme ; 3-3-3 : `texte`, subjonctif présent après « il faut que » ;
  4-4-5 : distinguer futur et conditionnel (« je serai » et « je serais »), choix du mode dans une phrase.
- **Erreurs fréquentes** : « -rai » et « -rais » ; « que je sois » et « que je soit ».
- **À vérifier (#55)** : la conjugaison n'a pas de cours propre en 3e : à confirmer ou à compléter.

### C7 — 3e — Accords et réécriture, brevet (dossier)

- **Existant** : dossier documentaire 02 (leçon en cinq étapes, 8 questions d'entraînement, 3 de transfert,
  11 corrigés, grille professeur), à importer au format `boussole-francais-dossier/1`.
- **À ajouter** : un **quiz de 9 QCM** (accords du participe passé, de l'adjectif, du verbe avec un sujet éloigné),
  3 faciles, 3 moyens, 3 difficiles, et des phrases « Je sais ».
- **Point à trancher** : le quiz d'un dossier est corrigé par la plateforme mais **n'alimente pas la maîtrise**
  (ARCH-5 ne porte que sur les chapitres). Si le professeur souhaite un taux de maîtrise sur les accords, les
  questions de compétence transférable peuvent être placées dans un chapitre YAML de grammaire associé au dossier,
  sans être dupliquées dans le quiz (option M1, [`PREPARATION-175.md`](PREPARATION-175.md) § 10).

### C8 — 3e — Comprendre un texte, brevet (dossier)

- **Existant** : `FR3-DNB27-01` importé, v2 « soumis » à valider par un professeur.
- **À ajouter** : 3 QCM au quiz (6 → 9), pour respecter 3 faciles, 3 moyens, 3 difficiles.
- **Même point** que C7 sur la maîtrise.

## 3. Sujets de rédaction (chapitres de la rubrique `redaction`, circuit #187)

Chaque sujet comprend une consigne, une longueur indicative, des critères de réussite et un guide pour le
professeur (`correction` obligatoire, jamais montré à l'élève). Correction **humaine** ; aucun effet sur le taux de
maîtrise. Rédaction fermée tant que `PKP_REDACTION_ACTIVE` est faux (A6) : les sujets peuvent être préparés, validés
et exportés en PDF.

| Sujet | Niveau | Consigne proposée | Longueur | Critères |
|---|---|---|---|---|
| R1 — Raconter une aventure | 6e | Raconte une aventure vécue par un personnage que tu inventes, au présent | 15 à 20 lignes | Situation initiale, péripéties, fin ; présent maîtrisé (C2) ; ponctuation |
| R2 — Raconter un événement passé | 5e | Raconte un événement inventé, à l'imparfait et au passé simple | 20 lignes | Temps du récit (C4) ; connecteurs temporels ; cohérence |
| R3 — Défendre son opinion | 4e | Donne ton avis sur une question proche des élèves et défends-le par deux arguments illustrés d'exemples | 20 à 25 lignes | Thèse claire ; arguments et exemples ; connecteurs logiques ; phrases complexes (C5) |
| R4 — Réflexion type brevet | 3e | Sujet de réflexion dans la forme du brevet, en lien avec C8 | 40 lignes | Problématique, organisation, exemples, langue (accords, C7) |

**Règles RGPD-2** rappelées dans chaque consigne : sujet fictif, ni adresse, ni coordonnées, ni informations
intimes.

## 4. Ce qui est demandé au professeur

- [ ] La liste des huit cours convient, ou propose les changements (notamment le complément du nom et la conjugaison
  en 3e).
- [ ] Les objectifs et les prérequis de chaque fiche conviennent.
- [ ] La répartition des difficultés (1-1-2, 3-3-3, 4-4-5) convient.
- [ ] Les quatre sujets de rédaction conviennent.
- [ ] Les cours de 3e ont besoin, ou non, d'un taux de maîtrise (chapitre d'accompagnement de C7 et C8).

Après validation de la liste, les questions et corrigés sont rédigés (contenu original, registre des sources
rempli), importés en **brouillon**, puis validés question par question par un validateur distinct de l'auteur
(V2-D15) avant toute ouverture aux classes pilotes.
