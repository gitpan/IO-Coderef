use strict;
use warnings;
use Test::More;

use IO::Coderef;

my @readcode = grep {/\S/} split /\n/, <<'EOF';
$_ = <$fh>
my @foo = <$fh>
$_ = $fh->getline
my @foo = $fh->getlines
my $c = $fh->getc
$fh->ungetc(123)
read $fh, $_, 1024
sysread $fh, $_, 1024
EOF

my @writecode = grep {/\S/} split /\n/, <<'EOF';
$fh->print(4)
print $fh 4
$fh->printf(4)
printf $fh 4
syswrite $fh, "asdfsadf", 3
EOF

plan tests => 2*(@readcode + @writecode);

my $readonly  = IO::Coderef->new('<', sub {});
my $writeonly = IO::Coderef->new('>', sub {});

foreach my $code (@readcode) {
    my $fh = $readonly;
    eval $code;
    is( $@, '', "no croak for $code on read-only fh" );
    $fh = $writeonly;
    eval $code;
    like( $@, qr/^read on write-only IO::Coderef/, "croak for $code on write-only fh" );
}

foreach my $code (@writecode) {
    my $fh = $readonly;
    eval $code;
    like( $@, qr/^write on read-only IO::Coderef/, "croak for $code on read-only fh" );
    $fh = $writeonly;
    eval $code;
    is( $@, '', "no croak for $code on write-only fh" );
}

