use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'IO::Coderef',
    license             => 'perl',
    dist_author         => 'Dave Taylor <dave.taylor.cpan@gmail.com>',
    dist_version_from   => 'lib/IO/Coderef.pm',
    build_requires => {
        'Test::More' => 0,
        'Fatal'      => 0,
        'File::Temp' => 0,
    },
    add_to_cleanup      => [ 'IO::Coderef-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
