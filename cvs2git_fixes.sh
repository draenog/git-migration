#!/bin/sh
# Script to fix git repo resulting from cvs2git conversion
# usage: cvs2git_fixes.sh <name>'
#
# It fixes following problems
#
# Branches which are no longer labelled can exist in CVS. cvs2git names them
# unlabeled-<revision>. The script changes "unlabeled" to specified name or
# deleted them if name is unspecified. Such a branch is also deleted if it is pointed
# by another tag or named branch.

# Often in CVS repo only changed file are tagged. In this case cvs2git produces
# superfluous commits to delete not tagged file. Here the tag in converted git
# repo is moved to the parent if the tagged commit:
# 1. was made by cvs2svn
# 2. the only change in the tree is deletion of files
# 3. the tag is not on any branch

name=$1
file_tags=$(mktemp tags.XXXXXX)
file_heads=$(mktemp heads.XXXXXX)

git show-ref --tags -d > $file_tags
git show-ref --heads > $file_heads

grep -E 'unlabeled-[0-9.]+$' $file_heads | \
while read rev branchname; do
        if [ -z "$name" ]; then
                git update-ref -d "$branchname" $rev
        else
            cat $file_tags
            if ! grep "^$rev" $file_heads $file_tags | grep -v refs/heads/unlabeled- ; then
                new_branchname=`echo $branchname | sed -e "s/refs\/heads\/unlabeled-\([0-9.]\+\)$/${name}-\1/"`
                git update-ref "refs/tags/$new_branchname" $rev "" && git update-ref -d "$branchname" $rev
            else
                git update-ref -d "$branchname" $rev
            fi
        fi
done

cat $file_tags | \
while read rev tagname; do
        if [ "`git show --format="%an" -s $rev`" = "cvs2svn" ]; then
                git diff-tree --diff-filter=ACMRTUXB --quiet $rev~ $rev && \
                        [ -z "`git branch --contains $rev`" ]  && \
                        git update-ref "$tagname" $rev~
        fi
done
rm $file_tags $file_heads

