#!/usr/bin/perl

use warnings;
use strict;

use FindBin;
use lib $FindBin::Bin.'/../lib';

my $lib_to_test = 'probot::session::manager';
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


my $session_manager = "$lib_to_test"->new();
POE::Kernel->run();

exit 0;
