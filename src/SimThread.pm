package SimThread;
use strict;
use warnings;
use Moose;


has 'prog' => (
	is => 'ro',
	isa => 'Prog',
	writer => 'set_prog',
	trigger => \&reset
    );

has 'pc' => (
	is => 'ro',
	isa => 'Int',
	default => 0,
	writer => '_set_pc',
    );

has 'looping' => (
	is => 'ro',
	isa => 'Bool',
	default => 0,
	writer => '_set_looping',
    );

has 'loop_count' => (
	is => 'ro',
	isa => 'Int',
	default => 0,
	writer => '_set_loop_count',
    );

has 'loop_start' => (
	is => 'ro',
	isa => 'Int',
	default => 0,
	writer => '_set_loop_start'
    );

has 'exited' => (
	is => 'ro',
	isa => 'Bool',
	default => 0,
	writer => '_set_exited'
    );

has 'name' => (
	is => 'rw',
	isa => 'Str',
	default => 'nameless',
    );

has 'ins_count' => (
	traits => ['Counter'],
	is => 'ro',
	isa => 'Num',
	default => 0,
	handles => {
		inc_ins => 'inc',
		_reset_ins => 'reset',
	},
    );

has 'run_branch_decisions' => (
	traits => ['Array'],
	is => 'rw',
	isa => 'ArrayRef[Int]',
	default => sub { [ ] },
	handles => {
		pop_branch_decision => 'pop',
	},
    );

has 'run_loop_decisions' => (
	traits => ['Array'],
	is => 'rw',
	isa => 'ArrayRef[Int]',
	default => sub { [ ] },
	handles => {
		pop_loop_decision => 'pop',
	},
    );

sub reset {
	my $self = shift;
	$self->_set_pc($self->first_instr);
	$self->_set_looping(0);
	$self->_set_loop_count(0);
	$self->_set_loop_start(0);
	$self->_set_exited(0);
	$self->_reset_ins();
}

sub ready {
	my $self = shift;
	return 0 if $self->exited();
	return 1 if ($self->first_instr() != 0);
	return 0;
}

sub first_instr {
	my $self = shift;
	return $self->prog()->sorted_addrs()->[0];
}

#
# Moves forward one step, returns the address of the last instruction executed
#
sub step {
	my ($self, $addr, $tnext, $iters, $fnext);
	$self = shift;
	$addr = $self->pc();

	if ($addr == 0) {
		# 0 is the stopping address
		return 0;
	}
	
	($tnext, $iters, $fnext) = @{$self->prog()->lines()->{$addr}};
	my $next = $tnext;
	if ($iters == 0 && $fnext) {
		# There's a decision to be made
		my $true = $self->pop_branch_decision();
		if (!defined($true)) {
			warn "Random branch decision made";
			$true = int(rand(2));
		}
		$next = ($fnext, $tnext)[$true];
	}
		
	if ($iters > 0) {
		my $c;
		# Loop condition
		if ($self->loop_start() == $addr) {
			# Same loop
			$c = $self->loop_count();
		} else {
			# New loop
			$c = $self->pop_loop_decision();
			if (!defined($c)) {
				warn "Random loop iteration decision made";
				$c = int(rand($iters)) + 1;
			}
			$self->_set_loop_start($addr);
			$self->_set_looping(1);
		}
		if ($c > 0) {
			# More iterations available
			$self->_set_loop_count($c - 1);
		} else {
			$next = $fnext;
		}
		if ($next == $fnext) {
			# Loop terminated
			$self->_set_looping(0);
			$self->_set_loop_count(0);
			$self->_set_loop_start(0);
		}
	}
	if ($next == 0) {
		$self->_set_exited(1);
	}
	$self->inc_ins();
	$self->_set_pc($next);
	return $addr;
}

sub status {
	my $self = shift;
	if ($self->exited()) {
		return "pc:exited";
	}
	return sprintf("pc:%-4d loopstart:%-4d looping:%-1d loop_count:%-3d",
		       $self->pc(), $self->loop_start(), $self->looping(),
		       $self->loop_count());
}

no Moose;
__PACKAGE__->meta->make_immutable;

