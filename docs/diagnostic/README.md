<!-- Banque de diagnostic des acquis antérieurs — note de cadrage (Claude) -->
# Diagnostic des acquis antérieurs — note de cadrage

> Statut : **proposition, en attente des décisions du propriétaire** (§ 6). Aucune question n'est encore dans
> `contenu/` ; le pilote `pilote-3e-acquis-4e.yaml` est prêt à y être déplacé une fois le format arrêté.

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
| Terminale | 1re, selon l'enseignement suivi | 2nde, puis plus ancien |

Le bilan se fait **par compétence**, jamais sous la forme « niveau de 5e ». Les observations du diagnostic restent
séparées du taux de maîtrise : une réussite isolée ne déclare pas une compétence maîtrisée.

## 2. Quel programme interroger

Ce qui compte n'est pas le programme de l'année en cours, mais celui **que l'élève a suivi l'année précédente**.
En 2026-2027, toutes les classes antérieures ont été suivies en 2025-2026, avant l'entrée en vigueur des nouveaux
programmes de 5e, 2nde et 1re (septembre 2026). **Tous les diagnostics de l'année 2026-2027 portent donc sur les
anciens programmes** (repères 2020 au collège, programmes 2019 au lycée). Les premiers diagnostics sur un nouveau
programme seront ceux de 2027-2028 (entrée en 4e sur la 5e 2026, en 1re sur la 2nde 2026, en Terminale sur la
1re 2026 ; pour l'entrée en 6e, vérifier le calendrier du nouveau programme de CM2).

Conséquence : chaque question porte le programme dont elle teste un acquis (`3e-2020`, `5e-2026`…), et le
questionnaire est choisi selon l'année scolaire de passation, pas selon la seule classe.

## 3. Ce que le moteur sait corriger

Types disponibles : `qcm` (une seule lettre), `numerique`, `expression` (`docs/CONTENU.md`).

| Format de la banque | Traitement proposé |
|---|---|
| QCM | `qcm` tel quel |
| Calcul à résultat unique | `numerique` ou `expression` |
| QSM (plusieurs bonnes réponses) | **non pris en charge** : reformuler en QCM (« Quelles affirmations sont vraies ? A) 1 et 3 B) … ») ou ajouter un type au moteur (décision) |
| Rédaction, justification, construction | **hors correction automatique** : passation sur papier ou correction par le professeur, jusqu'à validation d'une correction automatique |
| Valeur arrondie, ensemble de solutions, coordonnées | QCM |

## 4. Corrections à apporter à la banque fusionnée (152 questions)

Vérifiées contre les référentiels du dépôt (`referentiels/`) et les calculs refaits.

### 4.1 Questions hors du programme de l'année précédente

| ID | Problème | Proposition |
|---|---|---|
| 3E-14 | Réciproque de Thalès : programme de **3e** (`3E-2020-GEOM-01`) | Retirer de l'entrée en 3e ; la garder pour l'entrée en 2nde |
| 2N-13 | Systèmes d'équations : programme de **2nde** | Retirer |
| 2N-14 | Inéquations : programme de **2nde** (`2NDE-2026-ALG-05`), absentes du cycle 4 | Retirer, ou remplacer par une inéquation « tester si 3 est solution » |
| 4E-16 | Produit de fractions : 4e | Remplacer par une addition à dénominateurs multiples |
| 4E-14 | Puissances de relatifs : 4e (en 5e, seulement carré et cube de nombres positifs) | Remplacer par un calcul de relatifs, ou reporter à l'entrée en 3e |
| 5E-15 | Parallélogramme : programme de **5e** | Déplacer vers l'entrée en 4e (déjà couvert par 4E-20) |
| 6E-12 | Produit de deux décimaux : 6e | Déplacer en entrée en 5e ; en 6e, garder la partie addition |

### 4.2 Questions fausses ou ambiguës

