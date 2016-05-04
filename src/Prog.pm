package Prog;
use strict;
use warnings;
use Scalar::Util qw(looks_like_number);
use Carp qw(cluck);

use Moose;
use vars qw/$VERSION/;

has 'version' => (
	is => 'ro',
	isa => 'Str',
	default => '##psim#1.0.a##',
    );

has 'file' => (
	is => 'ro',
	isa => 'Str',
	writer => 'set_file',
	trigger => \&read_file,
    );

has 'lines' => (
	is => 'ro',
	isa => 'HashRef[ArrayRef[Int]]',
	default => sub { {} },
    );

has 'sorted_addrs' => (
	is => 'ro',
	isa => 'ArrayRef[Int]',
	writer => '_set_sorted_addrs',
	default => sub { [ ] },
    );

has 'loop_pairs' => (
	is => 'ro',
	isa => 'ArrayRef[ArrayRef[Int]]',
	writer => '_set_loop_pairs',
	default => sub { [ ] },
    );

has 'instruction_count' => (
	is => 'ro',
	isa => 'Int',
	default => 0,
	writer => '_set_instruction_count',
    );

#
# Adds or updates an instruction
# Usage:
#	$prog->set_instr(<addr> => [ ]);
#
# The array reference is encoded as
#	[ <addr>, <iter>, <addr>> ]
#
# The first address is the "next if true" one, followed by the number
# of permissible loop iterations (which may be 0 for no loop
# paticipation). The iteration number is *always* required.
#
# The second address, iter pair is for the "next if false" case. It
# may be omitted. If the first pair is ommitted, the instruction is a
# program terminator.
#
sub set_instr {
	my $self = shift;
	my $href = $self->lines();
	my %args = @_;

	while (my ($k, $v) = each %args) {
		my $c = scalar(@$v);
		if ( $c < 0 || $c == 1 || $c > 3) {
			die ("Instruction must have 0, 2 or 3 components");
		}
		my @array;
		confess("$k is not an address") if !looks_like_number($k);
		$k = sprintf("%d", $k);
		confess("$k is <= 0") if $k <= 0;
		foreach my $val (@$v) {
			my $d = sprintf("%d", $val);
			if (!defined($d)) {
				die ("$val is not a number");
			}
			push @array, $d;
		}
		$href->{$k} = \@array;
	}
	$self->update_sorted_addrs();
	$self->update_loop_pairs();
};

#
# Reads a into the program lines
#
sub read_file {
	my ($handle, $self, $file, $version, $line);
	$self = shift;
	$version = $self->version();

	$file = $self->file();
	open($handle, "<", $file) or die "Could not open $file";

	$line = <$handle>; chomp($line);
	if ($line !~ /^$version$/) {
		die ("Incompatible version $line aborting");
	}
	while ($line = <$handle>) {
		my $orig = $line;
		chomp($line);
		$line =~ s/#.*$//g; # Remove comments
		$line =~ s/\s+/ /g; # Remove extra spaces
		if ($line =~ /^\s{0,1}$/) {
			# Skip blank lines
			next;
		}
		my @parts = split('\|', $line);
		my ($addr, $tnext, $fnext) = @parts;
		my @args;
		if ($tnext) {
			my $iter = 0;
			if ($tnext =~ s/\(\s*(\d+)\s*\)//) {			
				$iter = $1;
			}
			push @args, $tnext, $iter;
		}
		if ($fnext) {
			push @args, $fnext;
		}
		foreach my $v (@args) {
			die("Bad line in input file\n>>>> $orig")
			    if !looks_like_number($v);
		}
		$self->set_instr($addr => \@args);
	}
	
	close($handle);
}

#
# Prints the program to STDOUT by default
#
sub print {
	my ($self, $handle);

	($self, $handle) = @_;
	if (!defined($handle)) {
		open($handle, ">-");
	}
	print $handle "#Number of Instructions: "
	    . $self->instruction_count . "\n";

	print $handle "#ADDR |T NEXT (ITERS)|F NEXT\n";
	my $format = "%-6d|  %-4d (%4d) |  %-4d\n";
	my @keys = keys(%{$self->lines()});
	for my $key (@{$self->sorted_addrs()}) {
		my $values = $self->lines()->{$key};
		for (0..2) {
			$values->[$_] = 0 if !defined($values->[$_]);
		}
		printf $handle ($format, $key, @$values);
	}
}

#
# Updates the sorted addresses
#
sub update_sorted_addrs {
	my $self = shift;

	my @keys = sort {$a <=> $b} (keys(%{$self->lines()}));
	$self->_set_sorted_addrs(\@keys);
	$self->_set_instruction_count(scalar(@keys));
}

#
# Call update_sorted_addrs() before
#
sub update_loop_pairs {
	my $self = shift;
	my @loop_pairs;

	foreach my $a (@{$self->sorted_addrs()}) {
		my ($parms, $loops, $loope);
		$parms = $self->lines()->{$a};
		if ($parms->[1] != 0) {
			$loops = $parms->[0];
			$loope = $a;
			push @loop_pairs, [$loops, $loope];
		}
	}
	$self->_set_loop_pairs(\@loop_pairs);
}	

#
#  Returns the instructino at $addr
#			
sub get_instr {
	my ($self, $addr);
	($self, $addr) = @_;

	return ($addr, $self->lines()->{$addr});
}

no Moose;
__PACKAGE__->meta->make_immutable;

