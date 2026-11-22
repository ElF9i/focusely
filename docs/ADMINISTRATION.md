# Guide d'administration : Focusely

## Sauvegardes
| Action | Commande |
|---|---|
| Sauvegarde manuelle (Windows) | `.\deploy\backup.ps1` |
| Sauvegarde manuelle (Linux) | `./deploy/backup.sh` |
| Restauration | `.\deploy\restore.ps1 -File .\backups\focusely_AAAAMMJJ_HHMMSS.dump` |

Les fichiers sont dans `backups/` (14 derniers conservés). **Copie ce dossier sur un NAS ou un disque externe** (exigence du cahier des charges).

Planification quotidienne à 2 h :
- Windows : `schtasks /Create /SC DAILY /ST 02:00 /TN FocuselyBackup /TR "powershell -ExecutionPolicy Bypass -File C:\dev\focusely\deploy\backup.ps1"`
- Linux : `0 2 * * * /chemin/focusely/deploy/backup.sh`

**Teste la restauration régulièrement** sur une base vide : une sauvegarde jamais restaurée n'est pas une sauvegarde.

## Supervision
| Contrôle | Commande |
|---|---|
| Services Docker | `docker ps` |
| CPU / RAM des conteneurs | `docker stats --no-stream` |
| Espace disque | `Get-PSDrive C` (Windows) ou `df -h` (Linux) |
| API disponible | ouvrir `http://IP:8080/swagger` |
| Journaux PostgreSQL | `docker logs <nom_du_conteneur_postgres>` |

## Sécurité
- Remplace le mot de passe PostgreSQL et la clé JWT d'exemple avant toute mise en service.
- Accès depuis l'extérieur : VPN de l'établissement uniquement, jamais d'ouverture de ports sur Internet.
- Active HTTPS (Nginx) dès que les téléphones ont installé le certificat.
- Garde le dépôt GitHub **privé** tant que des secrets sont dans le code.

## Mise à jour
```powershell
git pull
cd backend/Focusely.Api; dotnet build; dotnet run --urls http://0.0.0.0:8080
```
Fais une sauvegarde avant chaque mise à jour.