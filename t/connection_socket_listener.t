#!/usr/bin/perl

use warnings;
use strict;

use FindBin;
use lib $FindBin::Bin.'/../lib';
use lib $FindBin::Bin.'/../t/lib';

sub POE::Kernel::ASSERT_DEFAULT () { 1 }
sub POE::Kernel::ASSERT_EVENTS  () { 1 }
# sub POE::Kernel::TRACE_EVENTS   () { 1 }
# sub POE::Kernel::TRACE_DEFAULT  () { 1 }

use MooseX::POE;
use namespace::autoclean;

my $lib_to_test = 'test_connection_socket_listener';
eval "use $lib_to_test;"; if ($@) { die $@ }

my $config = {
    debug   => 1,
    verbose => 1,
};

use Getopt::Long;
{
    my %opts;
    my $result = Getopt::Long::GetOptions(
        'help'                  => \$opts{help},
        'debug'                 => \$opts{debug},
        'verbose'               => \$opts{verbose},
    );

    if (defined $opts{debug})               { $config->{debug}              = $opts{debug}              }
    if (defined $opts{verbose})             { $config->{verbose}            = $opts{verbose}            }
    if (defined $opts{help})                { $config->{help}               = $opts{help}               }
}

sub debug   { $config->{debug}   && print STDERR  "[DBG] @_\n" }
sub verbose { $config->{verbose} && print STDERR "[VERB] @_\n" }
sub warn    {                       print STDERR "[WARN] @_\n" }
sub error   {                       print STDERR  "[ERR] @_\n" }

my $mysession = test_connection_socket_listener->new({ name => 'mysession' });
$mysession->verbose('i am alive');
$poe_kernel->run();
$mysession->verbose('poe_kernel stopped');

exit 0;
