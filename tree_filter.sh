first_line='# \$Revision\$, \$Date\$'
changelog_line='%changelog'
define_date_line='%define[\t ]*date[\t ]*.*'

find -name '*.spec' |
while read spec; do
    sed -i -e "
		/^${first_line}$/d
		/^${define_date_line}$/,\$d
	" $spec

    sed -i -e "
		# kill last empty line(s)
		\${/^\$/d}
	" $spec
done