| ID | Problème | Correction |
|---|---|---|
| 4E-15 | QCM à **deux** bonnes réponses : $3/5 = 0{,}6$ | Remplacer $3/5$ par $5/8$ (0,625, la plus grande) ou $0{,}6$ par $0{,}65$ |
| 5E-15 | Choix D « angles opposés supplémentaires » faux mais trompeur | Écrire « angles consécutifs supplémentaires » comme distracteur explicite |
| 1R-19 | Trois valeurs ne prouvent pas que $f$ ne s'annule qu'en 3 | Donner la courbe, ou demander seulement $f(3)$ |
| 3E-20 | « Combien de graduations à gauche de 0 ? » réponse « 2,5 » : question mal posée | Remplacer par un rangement de relatifs (QCM) |
| 6E-16 | Question sans difficulté de lecture (« entre 2 et 3 ») | Demander l'abscisse d'un point placé sur une droite graduée |

### 4.3 Doublons

| Doublons | Proposition |
|---|---|
| 2N-08 = 3E-13 (mêmes nombres) ; 2N-09 = 3E-15 | Changer les valeurs en 2nde (règle des variantes) |
| 1R-14 = MC-02 ; 1R-20 ≈ TE-06 | Changer les valeurs |

### 4.4 Terminale : le module « mathématiques complémentaires » est mal ciblé

Les élèves de mathématiques complémentaires ont **suivi la spécialité en 1re** : les questions TE-07 à TE-12
(second degré, dérivation, suites, probabilités conditionnelles) sont précisément leurs prérequis. Le module MC-01
à MC-06 ne correspond à aucun parcours de 1re ; il recouvre plutôt les élèves sans spécialité (enseignement
scientifique). Proposition de routage :

| Parcours en Terminale | Acquis de 1re interrogés |
|---|---|
| Spécialité, avec ou sans maths expertes | Socle TE-01 à 06 + module spécialité TE-07 à 12 |
| Mathématiques complémentaires | Socle + module spécialité (niveau D1-D2 en priorité) |
| Voie technologique | Socle + module technologique (TECH-01 à 06) |
| Sans maths en Terminale | Pas de diagnostic de maths |

Le module MC-xx peut servir à l'entrée en 1re pour les élèves qui ne prennent pas la spécialité.

## 5. Pilote : entrée en 3e

`pilote-3e-acquis-4e.yaml` transcrit au format du dépôt les questions automatisables de l'entrée en 3e : 18 questions
(3E-01 à 3E-13, 3E-15 à 3E-19), en 5 compétences reliées par `prerequis` aux chapitres de 4e existants
(`4E-THALES`, `4E-PYRAMIDE-CONE`…), pour que le bilan oriente directement vers le bon cours. 3E-14 (hors programme)
et 3E-20 (mal posée) sont exclues. Il passe `python -m app.contenu verifier`.

## 6. Décisions demandées au propriétaire

1. **Où ranger le diagnostic.** Le dépôt exige, pour chaque compétence, un cours et des questions des cinq
   difficultés (`test_inventaire_matrice_trous_et_registre`) ; un diagnostic n'a que des difficultés 1 à 3 et
   renvoie au cours de l'année précédente. Options :
   - **A.** le loger dans `mise-a-niveau` et le compléter (résumé, questions D4-D5) : possible tout de suite,
     mais pas de passation dédiée ni de bilan séparé de la maîtrise ;
   - **B.** créer une nature de chapitre « diagnostic » (exemptée de la règle des cinq difficultés), avec passation
     sans correction affichée, « Je ne sais pas », relance de deux questions après un échec et bilan par
     compétence, stocké à part du taux de maîtrise : demande une issue, une migration et du front.
   - Recommandation : **B**, en commençant par la passation et le bilan ; le pilote est déjà au bon format pour l'une
     ou l'autre option.
2. **QSM** : reformuler en QCM (recommandé pour le pilote) ou ajouter un type « choix multiples » au moteur.
3. **Questions rédigées** : passation papier corrigée par le professeur, ou saisie libre corrigée dans l'interface.
4. Valider les corrections du § 4 ; la **validation pédagogique** des questions reste celle d'un professeur.
