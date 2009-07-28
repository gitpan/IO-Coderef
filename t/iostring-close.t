# This is t/close.t from IO::String 1.08, adapted to IO::Coderef.

use strict;
use warnings;
use Test::More tests => 6;
use IO::Coderef;

my $str = "abcd";
my $eof = 0;

my $destroyed = 0;

{
    package MyStr;
    @MyStr::ISA = qw(IO::Coderef);

    sub DESTROY {
        $destroyed++;
    }
}


my $rounds = 5;

for (1..$rounds) {
   $eof = 0;
   my $io = MyStr->new("<", sub { return if $eof++; return $str });
   is ( $io->getline, "abcd", "getline correct on round $_" );
   $io->close;
   undef($io);
}

is( $destroyed, $rounds, "destructor called $rounds times" );

