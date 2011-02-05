#!/bin/sh
# Author: Elan Ruusamäe <glen@pld-linux.org>

set -e
export LC_ALL=C
ftpdir=$HOME/ftp
wwwdir=$HOME/www
CVSROOT=:pserver:cvs@cvs.pld-linux.org:/cvsroot
d=$-

# generate list of .specs on ftp. needs cvsnt client
# input: $CVSROOT = cvs server location
# output: $t/cvs.dirs = list of pkgs on cvs
cvs_pkgs() {
	set -$d
	[ -s cvs.raw ] || cvs -d $CVSROOT -Q ls -e packages > cvs.raw 2>/dev/null
	[ -s cvs.dirs ] || awk -F/ '$1 == "D" { print $2 } ' cvs.raw > cvs.dirs
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

# run git cvsimport on each package module
# input: $CVSROOT
# input: cvs.dirs = list of packages
# modifies: cvs.blacklist = list of problematic packages
git_import() {
	set -$d
	local pkg

	touch cvs.blacklist
	for pkg in ${@:-$(cat cvs.dirs)}; do
		# faster startup, skip existing ones for now
		test -d git-import/$pkg && continue

		grep -qF $pkg cvs.blacklist && continue
		# commits are mixed latin2 and utf8, do not force neither.
		# -c i18n.commitencoding=iso8859-2
		git cvsimport -d $CVSROOT -C git-import/$pkg -R -A cvs.users packages/$pkg || {
			rm -rf git-import/$pkg
			echo $pkg >> cvs.blacklist
		}
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

# setup bare git repo for each imported git repo
# input: cvs.dirs = list of packages
git_bare() {
	set -$d
	local pkg

	install -d git
	for pkg in ${@:-$(cat cvs.dirs)}; do
		grep -qF $pkg git.blacklist && continue

		test -d git-import/$pkg || continue
		test -d gitroot/$pkg && continue

		git clone --bare --template=templates git-import/$pkg gitroot/$pkg || echo $pkg >> git.blacklist
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
		grep -qF $pkg cvs.blacklist && continue
		[ -s git-import/.$pkg.shortlog ] && continue

		cd git-import/$pkg
		git shortlog -s -e > ../.$pkg.shortlog
		cd ../../
	done

	cat git-import/.*.shortlog > git.shortlog
}

# generate list of missing authors from all git modules
git_missingusers() {
	set -$d
	local pkg

	[ -f git.users ] && return
	git_shortlog

	sed -rne 's,.+<(.*)>,\1,p' git.shortlog | sort -u | grep -v @ > git.users.unknown
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

cvs_pkgs
cvs_users
git_import "$@"
git_missingusers
git_templates
git_bare "$@"
