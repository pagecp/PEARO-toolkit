#!/bin/bash

echo "===================================================="
echo " Comptage des fichiers par jour et par membre"
echo "===================================================="

awk -F'/' '{
    date=$(NF-6)"/"$(NF-5)"/"$(NF-4)
    member=$(NF-2)
    key=date" "member
    count[key]++
}
END {
    for (k in count) print k, count[k]
}' $1 | sort

echo "===================================================="
echo " Comptage des fichiers par jour"
echo "===================================================="

awk -F'/' '{
    date=$(NF-6)"/"$(NF-5)"/"$(NF-4)
    count[date]++
}
END {
    for (d in count) print d, count[d]
}' $1 | sort

echo "===================================================="
echo " Construction de la liste de fichiers par jour"
echo " - 1er  champ: chemin+nom fichier d'origine"
echo " - 2eme champ: nouveau nom fichier (+ complet)"
echo " => prêt à être utilisé par ftget"
echo "===================================================="

awk '
{
    original = $0

    if (match($0, /([0-9]{4})\/([0-9]{2})\/([0-9]{2})/)) {
        date_tag = substr($0, RSTART, RLENGTH)
        gsub("/", "-", date_tag)
        outfile = "lof_" date_tag ".txt"
    }

    if (match($0, /(mb[0-9]+)/)) {
        member = substr($0, RSTART, RLENGTH)
    }

    n = split($0, parts, "/")
    filename = parts[n]

    renamed = member "_" date_tag "_" filename

    print original "\t" renamed >> outfile
    close(outfile)
}
' $1

echo "===================================================="
echo " Ecriture de la liste des dates"
echo "===================================================="

awk '
{
    if (match($0, /([0-9]{4})\/([0-9]{2})\/([0-9]{2})/)) {
        date_tag = substr($0, RSTART, RLENGTH)
        gsub("/", "-", date_tag)
        print date_tag
    }
}
' $1 | sort -u > lof_days.txt