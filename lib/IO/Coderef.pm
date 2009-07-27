package IO::Coderef;

use warnings;
use strict;

=head1 NAME

IO::Coderef - Emulate file interface for a code reference

=head1 VERSION

Version 0.91

=cut

our $VERSION = '0.91';

=head1 SYNOPSIS

C<IO::Coderef> provides an easy way to produce a phoney read-only filehandle that calls back to your own code when it needs data to satisfy a read. This is useful if you want to use a library module that expects to read data from a filehandle, but you want the data to come from some other source, and there is too much data to read it all into memory and use L<IO::String> or similar.

    use IO::Coderef;

    my $fh = IO::Coderef->new('<', sub { ... ; return $data });
    my $object = Some::Class->new_from_file($fh);

Similarly, IO::Coderef allows you to wrap up a coderef as a write-only filehandle, which you can pass to a library module that expects to write its output to a filehandle.

    my $fh = IO::Coderef->new('>', sub { my $data = shift ; ... });
    $object->dump_to_file($fh);


=head1 CONSTRUCTOR

=head2 C<new ( MODE, CODEREF [,ARG ...] )>

Returns a filehandle object encapsulating the coderef.

MODE must be either C<E<lt>> for a read-only filehandle or C<E<gt>> for a write-only filehandle.

For a read-only filehandle, the callback coderef will be invoked in a scalar context each time more data is required to satisfy a read. It must return some more input data (at least one byte) as a string. If there is no more data to be read, then the callback should return either C<undef> or the empty string. If ARG values were supplied to the constructor, then they will be passed to the callback each time it is invoked.

For a write-only filehandle, the callback will be invoked each time there is data to be written. The first argument will be the data as a string, which will always be at least one byte long. If ARG values were supplied to the constructor, then they will be passed as additional arguments to the callback. When the filehandle is closed, the callback will be invoked once with the empty string as its first argument.  

=head1 EXAMPLES

=over 4

=item Example 1

To generate a filehandle from which an infinite number of C<x> characters can be read:

=for test "ex1" begin

  my $fh = IO::Coderef->new('<', sub {"xxxxxxxxxxxxxxxxxxxxxxxxxxx"});

  my $x = $fh->getc;  # $x now contains "x"
  read $fh, $x, 5;    # $x now contains "xxxxx"

=for test "ex1" end

=item Example 2

A filehandle from which 1000 C<foo> lines can be read before EOF:

=for test "ex2" begin

  my $count = 0;
  my $fh = IO::Coderef->new('<', sub {
      return if ++$count > 1000; # EOF
      return "foo\n";
  });

  my $x = <$fh>;    # $x now contains "foo\n"
  read $fh, $x, 2;  # $x now contains "fo"
  read $fh, $x, 2;  # $x now contains "o\n"
  read $fh, $x, 20; # $x now contains "foo\nfoo\nfoo\nfoo\nfoo\n"
  my @foos = <$fh>; # @foos now contains ("foo\n") x 993

=for test "ex2" end

