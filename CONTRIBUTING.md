# Contribuer à Focusely

## Installation (une seule fois)

Outils nécessaires : Git, .NET SDK 8, Flutter, JDK 17, Docker Desktop, un téléphone Android avec le débogage USB.

```powershell
git clone https://github.com/ElF9i/focusely.git
cd focusely
powershell -ExecutionPolicy Bypass -File .\setup_ami.ps1
```

Le script vérifie les outils, crée `appsettings.Development.json` avec ta propre clé, démarre la base PostgreSQL (Docker) et installe les paquets Flutter.

## Lancer le projet

Terminal 1, l'API :
```powershell
cd backend\Focusely.Api
dotnet run --urls http://0.0.0.0:8080
```

Terminal 2, l'app sur le téléphone (même Wi-Fi que le PC) :
```powershell
cd mobile
flutter run
```

Sur la page de connexion, l'icône serveur permet de saisir l'adresse de ton PC (`http://TON_IP:8080`). Crée ton propre compte : ta base de données est locale et ne contient pas les comptes des autres.

## Travailler à deux

1. Récupérer la dernière version : `git pull`
2. Créer une branche, jamais de travail direct sur `main` : `git checkout -b ma-fonction`
3. Faire de petits commits : `git add .` puis `git commit -m "Ce que j'ai changé"`
4. Envoyer : `git push -u origin ma-fonction`
5. Ouvrir une Pull Request sur GitHub. Le propriétaire relit, puis fusionne avec Merge.

Avant de fusionner, lancer `flutter analyze` : il ne doit afficher aucune ligne `error`.

## Répartition conseillée

| Zone | Qui |
|---|---|
| Backend (`backend/`) : amis, Study Rooms, chat (SignalR) | propriétaire |
| App (`mobile/lib/features/`) : notifications, ambiances sonores, planificateur | collaborateur |

Éviter de modifier le même fichier en même temps. Fichiers partagés sensibles : `mobile/lib/main.dart` (navigation), `mobile/lib/core/` (réseau, synchro, cache) et `AppDbContext.cs`.

## Règles du projet

- Le temps est calculé à partir d'horodatages, jamais avec un compteur local.
- Une séance est validée à partir de 60 secondes. Pas de séances simultanées.
- Hors-ligne d'abord : toute fonction de l'app doit rester utilisable sans réseau, ou le dire clairement à l'utilisateur.
- Chaque séance a un identifiant unique créé par le téléphone, pour qu'elle ne soit jamais comptée deux fois.
- Une modification de la base passe par une migration : `dotnet ef migrations add NomDeLaMigration` dans `backend/Focusely.Api`.
- Ne jamais committer de mot de passe, de clé ou de fichier `.env`.