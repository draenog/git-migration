#!/bin/sh
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e
export LC_ALL=C
ftpdir=$HOME/ftp
wwwdir=$HOME/www
CVSROOT=:pserver:cvs@cvs.pld-linux.org:/cvsroot
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
	> $logfile
	rsync -av rsync://cvs.pld-linux.org/cvs/packages/ packages/ \
		--log-file=$logfile --log-file-format='changes=%i name=%n' \
		--include=**/*,v --include=**/ --exclude=*

	# parse rsync log
	# we want "^.f" - any file change
	grep 'changes=.f' $logfile | sed -rne 's/.*name=([^/]+).*/\1/p' | sort -u > cvs.pkgs

	touch cvs.rsync
}

# generate list of .specs on ftp. needs cvsnt client
# input: $CVSROOT = cvs server location
# output: $t/cvs.dirs = list of pkgs on cvs
cvs_dirs() {
	set -$d
	[ -s cvs.raw ] || cvs -d $CVSROOT -Q ls -e packages > cvs.raw 2>/dev/null
	[ -s cvs.dirs ] || awk -F/ '$1 == "D" { print $2 } ' cvs.raw > cvs.dirs
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
	'  cvs.userlog > cvs.users
}

# run cvs2git on each package module
# input: cvs.pkgs = list of packages
# conflicts with import_git-cvsimport
import_cvs2git() {
	set -$d
	local pkg gitdir=git-import

	[ -x /usr/bin/cvs2git ] || {
		echo >&2 "cvs2git missing, install cvs2svn package"
		exit 1
	}

	cvs_pkgs

	touch cvs.blacklist
	install -d $gitdir cvs2svn-tmp
	for pkg in ${@:-$(cat cvs.pkgs)}; do
		grep -qF $pkg cvs.blacklist && continue

		# can't resume, drop old efforts
		rm -rf $gitdir/$pkg

		export GIT_DIR=$gitdir/$pkg
		git init
		CVS_REPO=packages/$pkg cvs2git --options=cvs2git.options
		git fast-import --export-marks=cvs2svn-tmp/cvs2git.marks < cvs2svn-tmp/git-blob.dat
		git fast-import --import-marks=cvs2svn-tmp/cvs2git.marks < cvs2svn-tmp/git-dump.dat
		./cvs2git_fixes.sh $pkg
		# add origin remote
		git remote add origin git@github.com:pld-linux/$pkg.git
		# do some space
		git repack -a -d
		> $GIT_DIR/description
		rm -f $GIT_DIR/hooks/*
		unset GIT_DIR
	done
}

# run git cvsimport on each package module
# input: $CVSROOT
# input: cvs.pkgs = list of packages
# modifies: cvs.blacklist = list of problematic packages
import_git-cvsimport() {
	set -$d
	local pkg

	cvs_pkgs
	cvs_users

	touch cvs.blacklist
	install -d git-import
	for pkg in ${@:-$(cat cvs.pkgs)}; do
		grep -qF $pkg cvs.blacklist && continue

		# faster startup, skip existing ones for now
#		test -d git-import/$pkg && continue

		git cvsimport -d $CVSROOT -C git-import/$pkg -R -A cvs.users packages/$pkg || {
			rm -rf git-import/$pkg
			echo $pkg >> cvs.blacklist
			exit 1
		}
	done
}

# rewrite commit logs
# historically old commits were in latin2, detect those and convert to utf8
git_rewrite_commitlogs() {
	set -$d
	local msgconv=$(pwd)/msgconv.sh

	cvs_pkgs
	for pkg in ${@:-$(cat cvs.pkgs)}; do
		grep -qF $pkg cvs.blacklist && continue

		cd gitroot/$pkg
		git filter-branch --msg-filter "$msgconv" --tag-name-filter cat -- --all
		cd ../../
	done
}

# create template dir of git_bare
# we copy system template dir and remove samples from it
git_templates() {
	set -$d
	[ -d templates ] && return
	cp -a /usr/share/git-core/templates templates
	find templates -name '*.sample' | xargs rm
	# clear
	> templates/info/exclude
	# clear
	> templates/description
}

git_dirs() {
	[ -s git.dirs ] || ls -1 git-import > git.dirs
}

# setup bare git repo for each imported git repo
# i.e repos that should be used for serving git service
# input: cvs.pkgs = list of packages
git_bare() {
	set -$d
	local pkg gitdir=git-import

	git_templates
	cvs_pkgs
	install -d git
	for pkg in ${@:-$(cat cvs.pkgs)}; do
		grep -qF $pkg cvs.blacklist && continue
		grep -qF $pkg git.blacklist && continue

		test -d $gitdir/$pkg

		rm -rf gitroot/$pkg
		git clone --bare --mirror --template=templates git-import/$pkg gitroot/$pkg || echo $pkg >> git.blacklist
	done
}

# generate shortlog for each package
git_shortlog() {
	set -$d
	local pkg

	[ ! -f git.shortlog ] || return

	git_dirs
	for pkg in $(cat git.dirs); do
		grep -qF $pkg cvs.blacklist && continue
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
		grep -qF $pkg cvs.blacklist && continue

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


cvs_rsync

#import_git-cvsimport "$@"
import_cvs2git "$@"
#git_rewrite_commitlogs "$@"

# missingusers needed only to analyze missing users file
#git_missingusers

# do not need bare repo, if all we do is push to github
#git_bare "$@"