The example above uses a C<closure> (a special kind of anonymous sub, see L<http://perldoc.perl.org/perlfaq7.html#What's-a-closure?>) to allow the callback to keep track of how many lines it has returned. You don't have to use a closure if you don't want to, since C<IO::Coderef> will forward extra constructor arguments to the callback. This example could be re-written as:

=for test "ex2a" begin

  my $count = 0;
  my $fh = IO::Coderef->new('<', \&my_callback, \$count); 

  my $x = <$fh>;    # $x now contains "foo\n"
  read $fh, $x, 2;  # $x now contains "fo"
  read $fh, $x, 2;  # $x now contains "o\n"
  read $fh, $x, 20; # $x now contains "foo\nfoo\nfoo\nfoo\nfoo\n"
  my @foos = <$fh>; # @foos now contains ("foo\n") x 993

  sub my_callback {
      my $count_ref = shift;

      return if ++$$count_ref > 1000; # EOF
      return "foo\n";
  };

=for test "ex2a" end

=item Example 3

To generate a filehandle interface to data drawn from an SQL table:

=for test "ex3" begin

  my $sth = $dbh->prepare("SELECT ...");
  $sth->execute;
  my $fh = IO::Coderef->new('<', sub {
      my @row = $sth->fetchrow_array;
      return unless @row; # EOF
      return join(',', @row) . "\n";
  });

  # ...

=for test "ex3" end

=item Example 4

You want a filehandle to which data can be written, where the data is discarded but an exception is raised if the data includes the string C<foo>.

=for test "ex4" begin

  my $buf = '';
  my $fh = IO::Coderef->new('>', sub {
      $buf .= shift;
      die "foo written" if $buf =~ /foo/;

      if ($buf =~ /(fo?)\z/) {
          # Part way through a "foo", carry over to the next block.
          $buf = $1;
      } else {
          $buf = '';
      }
  });

=for test "ex4" end

=item Example 5

You have been given an object with a copy_data_out() method that takes a destination filehandle as an argument.  You don't want the data written to a file though, you want it split into 1024-byte blocks and inserted into an SQL database.

=for test "ex5" begin

  my $blocksize = 1024;
  my $sth = $dbh->prepare('INSERT ...');

  my $buf = '';
  my $fh = IO::Coderef->new('>', sub {
      $buf .= shift;
      while (length $buf >= $blocksize) {
          $sth->execute(substr $buf, 0, $blocksize, '');
      }
  });

  $thing->copy_data_out($fh);

  if (length $buf) {
      # There is a remainder of < $blocksize
      $sth->execute($buf);
  }

=for test "ex5" end

=back

=cut

use Symbol qw/gensym/;
use Carp;

sub new
{
    my $class = shift;
    my $self = bless gensym(), ref($class) || $class;
    tie *$self, $self;
    $self->open(@_);
    return $self;
}

sub open
{
    my $self = shift;
    return $self->new(@_) unless ref($self);

    my $mode = shift or croak "mode missing";
    my $code = shift or croak "coderef missing";
    ref $code eq "CODE" or croak "non-coderef argument";

    if ($mode eq '<') {
        *$self->{R} = 1;
    } elsif ($mode eq '>') {
        *$self->{W} = 1;
    } else {
        croak "invalid mode $mode";
    }

    my $buf = '';
    *$self->{Buf} = \$buf;

    if (@_) {
        my @args = @_;
        *$self->{Code} = sub { $code->(@_, @args) };
    } else {
        *$self->{Code} = $code;
    }
}

sub TIEHANDLE
{
    return $_[0] if ref($_[0]);
    my $class = shift;
    my $self = bless Symbol::gensym(), $class;
    $self->open(@_);
    return $self;
}

sub close
{
    my $self = shift;
    if (*$self->{W}) {
        *$self->{Code}('');
    }
    foreach my $key (qr/Code Buf Eof R W/) {
        delete *$self->{$key};
    }
    undef *$self if $] eq "5.008";  # cargo culted from IO::String
    return 1;
}

sub opened
{
    my $self = shift;
    return defined *$self->{Code};
}

sub binmode
{
    my $self = shift;
    return 1 unless @_;
    return 0;
}

sub getc
{
    my $self = shift;
    *$self->{R} or croak "getc on write-only IO::Coderef";
    my $buf;
    return $buf if $self->read($buf, 1);
    return undef;
}

sub ungetc
{
    my ($self, $char) = @_;
    *$self->{R} or croak "ungetc on write-only IO::Coderef";
    my $buf = *$self->{Buf};
    $$buf = $char . $$buf;
    return 1;
}

sub eof
{
    my $self = shift;
    return *$self->{Eof};
}

sub _doread {
    my $self = shift;

    return unless *$self->{Code};
    my $newbit = *$self->{Code}();
    if (defined $newbit and length $newbit) {
        ${*$self->{Buf}} .= $newbit;
        return 1;
    } else {
        delete *$self->{Code};
        return;
    }
}

sub getline
{
    my $self = shift;
    *$self->{R} or croak "getline on write-only IO::Coderef";
    return if *$self->{Eof};
    my $buf = *$self->{Buf};

    unless (defined $/) {  # slurp
        $self->_doread while *$self->{Code};
        *$self->{Eof} = 1;
        return $$buf;
    }

    my $rs = length $/ ? $/ : "\n\n";
    for (;;) {
        $$buf =~ s/^\n+// unless length $/; # In paragraph mode, discard extra newlines.
        my $pos = index $$buf, $rs;
        if ($pos >= 0) {
            if (length $/) {
                return substr $$buf, 0, $pos+length($rs), '';
            } else {
                # paragraph mode, discard extra trailing newlines
                my $ret = substr $$buf, 0, $pos+length($rs), '';
                $$buf =~ s/^\n+//;
                while (*$self->{Code} and length $$buf == 0) {
                    $self->_doread;
                    $$buf =~ s/^\n+//;
                }
                return $ret;
            }
        }
        if (*$self->{Code}) {
            $self->_doread;
        } else {
            # EOL not in buffer and no more data to come - the last line is missing its EOL.
            *$self->{Eof} = 1;
            return $$buf if length $$buf;
            return;
        }
    }
}

