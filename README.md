# Pipeline PEARO

*(Travail initial : MPM, 7 août 2026 ; workflow opérationnel complété en août 2026)*

Ce dépôt récupère des champs horaires PE-AROME depuis Hendrix, calcule un champ journalier de `tasmax` pour chaque membre, puis peut envoyer les fichiers NetCDF produits vers le Cerfacs.

## Quel workflow utiliser ?

Le workflow recommandé est `run_streaming_pipeline.sh`. Il traite les jours séquentiellement, conserve un état de reprise hors du scratch et peut reprendre après une interruption.

| Usage | Commande ou script | Statut |
| --- | --- | --- |
| Traitement normal ou traitement long | `run_streaming_pipeline.sh` | **Recommandé** |
| Pré-staging seul ou diagnostic | `prestage_pearo.sh` | Outil utilisé par le workflow, exécutable manuellement |
| Transfert d'une journée | `fetch_one_day.sh` via `get_one_day.job` | Outil utilisé par le workflow |
| Ancien lancement parallèle | `run_over_all_days.sh` | **Workflow historique de MPM**, conservé pour référence |
| Commandes interactives `hshell`, `stage` et `fstat` | Exemples de diagnostic | **Manuel**, non nécessaire au workflow recommandé |

## Architecture du workflow recommandé

Le dépôt et sa configuration sont installés sur **Belenos**, dans un espace persistant tel que `$HOME/SAVE/PEARO-toolkit`. Hendrix sert uniquement de source pour les fichiers GRIB.

Pour chaque date listée dans `PEARO_DAYS_FILE`, le workflow réalise les étapes suivantes :

1. pré-staging des GRIB depuis les bandes vers le cache disque Hendrix avec `hstage` et suivi avec `hfstat` ;
2. transfert séquentiel des GRIB vers le scratch Belenos avec `ftget`, sur un nœud `transfert` ;
3. lecture des champs horaires de température de l'air à 2 m et calcul de `tasmax` avec `compute_tasmax.py`, sur `normal256` ;
4. envoi optionnel des NetCDF vers le Cerfacs avec `rsync`, sur un nœud `transfert` ;
5. suppression optionnelle des GRIB temporaires après réussite.

Le `tasmax` est calculé à partir des 12 champs horaires sélectionnés dans chaque liste de fichiers. Le script vérifie que leurs heures de validité sont distinctes et consécutives, sans supposer d'échéances de prévision fixes. Il ne correspond donc pas à un maximum calculé sur 24 heures.

## Installation sur Belenos

Pour le moment, la source de référence est uniquement la branche `pagec/prestage-ftserv-t2m` du fork `pagecp/PEARO-toolkit`. Ne pas utiliser la branche principale du fork ni copier directement l'ancien dépôt de MPM : ils ne contiennent pas nécessairement le workflow opérationnel et ses dernières corrections.

Git n'étant pas nécessairement disponible ou configuré sur Belenos, mettre d'abord à jour une copie du fork sur une machine ayant accès à GitHub, par exemple `elnino` :

```bash
cd /home/globc/page
git clone --branch pagec/prestage-ftserv-t2m --single-branch \
  https://github.com/pagecp/PEARO-toolkit.git PEARO-toolkit
cd PEARO-toolkit
```

Si la copie existe déjà sur `elnino`, la mettre à jour avec :

```bash
cd /home/globc/page/PEARO-toolkit
git switch pagec/prestage-ftserv-t2m
git pull --ff-only origin pagec/prestage-ftserv-t2m
```

Depuis un nœud `transfert` de Belenos, copier ensuite cette version dans l'espace persistant de l'utilisateur :

```bash
mkdir -p "$HOME/SAVE/PEARO-toolkit"
rsync -av page@elnino.cerfacs.fr:/home/globc/page/PEARO-toolkit/ \
  "$HOME/SAVE/PEARO-toolkit/"
cd "$HOME/SAVE/PEARO-toolkit"
```

Cette copie contient le répertoire `.git`, mais aucune commande Git n'est nécessaire sur Belenos pour exécuter le workflow.

Les données temporaires sont placées par défaut sous :

```text
$WORKDIR/PEARO_data/
├── orig_data/     # GRIB transférés depuis Hendrix
└── prepro_data/   # NetCDF journaliers de tasmax
```

## Prérequis

### Accès Hendrix et FTserv

Sur Belenos, charger les outils Hendrix :

```bash
module load hpss/1.0
```

