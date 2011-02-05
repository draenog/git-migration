#!/bin/sh
# if any of the chars matched, iconv latin2->utf8, otherwise just print it
# IMPORTANT: this file needs to be latin2 encoded
# this script should be used as filter to "git-filter-branch":
# $ git-filter-branch --msg-filter msgconv.sh

s=$(cat)
if echo "$s" | grep --color '[±æê³ñó¶¼¿¡ÆÊ£ÑÓ¦¬¯]'; then
	echo "$s"  | iconv -flatin2 -tutf8
else
	echo "$s"
fi
