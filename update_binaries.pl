#!/usr/bin/perl -l

open(PATTERNS, "<binary_patterns") or die "File binary_patterns not found\n";
while(<PATTERNS>) {
    chomp;
    s/Attic\///;
    push @ARGV, glob "packages/*/$_";
}
close PATTERNS;

while(<>) {
    if(/;\s+state (\w+)/) {
        if($1 eq "dead") {
            unlink $ARGV;
            $ARGV=~s#^packages/##;
            print $ARGV;
        }
        close ARGV;
    }
}

