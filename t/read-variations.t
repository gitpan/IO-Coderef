use strict;
use warnings;
use Test::More tests => 123930;

use IO::Coderef;
use IO::Handle;

our $read_dest;

# the block size for the coderef to serve up data
my @test_block_sizes = (1, 2, 3, 10, 1_000_000);

my %data_strings = (
    empty    => '',
    0        => '0',
    1        => '1',
    newline  => "\n",
    newline2 => "\n\n",
    newline3 => "\n\n\n",
    null     => "\0",
    foo      => "foo",
    foon     => "foo\n",
    foobar   => "foo\nbar",
    foobarn  => "foo\nbar\n",
    para2    => "hello\n\n",
    para22   => "\n\nhello\n\n",
    para3    => "hello\n\n\n",
    para33   => "\n\n\nhello\n\n\n",
    para323  => "\n\n\nfoo\n\nbar\nbaz\n\n\n",
    allbytes => join('', map {chr} (0..255)),
);

foreach my $use_sysread (0, 1) {
    my @readcode = build_read_code($use_sysread, \@test_block_sizes);
    foreach my $str (keys %data_strings) {
        foreach my $seglen (@test_block_sizes) {
            foreach my $readcode1 (@readcode) {
                foreach my $readcode2 (@readcode) {
                    run_test($str, $seglen, $readcode1, $readcode2);
                }
            }
        }
    }
}

sub run_test {
    my ($str, $seglen, @readcode) = @_;
    my $srccode = join "::", map {$_->{SrcCode}} @readcode;

    my $segs = segment_input($data_strings{$str}, $seglen);
    my $fh = IO::Coderef->new('<', \&readsub, $segs);
    my $got_via_io_coderef = do_test_reads($fh, map {$_->{CodeRef}} @readcode);

    # Use perl's builtin stringio to determine what the results should be with
    # this combination of read ops.  Builtin stringio doesn't play nicely with
    # sysread, so avoid it.
    open my $stringio_fh, "<", \$data_strings{$str} or die "stringio open: $!";
    my $got_via_stringio = do_test_reads($stringio_fh, map {$_->{CodeRefNoSysread}} @readcode);

    is( $got_via_io_coderef, $got_via_stringio, "$srccode $str $seglen matched stringio results" );

    # In paragraph mode newlines can be discarded, otherwise the output should
    # match the input exactly.  
    unless (grep {$_->{ParaMode}} @readcode) {
        is( $got_via_io_coderef, $data_strings{$str}, "$srccode recreated $str ($seglen)" );
    }
}

sub do_test_reads {
    my ($fh, @coderefs) = @_;

    # We have a selection of bits of code to read bits of data.  Use each in
    # turn, repeating the last until EOF.
    my $dest = '';
    while (@coderefs > 1) {
        my $code = shift @coderefs;
        $code->($fh, \$dest);
    }
    1 while $coderefs[0]->($fh, \$dest);
    return $dest;
}

sub readsub {
    my $segs = shift;

    return unless @$segs;
    return shift @$segs;
}

sub segment_input {
    my ($str, $seglen) = @_;

    my @seg;
    while (length $str) {
        push @seg, substr $str, 0, $seglen, '';
    }
    return \@seg;
}

sub build_read_code {
    my ($use_sysread, $block_sizes) = @_;
    my $read = $use_sysread ? 'sysread' : 'read';

    my @readcode;

    unless ($use_sysread) {
        my @linewise_readcode = (
            '$_ = <$fh>; return unless defined; $$dest .= $_',
            '$_ = $fh->getline; return unless defined; $$dest .= $_',
            '$$dest .= join "", <$fh>; return',
            '$$dest .= join "", $fh->getlines; return',
        );
        @readcode = map( { {SrcCode => $_} }
            @linewise_readcode,
            map ({'local $/; '.$_} @linewise_readcode),
            map ({'local $/="oo"; '.$_} @linewise_readcode),
            '$_ = $fh->getc; return unless defined; $$dest .= $_',
        );
        push @readcode, map { {SrcCode => "local \$/=''; $_", ParaMode => 1} } @linewise_readcode;
    }

    my $readcall_template = <<'ENDCODE';
       my $got = __READCALL__;
       unless (defined $got) {
           $$dest = "*** FAIL: __READ__ returned undef ***";
           return;
       }
       $got or return;
       $$dest .= $_;
ENDCODE
    $readcall_template =~ s/__READ__/$read/g;
    foreach my $blocksize (@$block_sizes) {
        foreach my $readcall ("$read \$fh, \$_, $blocksize", "\$fh->$read(\$_, $blocksize)") {
            my $fullcode = $readcall_template;
            $fullcode =~ s/__READCALL__/$readcall/g;
            push @readcode, {SrcCode => $readcall, FullSrcCode => $fullcode};
        }
    }

    foreach my $rc (@readcode) {
        $rc->{FullSrcCode} ||= $rc->{SrcCode};
        my $src = "sub { my (\$fh, \$dest) = \@_ ; $rc->{FullSrcCode} ; return 1 }";
        $rc->{CodeRef} = $rc->{CodeRefNoSysread} = eval $src;
        die "eval [$src]: $@" if $@;
        if ($src =~ s/\bsysread\b/read/g) {
            $rc->{CodeRefNoSysread} = eval $src;
            die "eval [$src]: $@" if $@;
        }
    }

    return @readcode;
}

