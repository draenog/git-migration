#!/bin/sh
# Script to fix git repo resulting from cvs2git conversion
# usage: cvs2git_fixes.sh <name>'
#
# It fixes following problems
#
# Branches which are no longer labelled can exist in CVS. cvs2git names them
# unlabeled-<revision>. The script changes "unlabeled" to specified name or
# deleted them if name is unspecified

# Often in CVS repo only changed file are tagged. In this case cvs2git produces
# superfluous commits to delete not tagged file. Here the tag in converted git
# repo is moved to the parent if the tagged commit:
# 1. was made by cvs2svn
# 2. the only change in the tree is deletion of files
# 3. the tag is not on any branch

name=$1

git show-ref --tags | \
while read rev tagname; do
        if [ "`git show --format="%an" --quiet $rev`" = "cvs2svn" -a \
             -z "`git branch --contains $rev`" ]; then
                git diff-tree --diff-filter=ACMRTUXB --quiet $rev~ $rev && \
                        git update-ref "$tagname" $rev~
        fi
done

git show-ref --heads | grep -E 'unlabeled-[0-9.]+$' | \
while read rev branchname; do
        if [ -z "$name" ]; then
                git update-ref -d "$branchname" $rev
        else
                new_branchname=`echo $branchname | sed -e "s/unlabeled-\([0-9.]\+\)$/${name}-\1/"`
                if [ "$branchname" != "$new_branchname" ]; then
                        git update-ref "$new_branchname" $rev "" && git update-ref -d "$branchname" $rev
                fi
        fi
done
