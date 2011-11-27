#!/usr/bin/perl -l

$CVSROOT = shift @ARGV;
$PKGDIR="$CVSROOT/packages";

open(PATTERNS, "<binary_patterns") or die "File binary_patterns not found\n";
while(<PATTERNS>) {
    chomp;
    s/Attic\///;
    push @ARGV, glob "$PKGDIR/*/$_";
}
close PATTERNS;

while(<>) {
    if(/;\s+state (\w+)/) {
        if($1 eq "dead") {
            $ARGV=~s#^$PKGDIR/##;
            print $ARGV;
        }
        close ARGV;
    }
}

