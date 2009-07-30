use strict;
use warnings;
use Test::More;

use IO::Coderef;

my @close_code = (
    'close $fh',
    '$fh->close',
    'close $fh ; close $fh',     
    'close $fh ; undef $fh',
);
my @write_data_sets = (
    [],
    ['q'],
    ['Q','W'],
);

plan tests => @close_code * @write_data_sets;

foreach my $write_data_set (@write_data_sets) {
    my $want = join ',', map {"{$_}"} @$write_data_set, '';
    foreach my $close_code (@close_code) {
        my @write;
        my $fh = IO::Coderef->new('>', sub { push @write, shift });
        foreach my $write_data (@$write_data_set) {
            print $fh $write_data;
        }
        eval $close_code;
        die $@ if $@;
        is( join(',', map {"{$_}"} @write), $want, "$want $close_code ok" );
    }
}