sub getlines
{
    die "getlines() called in scalar context\n" unless wantarray;
    my $self = shift;
    my($line, @lines);
    push(@lines, $line) while defined($line = $self->getline);
    return @lines;
}

sub READLINE
{
    goto &getlines if wantarray;
    goto &getline;
}

sub read
{
    my $self = shift;
    *$self->{R} or croak "read on write-only IO::Coderef";
    return 0 if *$self->{Eof};
    my $buf = *$self->{Buf};

    my $len = $_[1];
    $self->_doread while *$self->{Code} and $len > length $$buf;
    if ($len > length $$buf) {
        $len = length $$buf;
        *$self->{Eof} = 1;
    }

    if (@_ > 2) { # read offset
        substr($_[0],$_[2]) = substr($$buf, 0, $len, '');
    }
    else {
        $_[0] = substr($$buf, 0, $len, '');
    }
    return $len;
}

*sysread = \&read;
*syswrite = \&write;

sub stat {
    return;
}

sub FILENO {
    return undef;
}

sub blocking {
    my $self = shift;
    my $old = *$self->{blocking} || 0;
    *$self->{blocking} = shift if @_;
    return $old;
}

sub print
{
    my $self = shift;

    my $result;
    if (defined $\) {
        if (defined $,) {
            $result = $self->write(join($,, @_).$\);
        }
        else {
            $result = $self->write(join("",@_).$\);
        }
    }
    else {
        if (defined $,) {
            $result = $self->write(join($,, @_));
        }
        else {
            $result = $self->write(join("",@_));
        }
    }

    return unless defined $result;
    return 1;
}
*printflush = \*print;

sub printf
{
    my $self = shift;
    my $fmt = shift;
    my $result = $self->write(sprintf($fmt, @_));
    return unless defined $result;
    return 1;
}

sub write
{
    my $self = shift;
    *$self->{W} or croak "write on read-only IO::Coderef";

    my $slen = length($_[0]);
    my $len = $slen;
    my $off = 0;
    if (@_ > 1) {
        my $xlen = defined $_[1] ? $_[1] : 0;
        $len = $xlen if $xlen < $len;
        croak "Negative length" if $len < 0;
        if (@_ > 2) {
            $off = $_[2] || 0;
            croak "Offset outside string" if $off >= $slen and $off > 0;
            if ($off < 0) {
                $off += $slen;
                croak "Offset outside string" if $off < 0;
            }
            my $rem = $slen - $off;
            $len = $rem if $rem < $len;
        }
    }
    *$self->{Code}(substr $_[0], $off, $len) if $len;
    return $len;
}

my $notmuch = sub { return };

*fileno    = $notmuch;
*error     = $notmuch;
*clearerr  = $notmuch; 
*sync      = $notmuch;
*flush     = $notmuch;
*setbuf    = $notmuch;
*setvbuf   = $notmuch;

*untaint   = $notmuch;
*autoflush = $notmuch;
*fcntl     = $notmuch;
*ioctl     = $notmuch;

*GETC   = \&getc;
*PRINT  = \&print;
*PRINTF = \&printf;
*READ   = \&read;
*WRITE  = \&write;
*SEEK   = \&seek;
*TELL   = \&getpos;
*EOF    = \&eof;
*CLOSE  = \&close;
*BINMODE = \&binmode;

=head1 AUTHOR

Dave Taylor, C<< <dave.taylor.cpan at gmail.com> >>

=head1 BUGS AND LIMITATIONS

Fails to inter-operate with some library modules that read or write filehandles from within XS code. I am aware of the following specific cases, please let me know if you run into any others:

=over 4

=item C<Digest::MD5::addfile()>

=back

Please report any other bugs or feature requests to C<bug-io-coderef at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=IO::Coderef>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc IO::Coderef

You can also look for information at:

=over 4

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=IO::Coderef>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/IO::Coderef>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/IO::Coderef>

=item * Search CPAN

L<http://search.cpan.org/dist/IO::Coderef>

=back

=head1 SEE ALSO

L<IO::String>, L<IO::Stringy>, L<perlfunc/open>

=head1 ACKNOWLEDGEMENTS

Adapted from code in L<IO::String> by Gisle Aas.

=head1 COPYRIGHT & LICENSE

Copyright 1998-2005 Gisle Aas.

Copyright 2009 Dave Taylor, all rights reserved.


This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of IO::Coderef
