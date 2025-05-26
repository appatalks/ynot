#!/bin/bash/

# https://stackoverflow.com/questions/10622179/how-to-find-identify-large-commits-in-git-history

# Push one commit at a time
# git push <remotename> <commit SHA>:<branch>

#check if numfmt is installed
if ! command -v numfmt &> /dev/null
then
    echo "numfmt could not be found"
    git rev-list --objects --all |
    git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' |
    sed -n 's/^blob //p' |
    sort --numeric-sort --key=2 |
    cut -c 1-12,41-
else
    git rev-list --objects --all |
    git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' |
    sed -n 's/^blob //p' |
    sort --numeric-sort --key=2 |
    cut -c 1-12,41- |
    $(command -v gnumfmt || echo numfmt) --field=2 --to=iec-i --suffix=B --padding=7 --round=nearest
fi
