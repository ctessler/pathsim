#!/usr/bin/perl
use Getopt::Long;
use Pod::Usage;
use strict;
use warnings;
use Data::Dumper qw(Dumper);

BEGIN {
	use File::Basename;
	use File::Spec;
	use Cwd;

	# Local module search path modification
	my $file = Cwd::abs_path(__FILE__);
	$file = File::Spec->canonpath($file);
	my $dirname = dirname($file);

	push @INC, "$dirname"; # The directory of this file
}

use vars qw/$vout/;
use Math::Random;
use Prog;


# False entrypoint for perl
sub main {
	init_verbose();
	my (%args, $rv);
	$rv = parse_args(\%args);
	if (!$rv || $args{usage}) {
		pod2usage(1);
		return 1;
	}

	my ($branchr, $loopr, $blockl, $blockc, $loopi);
	($branchr, $loopr, $blockl, $blockc, $loopi) =
	    @args{'branches', 'loop', 'blocklen', 'blockcount', 'loopi'};

	my ($p, $addr);
	$p = new Prog;
	$addr = 1;

	my %c = (loop => 0, branch => 0);
	while ($blockc-- > 0) {
		print $vout "$blockc blocks remaining\n";
		my $count = add_block($p, start_addr => $addr, %args);
		$addr += $count;

		my $frac = rand();
		if ($frac <= $args{loop}) {
			# loop
			print $vout "Adding a loop at $addr\n";
			$addr = add_loop($p, $addr, $loopi);
			$c{loop}++;
			next;
		}
		if ($frac <= $args{branches}) {
			# branch
			print $vout "Adding a branch at $addr\n";
			$addr = add_branch($p, $addr, %args);
			$c{branch}++;
			next;
		}
	}
	# terminate
	$p->set_instr($addr => [0, 0, 0]);
	print $p->version() . "\n";
	print "#Branches: $c{branch} Loops: $c{loop}\n";
	$p->print();
	
	return 0;
}

#
# Parses the command line arguments
#
sub parse_args {
	my $href = shift;

	# Default values
	$href->{branches} = .2;
	$href->{loop} = .05;
	$href->{blocklen} = 15;
	$href->{blockcount} = 20;
	$href->{loopi} = 10;
	my $rv = GetOptions("b|branch-rate=f" => \$href->{branches},
			    "d|average-branch-distance=i" => \$href->{branchd},
			    "l|loop-rate=f" => \$href->{loop},
			    "a|average-block=i" => \$href->{blocklen},
			    "c|block-count=i" => \$href->{blockcount},
			    "i|max-loop=i" => \$href->{loopi},
			    "verbose" => \$href->{verbose}
	    );

	if (defined($href->{verbose})) {
		set_verbose();
		printf $vout "Verbose logging enabled\n";
	}

	if ($href->{branches} <= $href->{loop}) {
		print STDERR "--branch-rate must be greater than --loop-rate\n";
		return 0;
	}
	if (!defined($href->{branchd})) {
		$href->{branchd} = 3 * $href->{blocklen};
	}

	print $vout "Likelihood an instruction will branch: "
	    . $href->{branches} . "\n";
	print $vout "Average distance of branch jump: " . $href->{branchd} . "\n";
	print $vout "Likelihood an instruction will loop: "
	    . $href->{loop} . "\n";
	print $vout "Average loop iterations: " . $href->{loopi} . "\n";
	print $vout "Average block length: " . $href->{blocklen} . "\n";
	print $vout "Number of blocks: " . $href->{blockcount} . "\n";
	return 1;
}

#
# Initialize verbose logging
#
sub init_verbose {
	open $vout, ">", "/dev/null";
}

#
# Enables verbose logging
#
sub set_verbose {
	close $vout;
	open $vout, ">-"; # sets vout to stdout
}

#
#
#
sub add_block {
	my ($prog, %args, $count);
	($prog, %args) = @_;

	my $blocklen = rnorm($args{blocklen}, $args{blocklen} * .25);
	my $addr = $args{start_addr};
	for (1..$blocklen) {
		$prog->set_instr($addr => [$addr + 1, 0, 0]);
		$addr++;
	}
	
	return $blocklen;
}

sub rnorm {
	my ($mean, $std);
	($mean, $std) = @_;

	return int(random_normal(1, $mean, $std));
}

sub add_loop {
	my ($prog, $addr, $iters);
	($prog, $addr, $iters) = @_;

	$iters = rnorm($iters, $iters * .25);
	
	my ($start, $end);
	$end = $addr;
	do {
		$start = int(rand($addr));
	} while (!loop_split($prog, $start, $end));

	print $vout
	    "Adding a loop with $iters iterations from $start to $end\n";
	$prog->set_instr($end, [$start, $iters, $end + 1]);

	return ($end + 1);
}

sub loop_split {
	my ($prog, $start, $end);
	($prog, $start, $end) = @_;

	my @loop_pairs = @{$prog->loop_pairs()};
	print $vout "Checking ($start, $end) against " . scalar(@loop_pairs) 
	    . " loops\n  "; 
	
	foreach my $pair (@loop_pairs) {
		my ($loops, $loope) = @{$pair};
		print $vout "Inspecting loop ($loops, $loope)\n  ";
		if (($loops == $start) || ($loope == $start)) {
			print $vout
			    "Rejecting ($start, $end) because of $start\n";
			return 0;
		}
		if (($loops == $end) || ($loope == $end)) {
			print $vout
			    "Rejecting ($start, $end) because of $end\n";
			return 0;
		}

		if (($start < $loope) && ($end > $loope)) {
			print $vout
			    "Rejecting because $start is in the middle\n";
			return 0;
		}
		if (($start < $loops) && ($end > $loops)) {
			print $vout
			    "Rejecting because $end is in the middle\n";
			return 0;
		}
	}

	print $vout "Accepted ($start, $end)\n";
	return 1;
}

#
# Adds a branch where the false case *ends* at the current address.
#
sub add_branch {
	my ($prog, $addr, %args);
	($prog, $addr, %args) = @_;

	my ($start, $end, $branchd, $limit);
	$branchd = $args{branchd};
	$limit = 1;
	$end = $addr;
	$prog->set_instr($end, [$end + 1, 0, 0]);
	
	my $loops = $prog->loop_pairs();
	if (@$loops) {
		$limit = $loops->[-1]->[1];
	}
	do {
		my $d = rnorm($branchd, $branchd * .25);
		$start = $end - $d;
		$start = $limit + 1 if ($start <= $limit);
	} while (!loop_split($prog, $start, $end));

	print $vout "Adding branch from $start -> (" . ($start + 1)
	    . " or $end)\n";
	
	$prog->set_instr($start, [$start + 1, 0, $end]);

	return ($end + 1);
}	



exit main();

__END__

=pod

=head1 NAME

simgen.pl -- Simulated Program Generator

=head1 SYNOPSIS

 simgen.pl <OPTIONS> > <PROGRAM>
 simgen.pl --loop-rate=.05

=head1 OPTIONS

=over

=item -c|--block-count=i

The number of basic blocks, defaults to 20

=item -a|--average-block=i

The average number of instructions per basic block, defaults to 15

=item -b|--branch-rate=f

The probability than any instruction will be a branching instruction,
must be between 0 and 1.

=item -d|--average-branch-distance=i

The average number of instructions between branching statements,
default is 3 times the average block length

=item -l|--loop-rate=f

The probability than any instruction will be a looping instruction.

=item -i|--max-loop=i

The maximum number of loop iterations assigned to any loop

=item -v|--verbose

Enables verbose logging

