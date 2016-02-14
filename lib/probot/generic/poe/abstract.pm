package probot::generic::poe::abstract;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
extends qw(probot::generic);


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
