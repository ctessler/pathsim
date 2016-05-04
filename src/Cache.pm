package Cache;
use strict;
use warnings;
use Moose;

has 'cache' => (
	traits => ['Array'],
	is => 'rw',
	isa => 'ArrayRef[Int]',
	default => sub { [] },
	handles => {
		_set_line => 'set',
		get_line => 'get',
		_clear => 'clear'
	},
    );

has 'bundle' => (
	traits => ['Array'],
	is => 'ro',
	isa => 'ArrayRef[Int]',
	default => sub { [] },
	handles => {
		set_bundle => 'set',
		get_bundle => 'get',
	},
    );
		

has 'lines' => (
	is => 'ro',
	isa => 'Num',
	required => 1,
    );

has 'conflicts' => (
	traits => ['Counter'],
	is => 'ro',
	isa => 'Int',
	default => 0,
	handles => {
		_inc_cfc => 'inc',
		_rst_cfc => 'reset',
	}
    );

#
# Maps a program adress to a cache line
#
# $line = $cache->map($address);
sub map {
	my ($self, $addr);
	($self, $addr) = @_;

	return $addr % $self->lines();
}	

#
# Access of an address, will increment the conflict counter if the
# access is a miss in the cache.
#
# returns 1 if the access is a miss (and therefore a load), 0 on hit
#
# $cache->access($line);
#
sub access {
	my ($self, $line);
	($self, $line) = @_;

	my $m = $self->map($line);
	my $v = $self->get_line($m);
	
	if (!defined($v) || ($v != $line)) {
		# New value, not cached
		$self->_set_line($m, $line);
		$self->_inc_cfc();
		return 1;
	}
	return 0;
}

#
# clears the cache and resets the counters
#
sub rst {
	my $self = shift;
	$self->_clear();
	$self->_rst_cfc();
}
	
	    

no Moose;
__PACKAGE__->meta->make_immutable;

