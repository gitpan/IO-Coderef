use strict;
use warnings;
use Test::More;

use IO::Coderef;

eval 'use Digest::SHA';
plan skip_all => 'Digest::SHA required' if $@;

plan tests => 1;

my $block = "foo\n" x 1000;
my $lines = 0;
my $fh = IO::Coderef->new('<', sub {
    return if $lines++ >= 1000;
    return $block;
});

my $digest = Digest::SHA->new(256)->addfile($fh)->hexdigest;
is( $digest, "df1c1217e3256c67362044595cfe27918f43b25287721174c96726c078e3ecbe", "digest as expected" );