Avant le premier transfert, initialiser l'authentification FTserv :

```bash
ftmotpasse -h hendrix -u "$USER"
```

`hstage` et `hfstat` sont disponibles depuis le nœud de login. `ftget`, `ftput` et `ftmotpasse` doivent être utilisés sur un nœud de la partition `transfert` ; le workflow soumet automatiquement les jobs sur cette partition.

### Environnement Conda

L'environnement créé par MPM peut être réutilisé si l'utilisateur dispose des droits de lecture et d'exécution :

```bash
source /home/ext/cf/cglo/moinemp/SAVE/miniforge3/etc/profile.d/conda.sh
conda activate pearo_env
```

Pour une utilisation indépendante et durable, il est également possible de recréer son propre environnement à partir de `env_pearo.yaml`, puis d'adapter `PEARO_CONDA_SH` et `PEARO_CONDA_ENV`.

## Préparation des listes de fichiers

La liste source des fichiers PE-AROME à récupérer est attendue dans :

```text
config_input/full_lof_to_get.txt
```

Pour produire une liste par journée et le fichier des dates à traiter :

```bash
cd config_input
./scan_file_list.sh full_lof_to_get.txt
cd ..
```

Cette commande génère :

- `lof_YYYY-MM-DD.txt`, avec le chemin Hendrix et le nom local de chaque GRIB ;
- `lof_days.txt`, avec une date par ligne au format `YYYY-MM-DD`.

Exemple d'une ligne de `lof_YYYY-MM-DD.txt` :

```text
/home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/08/02/T2100P/mb001/forecast/grid.arome-forecast.eurw1s40+0012:00.grib	mb001_2022-08-02_grid.arome-forecast.eurw1s40+0012:00.grib
```

Le premier champ est le chemin Hendrix ; le second est le nom donné au fichier dans `orig_data/<YYYY-MM-DD>`.

Le nombre de membres est déduit de chaque fichier `lof_YYYY-MM-DD.txt`. Le workflow accepte donc des journées avec `mb000` à `mb016` (17 membres) comme des journées avec `mb000` à `mb024` (25 membres), sans modification de la configuration.

## Configuration locale

Créer le fichier de configuration local :

```bash
cp config_input/pearo.env.example config_input/pearo.env
```

Le fichier réel `config_input/pearo.env` est ignoré par Git. Les paramètres de connexion ne doivent pas être ajoutés au dépôt.

| Variable | Description | Valeur d'exemple |
| --- | --- | --- |
| `PEARO_DATA_ROOT` | Répertoire racine des GRIB temporaires et des NetCDF produits sur le scratch Belenos. | `${WORKDIR}/PEARO_data` |
| `PEARO_STATE_ROOT` | Répertoire persistant des marqueurs de progression et de reprise, placé hors du scratch. | `${HOME}/.pearo-toolkit-state` |
| `PEARO_DAYS_FILE` | Fichier des dates à traiter, une par ligne au format `YYYY-MM-DD`. | `${PWD}/config_input/lof_days.txt` |
| `PEARO_CONDA_SH` | Chemin du script initialisant Conda dans les jobs Slurm. | `/chemin/vers/miniforge3/etc/profile.d/conda.sh` |
| `PEARO_CONDA_ENV` | Nom de l'environnement Conda contenant les dépendances PEARO. | `pearo_env` |
| `PEARO_PRESTAGE_CHUNK_SIZE` | Nombre maximal de chemins soumis ensemble à `hstage` et `hfstat`. | `300` |
| `PEARO_PRESTAGE_POLL_SECONDS` | Délai en secondes entre deux contrôles du pré-staging. | `120` |
| `PEARO_PRESTAGE_MAX_POLLS` | Nombre maximal de contrôles avant l'échec du pré-staging. | `180` |
| `PEARO_TRANSFER_PARTITION` | Partition Slurm des transferts Hendrix vers Belenos. | `transfert` |
| `PEARO_TRANSFER_TIME` | Limite de temps du transfert d'une journée. | `02:00:00` |
| `PEARO_PREPROCESS_PARTITION` | Partition Slurm utilisée pour le calcul de `tasmax`. | `normal256` |
| `PEARO_PREPROCESS_TIME` | Limite de temps du prétraitement d'une journée. | `01:00:00` |
| `PEARO_SEND_PARTITION` | Partition Slurm utilisée pour l'envoi vers le Cerfacs. | `transfert` |
| `PEARO_SEND_TIME` | Limite de temps de l'envoi d'une journée. | `00:10:00` |
| `PEARO_DO_SEND` | Active (`1`) ou désactive (`0`) l'envoi vers le Cerfacs. | `1` |
| `PEARO_CLEAN_ORIG` | Supprime (`1`) ou conserve (`0`) les GRIB après réussite du traitement. | `1` |
| `PEARO_SEND_HOST` | Nom SSH du serveur Cerfacs destinataire. | `elnino.cerfacs.fr` |
| `PEARO_SEND_USER` | Compte SSH utilisé sur le serveur destinataire. | `page` |
| `PEARO_SEND_DEST_ROOT` | Répertoire racine de destination sur le serveur Cerfacs. | `/chemin/de/destination/PEARO` |

