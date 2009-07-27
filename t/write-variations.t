use strict;
use warnings;
use Test::More tests => 29021;

use IO::Coderef;
use IO::Handle;
use File::Temp qw/tempdir/;

our $test_write_dest;
our $failure_message;

our $tmpfile = tempdir(CLEANUP => 1) . "/testfile";


foreach my $use_syswrite (0, 1) {
    my @writecode = build_write_code($use_syswrite);
    foreach my $writecode1 (@writecode) {
        foreach my $writecode2 (@writecode) {
            run_test($writecode1, $writecode2);
        }
    }
}

sub run_test {
    my (@writecode) = @_;
    my $srccode = join "::", map {$_->{SrcCode}} @writecode;

    my $fh = IO::Coderef->new('>', \&writesub);
    local $test_write_dest = '';
    do_test_writes($fh, map {$_->{CodeRef}} @writecode);
    my $got = $test_write_dest;

    if ($failure_message) {
        fail("$srccode test bailed: iocode write: $failure_message");
        undef $failure_message;
        return;
    }

    # Check that the results are correct by applying the same sequence of
    # writes to a real file and comparing.
    open my $ref_fh, ">", $tmpfile;
    do_test_writes($ref_fh, map {$_->{CodeRef}} @writecode);
    close $ref_fh;
    open $ref_fh, "<", $tmpfile;
    my $want = do { local $/ ; <$ref_fh> };

    if ($failure_message) {
        fail("$srccode test bailed: real write: $failure_message");
        undef $failure_message;
        return;
    }

    is( $got, $want, "$srccode matched real file results" );
}

sub do_test_writes {
    my ($fh, @coderefs) = @_;

    foreach my $code (@coderefs) {
        $code->($fh);
    }
}

sub writesub {
    $test_write_dest .= $_[0];
}

sub build_write_code {
    my ($use_syswrite) = @_;

    my @writecode;

    if ($use_syswrite) {
        my $writecall_template = <<'ENDCODE';
            my $wrote = eval { __WRITECALL__ };
            if ($@) {
                $failure_message = "died within test: $@";
            } elsif (not defined $wrote) {
                $failure_message = "syswrite returned undef";
            }
ENDCODE
        my @write_src_code = (
            'syswrite $fh, ""',
            'syswrite $fh, "", 0',
            'syswrite $fh, "", 0, 0',
            'syswrite $fh, "123456", 0, 5',
            'syswrite $fh, "0"',
            'syswrite $fh, "abcdefg"',
            'syswrite $fh, "ABCDEFG", 2',
            'syswrite $fh, "qwertyz", 2, 2',
            'syswrite $fh, "QWERTYZ", 0, 2',
            'syswrite $fh, "QWERTYZ", 0, -2',
            'syswrite $fh, "fobabz8", 2, -4',
        );
        foreach my $short_code (@write_src_code) {
            my $long_code = $writecall_template;
            $long_code =~ s/__WRITECALL__/$short_code/;
            push @writecode, {
                SrcCode     => $short_code,
                FullSrcCode => $long_code,
            };
        }
    } else {
        my @src_code;
        my @printf_argsets = (
            q{''},
            q{'%s', ''},
            q{'%s', 'foo'},
            q{'%s', 0},
            q{0},
        );
        foreach my $as (@printf_argsets) {
            push @src_code, "printf \$fh $as", "\$fh->printf($as)";
        }
        my @print_argsets = (
            q{''},
            q{'', ''},
            q{0},
            q{0, 0},
            q{'foo', '', 'bar'},
        );
        foreach my $ors ('undef', "''", 0, "'foo'") {
            foreach my $ofs ('undef', "''", 0, "'bar'") {
                my $prefix = "local \$\\=$ors; local \$,=$ofs;";
                foreach my $as (@print_argsets) {
                    push @src_code, "$prefix print \$fh $as", "$prefix \$fh->print($as)";
                }
            }
        }
        @writecode = map { {SrcCode => $_} } @src_code;
    }

    foreach my $wc (@writecode) {
        $wc->{FullSrcCode} ||= $wc->{SrcCode};
        my $src = "sub { my \$fh = shift; $wc->{FullSrcCode} }";
        $wc->{CodeRef} = eval $src;
        die "eval [$src]: $@" if $@;
    }

    return @writecode;
}

