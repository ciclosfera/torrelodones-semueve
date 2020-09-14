#!/usr/bin/env perl
use Mojo::Base -strict, -signatures;

while (1) {
    my $out = `git pull 2>&1`;
    if ( $out =~ /files? changed/m ) {
        say `./app/builder.pl`;
        `git add .`;
        `git ci -m 'Rebuilt'`;
        `git push`;
    }
    else {
        say $out;
    }
    say "Waiting...";
    sleep 120;
}