Pour un premier test sans envoi, utiliser :

```bash
PEARO_DO_SEND=0
```

Avant d'activer l'envoi, renseigner localement `PEARO_SEND_HOST`, `PEARO_SEND_USER` et `PEARO_SEND_DEST_ROOT`.

## Lancement du workflow recommandé

Depuis le dépôt installé sur Belenos :

```bash
module load hpss/1.0
./run_streaming_pipeline.sh
```

Le script traite les jours un par un et attend la réussite de chaque job avec `sbatch --wait`. Les transferts sont effectués fichier par fichier avec `ftget` ; seul le pré-staging est soumis par lots, définis par `PEARO_PRESTAGE_CHUNK_SIZE`.

### Suivi et reprise

Les marqueurs sont conservés sous :

```text
$PEARO_STATE_ROOT/<YYYY-MM-DD>/
```

Ils comprennent notamment `transfer.ok`, `preprocess.ok`, `send.ok` lorsque l'envoi est activé, et `done.ok`.

Après une interruption, relancer la même commande. Le workflow vérifie les membres attendus dans le LOF avant d'ignorer une journée marquée terminée. Si la liste est complétée avec de nouveaux membres, il rétablit les GRIB nécessaires si le scratch a été purgé, puis ne recalcule que les NetCDF manquants avant de reprendre l'envoi :

```bash
./run_streaming_pipeline.sh
```

## Outils manuels de diagnostic

Ces commandes ne sont pas nécessaires pour un lancement normal, mais permettent de contrôler séparément les deux premières étapes.

Pré-staging d'une journée :

```bash
module load hpss/1.0
./prestage_pearo.sh config_input/lof_2022-08-11.txt
```

Options utiles :

```bash
./prestage_pearo.sh config_input/lof_2022-08-11.txt --verify-only
./prestage_pearo.sh config_input/lof_2022-08-11.txt --chunk-size 500 --poll-seconds 300
```

Transfert manuel, à exécuter sur un nœud `transfert` :

```bash
./fetch_one_day.sh \
  config_input/lof_2022-08-11.txt \
  "$WORKDIR/PEARO_data/orig_data/2022-08-11"
```

Les anciennes commandes interactives `hshell`, `stage` et `fstat` restent utiles pour diagnostiquer Hendrix. Elles ne constituent pas la procédure recommandée pour traiter les listes PEARO locales à Belenos : le workflow utilise `hstage -a -f` et `hfstat -f`.

## Workflow historique de MPM — legacy

Le dépôt initial utilisait `run_over_all_days.sh`, qui lançait les couples de jobs `get_one_day.job` et `preprocess_one_day.job` en parallèle pour chaque journée. Il permettait également de désactiver globalement le rapatriement :

```bash
./run_over_all_days.sh
./run_over_all_days.sh 0
```

Cette procédure est conservée pour référence et compatibilité, mais elle n'est plus recommandée pour les traitements longs : le contournement du transfert est global, l'état de reprise est moins précis et plusieurs journées peuvent occuper simultanément le scratch.

## Validation effectuée

Tests réalisés sur Belenos et Hendrix le 31 août 2026 :

- pré-staging avec `hstage` et `hfstat` ;
- transfert avec `ftget` sur un nœud `transfert` ;
- traitement complet du 11 août 2022 pour les 16 membres disponibles, soit 192 GRIB ;
- production de 16 fichiers NetCDF journaliers de `tasmax` ;
- conservation des marqueurs de reprise hors du scratch ;
- envoi des 16 NetCDF vers `elnino.cerfacs.fr` avec `rsync`.

La concaténation finale des journées et le lancement sur la liste complète restent à valider.
