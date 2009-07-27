use strict;
use warnings;
use Test::More;
use File::Temp qw/tempfile/;
use Fatal qw/open close unlink/;

use IO::Coderef;

$SIG{__WARN__} = sub {
    my $warning = shift;
    warn $warning unless $warning =~ /stat\(\) on unopened filehandle/i;
};

eval 'use File::Copy qw/copy/';
plan skip_all => 'File::Copy required' if $@;

plan tests => 5;

my $test_data = "foo\n" x 100;

my $line = 0;
my $coderef_read_fh = IO::Coderef->new('<', sub {
    return if $line++ >= 100;
    return "foo\n";
});

my $got_close = 0;
my $got_data = '';
my $coderef_write_fh = IO::Coderef->new('>', sub {
    my $buf = shift;
    if (length $buf) {
        $got_close and die "write after close";
        $got_data .= $buf;
    } else {
        ++$got_close;
    }
});

my ($tmp_fh, $tmp_file) = tempfile();
close $tmp_fh;
unlink $tmp_file;

ok( copy($coderef_read_fh, $tmp_file), "copy coderef->realfile succeeded" );
open $tmp_fh, "<", $tmp_file;
my $copy_got = do { local $/ ; <$tmp_fh> };
is( $copy_got, $test_data, "copy coderef->realfile copied correct data" );

ok( copy($tmp_file, $coderef_write_fh), "copy realfile->coderef succeeded" );
close $coderef_write_fh;
is( $got_close, 1, "got close on fh" );
is( $got_data, $test_data, "copy realfile->coderef copied correct data" );

close $tmp_fh;
unlink $tmp_file;

