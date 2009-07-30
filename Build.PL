use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'IO::Coderef',
    license             => 'perl',
    dist_author         => 'Dave Taylor <dave.taylor.cpan@gmail.com>',
    dist_version_from   => 'lib/IO/Coderef.pm',
    requires => {
        'Carp'   => 0,
        'Symbol' => 0,
    },
    build_requires => {
        'Fatal'       => 0,
        'Fcntl'       => 0,
        'File::Slurp' => 0,
        'File::Temp'  => 0,
        'IO::Handle'  => 0,
        'Test::More'  => 0,
    },
    add_to_cleanup      => [ 'IO::Coderef-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
