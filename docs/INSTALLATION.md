# Guide d'installation : Focusely

Application mobile de gestion du temps d'étude (Flutter) + API (ASP.NET Core) + PostgreSQL, hébergées sur un serveur local, sans Cloud.

## 1. Prérequis
| Outil | Usage |
|---|---|
| Docker Desktop (ou Docker Engine) | PostgreSQL, Nginx |
| .NET SDK 8.0 | API |
| Flutter (Dart ^3.14) + Android SDK | application mobile |
| Git | récupération du code |

## 2. Base de données
```powershell
cd focusely
docker compose up -d
```

## 3. API
```powershell
cd backend/Focusely.Api
dotnet run --urls http://0.0.0.0:8080
```
Les migrations de la base sont appliquées au démarrage (voir les journaux). Swagger : `http://IP_DU_SERVEUR:8080/swagger`.

**Pare-feu Windows** (une seule fois, en administrateur) :
```powershell
netsh advfirewall firewall add rule name="Focusely API" dir=in action=allow protocol=TCP localport=8080
```
Réserve une adresse IP fixe au serveur (réservation DHCP ou IP statique) : `ipconfig` pour la lire.

### API dans Docker (optionnel)
```powershell
docker build -t focusely-api backend/Focusely.Api
```
Le `Dockerfile` publie l'API sur le port 8080. Fournis la chaîne de connexion PostgreSQL et la clé JWT par variables d'environnement (mêmes noms que dans `appsettings.json`, `:` remplacé par `__`).

## 4. HTTPS avec Nginx (optionnel, recommandé)
1. Génère un certificat pour l'IP du serveur :
   ```bash
   mkdir -p deploy/nginx/certs && cd deploy/nginx/certs
   openssl req -x509 -nodes -newkey rsa:2048 -days 825 -keyout focusely.key -out focusely.crt \
     -subj "/CN=focusely.local" -addext "subjectAltName=IP:192.168.1.14"
   ```
2. Installe `focusely.crt` sur les téléphones (Paramètres > Sécurité > Installer un certificat).
3. Lance le proxy : `docker compose -f deploy/docker-compose.nginx.yml up -d`.
4. Dans l'app, utilise `https://192.168.1.14` comme adresse du serveur.

## 5. Application mobile
```powershell
cd mobile
flutter pub get
flutter run                       # téléphone en USB
flutter build apk --release       # APK : build/app/outputs/flutter-apk/app-release.apk
```
Au premier lancement : icône serveur sur l'écran de connexion, saisis `http://IP_DU_SERVEUR:8080`, bouton **Tester**, puis **Enregistrer**. L'adresse peut aussi se changer plus tard dans l'onglet **Profil**.

## 6. Dépannage
| Symptôme | Piste |
|---|---|
| « Serveur injoignable » | téléphone et serveur sur le même Wi-Fi ? pare-feu ? bonne IP ? |
| La séance reste « en attente » | l'API est arrêtée ou injoignable ; elle partira seule au retour du réseau (toutes les 30 s) |
| Séance refusée par le serveur | horodatages incohérents (règle RG03) : vérifie l'heure du téléphone |