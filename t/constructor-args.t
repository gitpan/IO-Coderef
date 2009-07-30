use strict;
use warnings;
use Test::More;

use IO::Coderef;

my $fh_src = IO::Coderef->new('<', sub {});

my %constructor_source = (
    package => 'IO::Coderef',
    object  => $fh_src,
);

my @extra_constructor_args = (
    [],
    [[]],
    [{}],
    [0],
    [[0]],
    [[1,2,3]],
    [undef],
    [[undef]],
    [1, 2, 3],
    [undef, undef, undef],
    [{}, [], {}, \$fh_src],
);
my $consarg;

sub read_callback {
    is( flat(@_), flat(@$consarg), "flattened constructor args consistent" );
    return;
}

plan tests => 2 * (@extra_constructor_args + 10);

while ( my ($src_name, $src) = each %constructor_source ) {
    foreach my $c (@extra_constructor_args) {
        $consarg = $c;
        IO::Coderef->new("<", \&read_callback, @$consarg)->getc;
    }

    my $res;

    eval { $res = $src->new };
    like( $@, qr{^mode missing in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name no mode no sub" );

    eval { $res = $src->new(undef) };
    like( $@, qr{^mode missing in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name undef mode no sub" );

    eval { $res = $src->new('r') };
    like( $@, qr{^invalid mode "r" in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name invalid mode no sub" );

    eval { $res = $src->new(undef, undef) };
    like( $@, qr{^mode missing in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name undef mode undef sub" );

    eval { $res = $src->new('r', undef) };
    like( $@, qr{^invalid mode "r" in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name invalid mode undef sub" );

    eval { $res = $src->new('r', 'not a coderef') };
    like( $@, qr{^invalid mode "r" in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name invalid mode invalid sub" );

    eval { $res = $src->new('r', sub {}) };
    like( $@, qr{^invalid mode "r" in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name invalid mode valid sub" );

    eval { $res = $src->new('<') };
    like( $@, qr{^coderef missing in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name valid mode no sub" );

    eval { $res = $src->new('<', undef) };
    like( $@, qr{^coderef missing in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name valid mode undef sub" );

    eval { $res = $src->new('<', 1) };
    like( $@, qr{^non-coderef second argument in IO::Coderef::new at t/constructor-args\.t line \d+}, "$src_name valid mode invalid sub" );
}

sub flat {
    return join ",", map { defined() ? "{$_}" : "undef" } @ARGV;
}

