

<h1 align="center">Focusely</h1>
<p align="center"><b>Chaque minute compte.</b><br>
Application mobile de suivi du temps d'étude : chronomètre fiable, Pomodoro, matières, statistiques, XP, badges et défis.</p>


## Fonctions

| | |
|---|---|
| **Chrono fiable** | Le temps est calculé à partir d'horodatages, jamais avec un compteur local : il reste exact en arrière-plan et après un redémarrage. |
| **3 modes** | Focus (15 à 90 min), Pomodoro (25 min de travail, 5 min de pause) et Chrono libre. |
| **Matières** | Emoji et couleur par matière, séances liées à une matière. |
| **Statistiques** | Temps du jour, de la semaine et du mois, graphique sur 7 jours, carte de régularité sur 35 jours, temps par matière. |
| **XP, niveaux et série** | 2 XP par minute + 10 XP par séance, rangs de Novice à Légende, série 🔥 (10 min d'étude par jour). |
| **Badges** | 14 badges (premières séances, heures cumulées, séries, marathon, noctambule, lève-tôt, niveau). |
| **Défis** | *Time Goal* (atteindre un temps avant la fin) et *Speed Race* (le premier à l'objectif gagne), avec classement. |
| **Classement** | Top de la semaine. |
| **Mode hors-ligne** | L'app fonctionne sans Wi-Fi : séances et matières sont enregistrées sur le téléphone (SQLite), stats et historique viennent du cache, et tout est envoyé au retour du réseau, sans double comptage. |

## Stack

- **Mobile** : Flutter (Riverpod, Dio, SQLite)
- **Backend** : ASP.NET Core 8 (API REST, JWT, EF Core)
- **Base de données** : PostgreSQL 16 (Docker)

## Démarrer en local

1. Base de données :
   ```
   docker compose up -d db
   ```
2. API : copier `backend/Focusely.Api/appsettings.Development.example.json` en
   `appsettings.Development.json`, y mettre vos valeurs, puis :
   ```
   cd backend/Focusely.Api
   dotnet run --urls http://0.0.0.0:8080
   ```
   Documentation interactive : http://localhost:8080/swagger
3. App mobile (téléphone branché en USB, même Wi-Fi que le PC) :
   ```
   cd mobile
   flutter run
   ```
   L'adresse du serveur se change depuis l'icône serveur de la page de connexion.

## Règles métier clés

- **RG01** : une séance est validée à partir d'une minute.
- **RG02** : le temps est calculé à partir d'horodatages, pas d'un compteur.
- **RG03** : pas de séances simultanées, durées négatives refusées, séances de plus de 12 h ou de plus de 30 jours refusées à la synchronisation.
- Hors-ligne : chaque séance a un identifiant unique, donc elle ne peut pas être comptée deux fois.

## Structure

```
backend/Focusely.Api/   API (contrôleurs, modèles, migrations)
mobile/lib/             app Flutter (core, features)
docs/                   vidéo de découverte
docker-compose.yml      base PostgreSQL
```

## Feuille de route

- [x] Authentification, chrono, historique
- [x] Matières, Pomodoro, statistiques, XP, niveaux, séries
- [x] Mode hors-ligne
- [x] Badges, défis et classement
- [ ] Amis, Study Rooms et chat (SignalR)
- [ ] Notifications, ambiances sonores, planificateur

## Sécurité

Le mot de passe de développement et la clé JWT sont des valeurs d'exemple : ne les utilise pas en production, et garde le dépôt privé tant qu'ils sont dans le code.

https://github.com/user-attachments/assets/4b17b33d-a44c-415b-907b-0dd6fd984cc6

