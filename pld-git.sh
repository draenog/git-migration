#!/bin/sh
# vim:noet:ts=4:sw=4
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e
export LC_ALL=C
gitdir="git-import"
CVSROOT=:pserver:cvs@cvs.pld-linux.org:/cvsroot
LOCAL_CVS2GIT="yes"
REMOVE_BINARIES="no"
d=$-

# get a copy of packages repo for faster local processing
# modifies: sets up $CVSROOT to be local if used
# creates: cvs.pkgs for packages being modified
cvs_rsync() {
	set -$d

	CVSROOT=$(pwd)

	[ ! -f cvs.rsync ] || return 0
	# sync only *,v files and dirs
	local logfile=rsync.log
	local exclude_pattern
	[ "$REMOVE_BINARIES" = "yes" ] &&
		exclude_pattern='--exclude=*.gz,v --exclude=*.bz2,v --exclude=*.tgz,v --exclude=*.Z,v --exclude=gap4r2.zoo,v --exclude=*.ogg,v --exclude=*.pdf,v --exclude=*.rpm,v --exclude=*.bz,v --exclude=*.mp3,v --exclude=*.bin,v --exclude=*.png,v --exclude=*.mpg,v --exclude=*.tbz2,v --exclude=*.tar,v --exclude=*.xpm,v --exclude=*.xpi,v'
	> $logfile
	rsync -av rsync://cvs.pld-linux.org/cvs/packages/ packages/ \
		--log-file=$logfile --log-file-format='changes=%i name=%n' \
		$exclude_pattern --include=**/*,v --include=**/ --exclude=* --delete --delete-excluded

	# parse rsync log
	# we want "^.f" - any file change
	grep 'changes=.f' $logfile | sed -rne 's/.*name=([^/]+)\/.*/\1/p' | sort -u > cvs.pkgs

	touch cvs.rsync
}

# generate list of .specs on ftp. needs cvsnt client
# input: $CVSROOT = cvs server location
# output: $t/cvs.dirs = list of pkgs on cvs
cvs_dirs() {
	set -$d

	if [ -d "$CVSROOT" ]; then
		local pkg
		for pkg in $CVSROOT/packages/*/; do
			pkg=${pkg%/}
			pkg=${pkg##*/}
			# skip fp
			[ "$pkg" = "CVS" ] && continue
			echo $pkg
		done > cvs.dirs
	else
		[ -s cvs.raw ] || cvs -d $CVSROOT -Q ls -e packages > cvs.raw 2>/dev/null
		[ -s cvs.dirs ] || awk -F/ '$1 == "D" { print $2 } ' cvs.raw > cvs.dirs
	fi
}

# expect cvs.pkgs, can be created by rsync.log of looking packages/ in cvs
cvs_pkgs() {
	set -$d

	[ -f cvs.pkgs ] && return
	cvs_dirs
	cat cvs.dirs > cvs.pkgs
}

# generate userlist for git import
# input: $CVSROOT = cvs server location
# output: cvs.userlog = log of users file
# output: cvs.users = user (authors) map for import
cvs_users() {
	set -$d
	[ ! -s cvs.users ] || return 0

	# iterate over each version to get list of all emails, we prefer most recent entry
	if [ ! -s cvs.userlog ]; then
		> cvs.userlog
		local rev revs=$(cvs -d $CVSROOT rlog CVSROOT/users | awk '/^revision /{print $2}')
		for rev in $revs; do
			cvs -d $CVSROOT co -r $rev CVSROOT/users
			cat CVSROOT/users >> cvs.userlog
		done
	fi
	perl -ne '
		chomp;
		my($login, $email, $name) = split(/:/);
		# skip notes
		next if $login =~ /^(?:vim|README|)$/;
		# skip aliases
		next if $email =~ /,/;
		$email = "$login\@pld-linux.org";
		printf("%s=%s <%s>\n", $login, $name, $email) unless $seen{$login};
		$seen{$login}++;
	' cvs.userlog > cvs.users
}

