# Restauration : .\deploy\restore.ps1 -File .\backups\focusely_20261120_020000.dump
param([Parameter(Mandatory = $true)][string]$File)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $File)) { throw "Fichier introuvable : $File" }
$c = docker ps --format "{{.Names}}|{{.Image}}" | Where-Object { $_ -match 'postgres' } | Select-Object -First 1
if (-not $c) { throw "Aucun conteneur PostgreSQL en cours d'execution." }
$name = $c.Split('|')[0]
$user = (docker exec $name printenv POSTGRES_USER).Trim(); if (-not $user) { $user = 'postgres' }
$db   = (docker exec $name printenv POSTGRES_DB).Trim();   if (-not $db)   { $db = $user }

Write-Host "ATTENTION : les donnees actuelles de '$db' seront remplacees." -ForegroundColor Yellow
if ((Read-Host "Tape OUI pour continuer") -ne 'OUI') { exit }
docker cp $File "${name}:/tmp/restore.dump"
docker exec $name pg_restore -U $user -d $db --clean --if-exists --no-owner /tmp/restore.dump
docker exec $name rm -f /tmp/restore.dump
Write-Host "Restauration terminee. Redemarre l'API."