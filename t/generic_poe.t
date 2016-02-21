#!/usr/bin/perl

{
    use warnings;
    use strict;

    sub POE::Kernel::ASSERT_DEFAULT () { 1 }
    sub POE::Kernel::ASSERT_EVENTS  () { 1 }
    # sub POE::Kernel::TRACE_EVENTS   () { 1 }
    # sub POE::Kernel::TRACE_DEFAULT  () { 1 }

    use FindBin;
    use lib $FindBin::Bin.'/../lib';
    use lib $FindBin::Bin.'/../t/lib';
    use test_generic_poe;

    use MooseX::POE;
    use namespace::autoclean;

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

    my $mysession = test_generic_poe->new({ name => 'mysession' });
    $DB::single = 1;
    $mysession->verbose('i am alive');
    $poe_kernel->run();
    $mysession->verbose('poe_kernel stopped');


    exit 0;

    no MooseX::POE;
}
