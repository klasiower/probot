#!/usr/bin/perl

# needs the following debian packages:
# libmoosex-poe-perl libnamespace-autoclean-perl

use warnings;
use strict;

use FindBin;
use lib $FindBin::Bin.'/../lib';

use JSON;

sub POE::Kernel::ASSERT_DEFAULT () { 1 }
sub POE::Kernel::ASSERT_EVENTS  () { 1 }
# sub POE::Kernel::TRACE_EVENTS   () { 1 }
# sub POE::Kernel::TRACE_DEFAULT  () { 1 }

use POE;

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
        'threads=s'             => \$opts{threads},
    );

    if (defined $opts{debug})               { $config->{debug}              = $opts{debug}              }
    if (defined $opts{verbose})             { $config->{verbose}            = $opts{verbose}            }
    if (defined $opts{help})                { $config->{help}               = $opts{help}               }
    if (defined $opts{threads})             { $config->{threads}            = $opts{threads}            }
}

sub debug   { $config->{debug}   && print STDERR  "[DBG] @_\n" }
sub verbose { $config->{verbose} && print STDERR "[VERB] @_\n" }
sub warn    {                       print STDERR "[WARN] @_\n" }
sub error   {                       print STDERR  "[ERR] @_\n" }

use probot;
my $probot = probot->new( name => 'probot' );

$poe_kernel->run();

exit 0;

