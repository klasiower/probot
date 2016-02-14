package probot::session::generic;

use warnings;
use strict;
use MooseX::POE;

use namespace::autoclean;
extends qw(probot::generic::poe);

# has socket => (
#     # isa         => 'IO::Socket',
#     isa         => 'Maybe[GlobRef]',
#     is          => 'rw',
#     required    => 1,
# );
# 
# has wheel => (
#     isa     => 'Maybe[POE::Wheel::ReadWrite]',
#     is      => 'rw',
# );
# 
# has remote_ip => (
#     isa         => 'Str',
#     is          => 'ro',
#     required    => 1,
# );
# 
# has remote_port => (
#     isa         => 'Num',
#     is          => 'ro',
#     required    => 1,
# );
# 
# after ev_started => sub {
#     my ($self, $kernel) = @_[OBJECT, KERNEL];
# 
# };
# 
# sub shutdown {
#     my ($self) = @_;
#     my $wheel_id;  if (defined $self->wheel) { $wheel_id = $self->wheel->ID }
#     $self->verbose(sprintf('[shutdown][%s:%s] wheel_id:%s',
#         $self->remote_ip, $self->remote_port, ($wheel_id // ''),
#     ));
#     $self->socket(undef);
#     $self->wheel(undef);
# }
# 
# before ev_shutdown => sub {
#     my ($self, $kernel) = @_[OBJECT, KERNEL];
#     $self->shutdown();
# };


__PACKAGE__->meta->make_immutable;
no MooseX::POE;

1;
