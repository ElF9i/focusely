# Sauvegarde PostgreSQL (conteneur Docker) -> backups\focusely_AAAAMMJJ_HHMMSS.dump
param([string]$OutDir = "$PSScriptRoot\..\backups", [int]$Keep = 14)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$c = docker ps --format "{{.Names}}|{{.Image}}" | Where-Object { $_ -match 'postgres' } | Select-Object -First 1
if (-not $c) { throw "Aucun conteneur PostgreSQL en cours d'execution (docker compose up -d)." }
$name = $c.Split('|')[0]
$user = (docker exec $name printenv POSTGRES_USER).Trim(); if (-not $user) { $user = 'postgres' }
$db   = (docker exec $name printenv POSTGRES_DB).Trim();   if (-not $db)   { $db = $user }

$file = Join-Path $OutDir ("focusely_{0:yyyyMMdd_HHmmss}.dump" -f (Get-Date))
docker exec $name pg_dump -U $user -d $db -Fc -f /tmp/focusely.dump
docker cp "${name}:/tmp/focusely.dump" $file
docker exec $name rm -f /tmp/focusely.dump
Write-Host "Sauvegarde : $file"

# Rotation : on garde les $Keep plus recentes
Get-ChildItem $OutDir -Filter 'focusely_*.dump' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force