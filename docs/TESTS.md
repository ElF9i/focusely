# Plan de tests et rapport : Focusely

## Tests automatiques
| Type | Commande | Contenu |
|---|---|---|
| Unitaires (logique métier mobile) | `cd mobile; flutter test` | badges, séries de jours, seuil de 10 min |
| Compilation + analyse | `flutter analyze` | qualité du code Dart |
| Intégration continue | GitHub Actions (`.github/workflows/ci.yml`) | build API + analyse + tests à chaque push |

## Critères d'acceptation du cahier des charges
| # | Critère | État | Comment vérifier |
|---|---|---|---|
| 1 | Créer un compte et se connecter | ✅ | inscription puis connexion dans l'app |
| 2 | Lancer, suspendre, terminer une séance | ✅ | onglet Focus |
| 3 | Séances correctement enregistrées | ✅ | onglet Historique et Swagger `/api/sessions/history` |
| 4 | Statistiques correctes | ✅ | comparer l'onglet Stats à l'historique |
| 5 | Créer et rejoindre un challenge | ⏳ | à développer (backend + app) |
| 6 | Classement sans incohérence | ⏳ | à développer |
| 7 | Récompenses automatiques | ⚠️ | badges calculés dans l'app ; attribution côté serveur à faire |
| 8 | Notifications | ⏳ | à développer |
| 9 | Données cohérentes après déconnexion | ✅ | couper le Wi-Fi, étudier, rallumer : une seule séance côté serveur |
| 10 | Android et iOS | ⚠️ | Android testé ; projet iOS non testé |

## Scénario manuel « coupure Wi-Fi »
1. Ouvrir Stats, Historique et Focus en ligne.
2. Couper le Wi-Fi, créer une matière, faire une séance de plus d'une minute.
3. Vérifier Stats et Historique (la séance apparaît, bandeau « en attente »).
4. Rallumer le Wi-Fi, attendre 30 s : la matière et la séance sont sur le serveur, sans doublon.

## Résultats (à compléter)
| Date | Testeur | Appareil / Android | Scénario | Résultat |
|---|---|---|---|---|
| | | | | |