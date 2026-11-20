# Focusely

Application mobile de suivi du temps d'étude : chronomètre fiable (le serveur fait foi),
Pomodoro, matières, statistiques, XP / niveaux / séries, et mode hors-ligne avec synchronisation.

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
- Le temps est calculé à partir d'horodatages, jamais avec un compteur local.
- Séance validée à partir de 1 minute. Pas de séances simultanées. Durées négatives refusées.
- Hors-ligne : les séances sont mises en file d'attente (SQLite) puis envoyées au retour du réseau.
  Chaque séance a un identifiant unique : elle ne peut pas être comptée deux fois.
