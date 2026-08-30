# Pipeline PEARO pour Jade

*(MPM,  7 août 2026)*

Le code PEARO-toolkit est installé sur mon `$HOME` de Belenos: `/home/ext/cf/cglo/moinemp/SAVE/PEARO-toolkit`

Pour le faire tourner sur un autre compte utilisateur, il suffit de le copier:

```bash
cd $HOME/SAVE
rsync -av /home/ext/cf/cglo/moinemp/SAVE/PEARO-toolkit .
```

Son contenu:

```text
├── README.md
├── config_input/
└── run_over_all_days.sh
├── get_one_day.job
├── preprocess_one_day.job
├── compute_tasmax.py
├── send_one_day.job
├── logs/
├── draft/
```

Les données d'origine qui seront rapatriées depuis Hendrix et les données préprocessées qui seront générées (calcul de tasmax) se trouveront sur le `$WORKDIR` de l'utilsateur sur Belenos, ex. `/scratch/work/moinemp/PEARO_data`, respectivement sous:

```text
├── orig_data/
├── prepro_data/
```

## Préparation de la liste des fichiers PEARO d'origine à utiliser

Cette étape est à faire en amont, une fois pour toutes.

Liste des fichiers PEARO utiles fournie par Jade : `config_input/full_lof_to_get.txt`

Elle contient 13800 fichiers dont:
* 300 fichiers pour 2022/05
* 5700 fichiers pour 2022/06
* 4800 fichiers pour 2022/07
* 3000 fichiers pour 2022/08

C'est 300 fichiers par jour (12 x 25 membres) et les 46 jours retenus sont:

MAI 2022 (1 jour)
```text
2022/05/31 300
```

JUIN 2022 (19 jours)

```text
2022/06/01 300
2022/06/02 300
2022/06/03 300
2022/06/10 300
2022/06/11 300
2022/06/12 300
2022/06/13 300
2022/06/14 300
2022/06/15 300
2022/06/16 300
2022/06/17 300
2022/06/18 300
2022/06/19 300
2022/06/21 300
2022/06/24 300
2022/06/25 300
2022/06/26 300
2022/06/28 300
2022/06/29 300
```

JUILLET 2022 (16 jours)

```text
2022/07/01 300
2022/07/02 300
2022/07/10 300
2022/07/11 300
2022/07/12 300
2022/07/13 300
2022/07/14 300
2022/07/15 300
2022/07/16 300
2022/07/17 300
2022/07/18 300
2022/07/19 300
2022/07/20 300
2022/07/21 300
2022/07/22 300
2022/07/23 300
```

AOUT (2022 10 jours)

```text
2022/08/01 300
2022/08/02 300
2022/08/03 300
2022/08/08 300
2022/08/09 300
2022/08/10 300
2022/08/11 300
2022/08/12 300
2022/08/16 300
2022/08/17 300
```

*Pour info, 1 jour de données brutes horaires PEARO c'est 13.5 Go / membre, soit 337.5 Go pour les 25 membres; donc our les 46 jours séléctionnés par Jade ça fait 15.5 To.*

*Rectification: il n'y a que 16 membres disponibles sur Hendrix, donc un volumétrie totale de 10 To.*

On commence par générer des listes de fichiers PEARO exploitables (séparés par jour):

```bash
cd config_input
./scan_file_list.sh full_lof_to_get.txt
```

Ceci génère des fichiers du type `config_input/lof_2022-08-02.txt` contenant des lignes du style:

```text
/home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/08/02/T2100P/mb001/forecast/grid.arome-forecast.eurw1s40+0012:00.grib	mb001_2022-08-02_grid.arome-forecast.eurw1s40+0012:00.grib
/home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/08/02/T2100P/mb001/forecast/grid.arome-forecast.eurw1s40+0013:00.grib	mb001_2022-08-02_grid.arome-forecast.eurw1s40+0013:00.grib
/home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/08/02/T2100P/mb001/forecast/grid.arome-forecast.eurw1s40+0014:00.grib	mb001_2022-08-02_grid.arome-forecast.eurw1s40+0014:00.grib
```

Le 1er champ sur chaque ligne est le path du fichier PEARO horaire sur Hendrix, le second le nom qu'il prendra après rapatriement local sous `orig_data/2022-08-02`. 

