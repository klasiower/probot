package probot::channel;

use warnings;
use strict;
use MooseX::POE;
use namespace::autoclean;
extends qw(probot::generic::poe);


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;

