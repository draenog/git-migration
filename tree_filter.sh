first_line='# $Revision$, $Date$'
log_line='%define date	%(echo `LC_ALL="C" date +"%a %b %d %Y"`)'

find -name \*.spec |
while read spec; do
    sed -ie "/^${first_line}$/d
             /^${log_line}$/,\$d" $spec
done