# run cvs2git on each package module
# input: cvs.pkgs = list of packages
# conflicts with import_git-cvsimport
import_cvs2git() {
	set -$d
	local pkg
	local tree_filter=$(pwd)/tree_filter.sh

	command -v cvs2git || {
		echo >&2 "cvs2git missing, install cvs2svn package"
		exit 1
	}
	[ -d .git-rewrite ] && {
		echo >&2 ".git-rewrite exists; remove it if you want to continue"
		exit 1
	}

	cvs_pkgs

	touch cvs.blacklist
	install -d $gitdir cvs2svn-tmp
	for pkg in ${@:-$(cat cvs.pkgs)}; do
		grep -qxF $pkg cvs.blacklist && continue

		# can't resume, drop old efforts
		rm -rf $gitdir/${pkg}.git

		export GIT_DIR=$gitdir/${pkg}.git
		git init
		PYTHONPATH=$(pwd) CVS_REPO=packages/$pkg cvs2git --options=cvs2git.options || {
			rm -rf $GIT_DIR
			exit 1
		}
		git fast-import --export-marks=cvs2svn-tmp/cvs2git.marks < cvs2svn-tmp/git-blob.dat
		git fast-import --import-marks=cvs2svn-tmp/cvs2git.marks < cvs2svn-tmp/git-dump.dat
		./cvs2git_fixes.sh deadbranch

		# clear all refs
		git for-each-ref --format="%(refname)" refs/original/ | xargs -r -n 1 git update-ref -d
		git gc --prune=now

		# add origin remote
		git remote add origin git@github.com:pld-linux/$pkg.git
		# do some space
		git repack -a -d -f -F --window=250 --depth=250
		> $GIT_DIR/description
		rm -f $GIT_DIR/hooks/*

		unset GIT_DIR

		# remove from cvs.pkgs to mark it done (for this round)
		sed -i -e "/^$pkg\$/d" cvs.pkgs
	done

}

git_dirs() {
	[ -s git.dirs ] || ls -1 git-import > git.dirs
}

# generate shortlog for each package
git_shortlog() {
	set -$d
	local pkg

	[ ! -f git.shortlog ] || return

	git_dirs
	for pkg in $(cat git.dirs); do
		grep -qxF $pkg cvs.blacklist && continue
		[ -s git-import/.$pkg.shortlog ] && continue

		cd git-import/$pkg
		git shortlog -s -e > ../.$pkg.shortlog
		cd ../../
	done

	cat git-import/.*.shortlog > git.shortlog
}

git_authors() {
	set -$d
	local pkg

	[ ! -s git.authors ] || return

	git_dirs
	for pkg in $(cat git.dirs); do
		grep -qxF $pkg cvs.blacklist && continue

		cat git-import/$pkg/.git/cvs-authors || echo $pkg >> cvs.no-autor
	done | sort -u > git.authors
}

# generate list of missing authors from all git modules
git_missingusers() {
	set -$d
	local pkg

	[ -f git.users ] && return
	cvs_users
	git_authors

	sed -rne 's,.+<(.*)>,\1,p' git.authors | grep -v @ > git.users.unknown
	local user
	for user in $(cat git.users.unknown); do
		if ! grep -q "^$user=" cvs.users; then
			if ! grep -q "^$user" cvs.users.missing; then
				echo $user >> cvs.users.missing
			fi
		fi
	done
	touch git.users
}

clone_cvs2svn() {
	set -$d

	[ "$LOCAL_CVS2GIT" = "yes" ] || return 0
	if [ ! -x cvs2svn/cvs2git ]; then
		git clone -b PLD_conversion git://github.com/draenog/cvs2svn.git
	fi
	PATH=$(pwd)/cvs2svn:$PATH
}

clone_cvs2svn
cvs_rsync

#import_git-cvsimport "$@"
import_cvs2git "$@"

# missingusers needed only to analyze missing users file
#git_missingusers
