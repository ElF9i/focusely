# Focusely - installation pour un nouveau collaborateur
# Usage (a la racine du projet clone) : powershell -ExecutionPolicy Bypass -File .\setup_ami.ps1

$ErrorActionPreference = 'Continue'
function Step($t) { Write-Host ""; Write-Host "== $t" -ForegroundColor Cyan }
function Ok($t)   { Write-Host "  OK  $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  !!  $t" -ForegroundColor Yellow }
function Fail($t) { Write-Host "  XX  $t" -ForegroundColor Red }
function Has($c)  { return [bool](Get-Command $c -ErrorAction SilentlyContinue) }

$root = $PSScriptRoot
$api = Join-Path $root 'backend\Focusely.Api'
$mobile = Join-Path $root 'mobile'
$enc = New-Object System.Text.UTF8Encoding($false)

Step "1/5 Outils"
$missing = @()
if (Has git) { Ok "Git" } else { Fail "Git manquant : winget install Git.Git"; $missing += 'git' }
$dv = (dotnet --version 2>$null | Out-String).Trim()
if ($dv -match '^8\.') { Ok ".NET SDK $dv" } else { Fail ".NET SDK 8 manquant : winget install Microsoft.DotNet.SDK.8"; $missing += 'dotnet' }
if (Has flutter) { Ok "Flutter" } else { Fail "Flutter manquant : https://docs.flutter.dev/get-started/install/windows"; $missing += 'flutter' }
if (Has docker) { Ok "Docker" } else { Fail "Docker Desktop manquant : winget install Docker.DockerDesktop"; $missing += 'docker' }
if (Has adb) { Ok "adb" } else { Warn "adb absent : winget install Google.PlatformTools (utile pour le telephone)" }
$jdk17 = Get-ChildItem 'C:\Program Files\Java','C:\Program Files\Eclipse Adoptium','C:\Program Files\Microsoft' -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -match 'jdk-?17' -and (Test-Path (Join-Path $_.FullName 'bin\javac.exe')) } | Select-Object -First 1
if ($jdk17) {
  Ok "JDK 17 : $($jdk17.FullName)"
  flutter config --jdk-dir "$($jdk17.FullName)" | Out-Null
  Ok "Flutter utilise ce JDK (le Java du PATH n'est pas modifie)"
} else { Warn "JDK 17 introuvable : winget install Microsoft.OpenJDK.17, puis flutter config --jdk-dir ""<dossier du JDK>""" }
if ($missing.Count -gt 0) { Fail "Installe les outils manquants puis relance ce script."; exit 1 }

Step "2/5 Configuration de l'API"
$cfg = Join-Path $api 'appsettings.Development.json'
if (Test-Path $cfg) {
  Ok "appsettings.Development.json existe deja"
} else {
  $key = -join ((1..48) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
  $json = @"
{
  "Logging": { "LogLevel": { "Default": "Information", "Microsoft.AspNetCore": "Warning" } },
  "ConnectionStrings": {
    "Default": "Host=localhost;Database=focusely;Username=focusely;Password=change_me"
  },
  "Jwt": { "Key": "dev_$key" }
}
"@
  [IO.File]::WriteAllText($cfg, $json, $enc)
  Ok "appsettings.Development.json cree (cle JWT aleatoire, mot de passe de la base = celui de docker-compose.yml)"
}

Step "3/5 Base de donnees (Docker)"
docker info 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
  Warn "Docker ne repond pas : lance Docker Desktop, attends l'icone verte, puis relance ce script."
} else {
  Set-Location $root
  docker compose up -d db
  if ($LASTEXITCODE -eq 0) { Ok "Base PostgreSQL demarree (docker compose ps doit afficher 'healthy')" } else { Fail "docker compose a echoue" }
}

Step "4/5 Paquets"
Set-Location $api
dotnet build 2>&1 | Select-Object -Last 4
if ($LASTEXITCODE -eq 0) { Ok "Backend compile" } else { Fail "Erreur de compilation backend : copie-la et envoie-la au proprietaire" }
Set-Location $mobile
flutter pub get
if ($LASTEXITCODE -eq 0) { Ok "Paquets Flutter installes" } else { Fail "flutter pub get a echoue" }

Step "5/5 Reseau (pour le telephone)"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not (Get-NetFirewallRule -DisplayName 'Focusely API' -ErrorAction SilentlyContinue)) {
  if ($isAdmin) {
    New-NetFirewallRule -DisplayName 'Focusely API' -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -Profile Private | Out-Null
    Ok "Regle de pare-feu creee (port 8080)"
  } else {
    Warn "Pare-feu : ouvre PowerShell en administrateur et lance :"
    Write-Host '     New-NetFirewallRule -DisplayName "Focusely API" -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -Profile Private'
  }
} else { Ok "Regle de pare-feu presente" }
$ip = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
  Where-Object { $_.InterfaceAlias -like 'Wi-Fi*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
if ($ip) { Ok "Ton adresse Wi-Fi : http://$($ip.IPAddress):8080  (a saisir dans l'app, icone serveur de la page de connexion)" }
else { Warn "Adresse Wi-Fi non trouvee : lance ipconfig et prends l'IPv4 du Wi-Fi" }
Warn "Verifie que ton Wi-Fi est en profil 'Prive' (Parametres, Reseau, Wi-Fi, Proprietes)."

Write-Host ""
Write-Host "Termine. Pour lancer :" -ForegroundColor Green
Write-Host "  Terminal 1 : cd backend\Focusely.Api ; dotnet run --urls http://0.0.0.0:8080"
Write-Host "  Terminal 2 : cd mobile ; flutter run   (telephone branche en USB, debogage USB active)"
Write-Host "Lis CONTRIBUTING.md pour travailler a deux (branches et Pull Requests)."