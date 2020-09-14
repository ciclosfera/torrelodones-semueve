#!/usr/bin/env perl
use Mojo::Base -strict, -signatures;
use Mojo::File;
use Mojo::Template;
use Text::Markdown;
use Mojo::Util qw/encode/;
use DateTime;
use FindBin;

my $root_dir     = Mojo::File->new("$FindBin::Bin/../docs/");
my $template_dir = Mojo::File->new("$FindBin::Bin/templates/");
my $content_dir  = Mojo::File->new("$FindBin::Bin/../content/");
my $images_dir   = $content_dir->child('image/');

my $events     = read_source('event');
my $pages      = read_source('page');
my $expositors = read_source('expositor');

build_events($events, $expositors);
build_expositors($expositors);
build_pages($pages, $expositors);
build_home($events, $expositors);

sub build_home($events, $expositors) {
    my $dest     = $root_dir->child('index.html');
    my $template = get_template('home');
    say 'Building home';

    my $data = { events => $events, expositors => $expositors };
    $events->sort(sub{ $a->{meta}{start_at} <=> $b->{meta}{start_at} })->each(sub($ev, $idx){
        $data->{days}{$ev->{meta}{start_at}->dmy}{date} ||= $ev->{meta}{start_at}->clone;
        push $data->{days}{$ev->{meta}{start_at}->dmy}{events}->@*, $ev;
    });
    $data->{days} = [ sort { $a->{date} <=> $b->{date} } values $data->{days}->%* ];

    $dest->spurt(encode 'UTF8', $template->process($data));
}

sub build_events($events, $expositors) {
    say 'Building events:';
    my $template = get_template('event');
    $events->each(sub($e, $idx){
        my $dest_dir = $root_dir->child('event', $e->{slug});
        $dest_dir->make_path;

        my $dest = $dest_dir->child('index.html');
        say ' - ', $e->{slug};
        $dest->spurt(encode 'UTF8', $template->process({ %$e, expositors => $expositors }));
    });
}

sub build_pages($pages, $expositors) {
    say 'Building pages:';
    my $template = get_template('page');
    $pages->each(sub($e, $idx){
        my $dest_dir = $root_dir->child($e->{slug});
        $dest_dir->make_path;

        my $dest = $dest_dir->child('index.html');
        say ' - ', $e->{slug};
        $dest->spurt(encode 'UTF8', $template->process({ %$e, expositors => $expositors }));
    });
}

sub build_expositors($expositors) {
    say 'Building expositors';
    my $template = get_template('expositor');
    $expositors->each(sub($e, $idx){
        my $dest_dir = $root_dir->child('expo', $e->{slug});
        $dest_dir->make_path;

        my $dest = $dest_dir->child('index.html');
        say ' - ', $e->{slug};
        $e->{products} ||= [];
        $dest->spurt(encode 'UTF8', $template->process({ %$e, expositors => $expositors }));
    });
}

sub get_template($name) {
    my $mt = Mojo::Template->new(vars => 1);
    my $fh = $template_dir->child("$name.html.ep")->open('<:encoding(UTF-8)');
    my $data = join "", <$fh>;
    $mt->parse($data);
    $mt;
}

sub read_source($type) {
    my $dir = $content_dir->child($type . '/');
    $dir->list->map(sub($file){ read_content($file, $type) });
}

sub read_content($file, $type) {
    my $out = { slug => $file->basename, type => $type };
    $out->{slug} =~ s/\..+$//;


    my $fh = $file->open('<:encoding(UTF-8)');
    my $buf = {};
    my $phase = 'meta';
    while ( my $line = <$fh> ) {
        if ( $phase eq 'meta' && $line =~ /([^\s:]+)\s*:\s*(.+?)\s*$/ ) {
            $out->{$phase}{lc($1)} = $2;
        }
        elsif ( $phase eq 'meta' && $line =~ /^\s*\-{3,4}\s*$/ ) {
            $phase = 'src';
        }
        elsif ( $line =~ /^\s*\-\-([a-z]+)\-\-\s*$/i ) {
            push($out->{$phase}->@*, $buf) if %$buf;
            $phase = lc($1);
        }
        elsif ( $phase eq 'src' ) {
            $out->{$phase} .= "$line\n";
        }
        elsif ( $phase ne 'meta' ) {
            if ( $line =~ /([^\s:]+)\s*:\s*(.+?)\s*$/ ) {
                $buf->{$1} = $2;
            }
            elsif ( $line =~ /^\s*$/ ) {
                push($out->{$phase}->@*, $buf) if %$buf;
                $buf = {};
            }
        }
        else {
            say STDERR "Skipped line on $file: $line";
        }
    }
    push($out->{$phase}->@*, $buf) if %$buf;

    if ( exists $out->{meta}{at} && $out->{meta}{at} =~ m|(\d+)/(\d+)/(\d{4})\s+(\d+):(\d+)| ) {
        $out->{meta}{start_at} = DateTime->new(
            day       => $1,
            month     => $2,
            year      => $3,
            hour      => $4,
            minute    => $5,
            time_zone => 'Europe/Madrid',
            locale    => 'es'
        );

        if ( my $dur = exists $out->{meta}{duration} && $out->{meta}{duration} ) {
            $out->{meta}{end_at} = $out->{meta}{start_at}->clone->add( minutes => $dur );
        }
    }

    $out->{body} = Text::Markdown->new->markdown( $out->{src} );

    $out;
}