L'utilsateur n'a pas à se préoccuper de ce rangement, il se fait automatiquement. 

Ces fichiers `config_input/lof_YYYY-MM-DD.txt` ne sont utile que pour le rapatriement des données Hendrix.

Le script `scan_file_list.sh` produit également le fichier`config_input/lof_days.txt` listant les dates à traiter, du style:

```text
2022-05-31
2022-06-01
2022-06-02
```

*AMELIORATION-1: Ce préprocessing de la  grande liste initiale `full_lof_to_get.txt`  pourrait être évité. On peut spécifier les choses dans l'autre sens: l'utilsateur définit les date-jours qu'il veut exploirer (`lof_days.txt`), le nombre de membres qu'il veut utiliser (`nb_members`) et un petit script construit les listes de fichiers horaires pour chaque jour (`lof_YYYY-MM-DD.txt`).*

## Prestaging des fichiers sur hendrix

Avant de lancer le pipeline et rapatrier les données de la PEARO depuis Hendrix, 
il faut faire un prestaging (i.e. remonter les fichiers du stockage bande au cache disk d'Hendrix).

Point important issu de la doc hshell:
* `stage -a -f listing` s'utilise dans `hshell` si le fichier `listing` est visible sur Hendrix.
* `hstage -a -f listing` s'utilise depuis le shell Belenos si le fichier `listing` est local a Belenos.

Dans notre cas, les fichiers `config_input/lof_YYYY-MM-DD.txt` et le listing fourni par Jade sous `/archive2/...` sont censes etre lus depuis Belenos. Il faut donc privilegier `hstage` et `hfstat`, pas `stage -f` dans `hshell`.

Exemple, pour pré-stager les données PEARO du 2022-05-31 du membre 1, faire sur Belenos:

```bash
module load hpss/1.0
hshell
cd /home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/05/31/T2100P/mb001/forecast
stage -a *.grib
```

La commande hshell nous connecte sur Hendrix.

La commande  `stage -a` (assychrone) rend la main, et il faut attendre que tous les fichiers soient sur le cache (passage du statut `OFF` à `ONL`). Pour vérifier ça:

```bash
fstat *.grib
````
```text
2026-08-07 15:09:07 1417761 normal : grid.arome-forecast.eurw1s40+0016:00.grib: ONL(2) (245324294) (1.92%)
2026-08-07 15:09:07 1417761 normal : grid.arome-forecast.eurw1s40+0008:00.grib: ONL(2) (243663319) (3.85%)
2026-08-07 15:09:07 1417761 normal : grid.arome-forecast.eurw1s40+0002:00.grib: ONL(2) (250163567) (5.77%)
2026-08-07 15:09:07 1417761 normal : grid.arome-forecast.eurw1s40+0017:00.grib: ONL(2) (245676297) (7.69%)
```

Si le statut `STA` s'affiche pour certains fichiers, c'est que le prestaging est en cours.

Pour pré-stager les 25 membres d'un coup:

```bash
module load hpss/1.0
hshell
cd /home/m/mxpt/mxpt001/vortex/arome/pefrance/OPER/2022/05/31/T2100P/mb001/forecast
stage -a mb*/forecast/*.grib
```

Pour automatiser le prestaging a partir d'un fichier `lof_YYYY-MM-DD.txt` du depot, utiliser:

```bash
module load hpss/1.0
cd $HOME/SAVE/PEARO-toolkit
./prestage_pearo.sh config_input/lof_2022-08-11.txt
```

Le script:
* lit uniquement la 1ere colonne du fichier `lof_*` (chemins Hendrix)
* soumet les demandes de prestaging par paquets avec `hstage -a -f`
* verifie l'avancement avec `hfstat -f`
* reboucle tant qu'il reste des fichiers `OFF` ou `STA`
* garde un etat de reprise sous `logs/prestage_*`

Exemples utiles:

```bash
# verifier uniquement un lot deja soumis
./prestage_pearo.sh config_input/lof_2022-08-11.txt --verify-only

# ajuster la taille des paquets et la frequence de polling
./prestage_pearo.sh config_input/lof_2022-08-11.txt --chunk-size 500 --poll-seconds 300
```

## Rapatriement Hendrix vers Belenos

Sur le compte `pagec` au 29 aout 2026:
* sur `belenoslogin0`, `hstage`, `hfstat`, `hshell` sont disponibles apres `module load hpss/1.0`
* sur un noeud `transfert`, `ftget`, `ftput` et `ftmotpasse` sont disponibles apres `module load hpss/1.0`
* `ftmotpasse -h hendrix -u pagec` a permis de creer `~/.ftuas`

Le job de transfert passe par `fetch_one_day.sh`, qui utilise `ftget` a partir du fichier `lof_YYYY-MM-DD.txt`.
Il faut donc executer ce job sur la partition `transfert`, conformement a la doc FTserv.

Test manuel conseille sur 1 ou 2 fichiers avant lancement massif:

```bash
module load hpss/1.0
cd $HOME/SAVE/PEARO-toolkit
ftmotpasse -h hendrix -u $USER
./fetch_one_day.sh config_input/lof_2022-08-11.txt /scratch/work/$USER/PEARO_data/orig_data/2022-08-11
```

## Principe du pipeline d'exécution

Ce pipeline va traiter chaque jour de PEARO: 
1. rapatriement de toutes les données horaires du jour au format natif GRIB
2. lecture de tous les fchiers GRIB du jour et calcul de la tasmax sur les 12h de données diurne et  sauvegarde des résultats au format NETCDF
3. envoi des fichiers de tasmax au Cerfacs
4. ménage des fichiers d'origine

Et ce pour chacun des membres de la prévi d'ensemble.

Techniquement l'enchaînement est le suivant:

`run_over_all_days.sh` lance `get_one_day.job` puis (en cas de succès seulement) `preprocess_one_day.job`. Ce dernier lance le script python `compute_tasmax.py`. Enfin, si le caclul a réussit, `send_one_day.job` envoi les données préprocessées (tasmax) au Cerfacs.

Les scripts `.job` sont des jobs SLURM:
*  `get_one_day.job` est lancé sur la partition `transfer` de Belenos 
* `preprocess_one_day.job` sur la partition `normal256`

Les couples de jobs (`get_one_day.job`, `preprocess_one_day.job`) sont lancés en parallèle pour chaque jour traité.

## Installation de l'environnement mamba pour PEARO (seulement MPM)

La création d'un environnement spécipique est nécessaire, notamment pour avoir le package `cfgrid` qui n'est pas dispo sur Belenos.

```bash
# Purge modules
module purge
# Certificates
export CURL_CA_BUNDLE="/opt/softs/certificats/proxy1_1.pem"
export REQUESTS_CA_BUNDLE="/opt/softs/certificats/proxy1_1.pem"
export GIT_SSL_CAINFO="/opt/softs/certificats/proxy1_1.pem"
# Install Minoforge3
cd SAVE
./Miniforge3-Linux-x86_64.sh # à faire une seul fois pour installer la miniforge3
source /home/ext/cf/cglo/moinemp/SAVE/miniforge3/etc/profile.d/conda.sh
# Create mamba env
cd PEARO
mamba env create -f env_pearo.yaml -vv
```

## Exemple d'appel 

```bash
mamba activate /home/ext/cf/cglo/moinemp/SAVE/miniforge3/pearo_env
cd $HOME/SAVE/PEARO-toolkit
./run_over_all_days.sh
```

On peut choisir de bypasser le rapatriement des données depuis Hendrix (intéressant dans le cas où il a déjà été fait). Pour ce faire:

```bash
cd $HOME/SAVE/PEARO-tool
./run_over_all_days.sh 0
```

*AMELIORATION-2: il faudrait pouvoir faire ce bypass selon les date traitées, ce qui n'est pas le cas, pour l'isntant c'est tout ou rien. Dans l'idéal même, faire une détection automatique des fichiers déjà rapatriés et compléter (MAJ dynamique des fichiers `lof_YYYY-MM-DD.txt`)*


En lançant le run, la totalité des dates présentes dans `config_input/lof_days.txt` va être traitée. 

Pour des tests rapides sur 1 jour par exemple, ou pour traiter d'autres dates, il suffit de modifier `lof_days.txt` (conseil: conserver une copie du fichier complet).

