#!/bin/sh
# Often in CVS repo only changed file are tagged. In this case cvs2git produces
# superfluouss commits to delete not tagged file. Here the tag in converted git 
# repo is moved to the parent if the tagged commit:
# 1. was made by cvs2svn
# 2. the only change in the tree is deletion of files


git show-ref --tags | \
while read rev tagname; do
        if [ "`git show --format="%an" --quiet $rev`" = "cvs2svn" -a \
             -z "`git branch --contains $rev`" ]; then
                git diff-tree --diff-filter=ACMRTUXB --quiet $rev~ $rev && \
                        git update-ref "$tagname" $rev~
        fi
done
        
        
