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

use Prog;
use SimThread;
use Cache;
use vars qw/$vout/;

# False entry point for perl
sub main {
	init_verbose();

	my %args;
	my $rv = parse_args(\%args);
	if (!$rv || $args{usage}) {
		pod2usage(1);
		return 1;
	}
	my ($clines, $decision, $sched, $prog, $threads);
	$clines = $args{clines};
	$sched = $args{sched};
	$decision = $args{decision};
	{
		my @keys = keys(%{$args{prog}});
		$prog = $keys[0];
		$threads = $args{prog}->{$keys[0]};
	}
	print $vout "Program File (Threads): $prog ($threads)\n";
	print $vout "Cache Size: $clines\n";
	print $vout "Scheduler: $sched\n";
	print $vout "Decision File: $decision\n";

	my (@dbranch, @dloop);
	if ($decision) {
		my ($fh, $line);
		open($fh, "<$decision");
		$line = <$fh>; chomp($line);
		@dbranch = split(/\s+/, $line);
		print $vout "Branch decisions: " . join(", ", @dbranch) . "\n";
		$line = <$fh>; chomp($line);
		@dloop = split(/\s+/, $line);
		print $vout "Loop decisions: " . join(", ", @dloop) . "\n";
		close($fh);
	}

	my $p = new Prog(file => $prog);
	print $vout "Program object file: " . $p->file() . ": \n";
	$p->print($vout);


	# Arguments Parsed


	# Create the cache
	my $cache = Cache->new('lines', $clines);

	# Create the threads
	my @threads;
	for (1..$threads) {
		my (@db, @dl);
		@db = @dbranch;
		@dl = @dloop;
		push @threads, new SimThread(prog => $p, name => "t$_",
					     run_branch_decisions=>\@db,
					     run_loop_decisions=>\@dl);
	}

	my $conflicts;
	print "Running $threads threads with a cache size of $clines lines"
	    . " using ";
	if ($sched eq 'seq') {
		print "a sequential scheduler\n";
		$conflicts = sched_seq($cache, @threads);
	}
	if ($sched eq 'random') {
		print "a random scheduler\n";
		$conflicts = sched_random($cache, @threads);
	}
	if ($sched eq 'bundle') {
		print "the bundle scheduler\n";
		$conflicts = sched_bundle($cache, @threads);
	}

	my $counter = 0;
	foreach my $t (@threads) {
		$counter += $t->ins_count();
	}
	print "Instructions Executed\tContext Switches\tCache Conflicts\n";
	printf("%-21d\t%-16d\t%-15d\n", $counter, ctx_switches(), $conflicts);

	return 0;
}

sub sched_seq {
	my ($cache, @threads);
	($cache, @threads) = @_;

	for (my $i=1; $i <= scalar(@threads); $i++) {
		ctx_switch_up();
		my $t = $threads[$i - 1];
		while ($t->ready()) {
			print $vout "$i -- " . $t->status() . "\n";
			my $addr = $t->step();
			$cache->access($addr);
		}
		print $vout "$i -- " . $t->status();
		print $vout " conflicts: " . $cache->conflicts() . "\n";
	}
	return $cache->conflicts();
}

sub sched_random {
	my ($cache, @threads);
	($cache, @threads) = @_;

	my ($tc, $delay_cap);
	$tc = scalar(@threads);
	$delay_cap = $threads[0]->prog()->instruction_count();

	print $vout "Random Scheduler with $tc threads and maximum " .
	    "non-preemptive instruction run $delay_cap\n";

	while (ready_threads(@threads)) {
		my $tid = int(rand($tc));
		my $cycles = int(rand($delay_cap + 1));
		my $t = $threads[$tid];
		if (!$t->ready()) {
			next;
		}
		ctx_switch_up();
		print $vout "Running thread $tid for $cycles cycles\n";
		for (my $i=0; $i < $cycles; $i++) {
			print $vout "$tid -- " . $t->status() . "\n";
			my $a = $t->step();
			$cache->access($a);
			if (!$t->ready()) {
				last;
			}
		}
		print $vout "$tid -- " . $t->status() . "\n";
	}
	return $cache->conflicts();
}

sub sched_bundle {
	my ($cache, @threads);
	($cache, @threads) = @_;

	my (%bundles, $active, $aid, $delay_cap);
	$aid = $threads[0]->first_instr();
	$bundles{$aid} = [ @threads ];

	while (ready_threads(@threads)) {
		my $ab = $bundles{$aid}; # array ref
		print $vout "Bundle $aid is active\n";
		dump_bundles(%bundles);
		while (ready_threads(@{$ab})) {
			# Bundle is active.
			my ($tid, $t);
			($tid, $t) = select_thread($ab);

			my ($new_bid);
			$new_bid = bundle_forward($t, $aid, $cache);
			splice @{$ab}, $tid, 1; # Remove from active bundle
			# Place in new bundle
			push @{$bundles{$new_bid}}, $t if $new_bid ;
		}
		# The bundle "should" be empty, delete the key
		delete $bundles{$aid};
		# Select a new bundle to execute, the intelligent choice *may*
		# be the largest bundle
		$aid = (keys %bundles)[rand keys %bundles];
	}
	return $cache->conflicts();
}

#
# ($index, $thread) = select_thread($array_ref);
#
sub select_thread {
	my $aref = shift;

	my $max = scalar(@{$aref});
	my $idx = int(rand $max);
	my $thread = $aref->[$idx];

	print $vout "select_thread: Available threads: (" .
	    join(", ", map { $_->name() } @{$aref}) . ") ";
	print $vout "selected $idx:" . $thread->name() . "\n";

	ctx_switch_up();
	return ($idx, $thread);
}

#
# Executes the thread until it terminates or conflicts with an instruction
# within the bundle (meaning it left the bundle)
#
# $bundle_id = bundle_forward($thread, $active_bundle_id, $cache);
#
# Returns the new bundle id for the thread, zero if terminated
#
sub bundle_forward {
	my ($t, $aid, $bid, $cache);
	($t, $aid, $cache) = @_;
	$bid = 0;

	while ($t->ready()) {
		my ($pc, $m, $line, $cbid);
		$pc = $t->pc(); # Next instruction to execute
		$m = $cache->map($pc); # Cache line numbe

		$line = $cache->get_line($m); # Cached instruction
		$line = 0 if !defined($line);

		print $vout $t->name() . " pc:$pc maps to cache[$m] = $line\n";
		if ($line != $pc) {
			# Cache miss
			$cbid = $cache->get_bundle($m);
			$cbid = 0 if !defined($cbid);
			if ($aid == $cbid) {
				# Evicting from this bundle, bad bad.
				print $vout $t->name() . " conflict with "
				    . "active bundle suspending\n";
				return $pc; # new bundle id
			}
		}
		# Progress the thread, mark the cache line
		print $vout $t->name() . " " . $t->status() . "\n";
		my $a = $t->step();
		$cache->access($a);
		$cache->set_bundle($m, $aid);
	}
	# If we got here, the thread terminated
	print $vout $t->name() . " " . $t->status() . "\n";
	return $bid;
}

sub dump_bundles {
	my %bundles = @_;
	print $vout "Bundle IDs: " . join(", ", keys %bundles) . "\n";
}

#
# Usage: bool = ready_threads(@threads)
#
sub ready_threads {
	my @threads = @_;

	return grep { $_->ready() } @threads;
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
# Parses the command line arguments
#
sub parse_args {
	my $href = shift;

	my $rv = GetOptions("l|cache-lines=i" => \$href->{clines},
			    "s|scheduler=s" => \$href->{sched},
			    "p|program=s%" =>  \$href->{prog},
			    "d|decision=s" => \$href->{decision},
			    "verbose" => \$href->{verbose}
	    );

	if (defined($href->{verbose})) {
		set_verbose();
		printf $vout "Verbose logging enabled\n";
	}

	if (!defined($href->{clines})) {
		printf STDERR "Must provide --cache-lines\n";
		return 0;
	}
	if (!defined($href->{sched})) {
		printf STDERR "Must provide --scheduler\n";
		return 0;
	}
	if ($href->{sched} !~ /^seq|random|bundle$/) {
		printf STDERR "Valid --scheduler options are: " .
		    "seq, bundle, random. Not: " . $href->{sched} . "\n";
		return 0;
	}
	if (!defined($href->{prog})) {
		printf STDERR "Must provide --program\n";
		return 0;
	}

	return 1;
}

#
# Registers a context switch
#
use vars qw/$CTX_SWITCHES/;
$CTX_SWITCHES = 0; # First switch doesn't count
sub ctx_switch_up {
	$CTX_SWITCHES++;
}

sub ctx_switches {
	return $CTX_SWITCHES;
}

exit main();

__END__

=pod 

=head1 NAME

psim.pl -- Path explorer SIMulator

=head1 SYNOPSIS

 psim.pl <OPTIONS> -p <prog file>=<# threads>
 psim.pl -l=24 -s=seq -p prog.pp=3

=head1 OPTIONS

=over

=item -l|--cache-lines N

The number of cache lines

=item -s|--scheduler <algorgithm>

The scheduler to use, either "seq", "bundle", "random". "seq"uential
executes one thread after another, "bundle" corresponds to BUNDLE, and
"random" preempts threads randomly.

=item -p|--program <file>=<# threads>

The program file described below and the number of threads it releases
on startup.

=item -d|--decision <file>

A list of branching and looping decisions used when running a program.

=item --usage

Displays the usage meassage and quits.

=item --verbose

Enables verbose output

=back

=head1 PROGRAM FILE FORMAT

 ##psim#1.0.a##
 <I ADDR> | <T ADDR> [(<ITER>)] | <F ADDR>
 <I ADDR> | <T ADDR> [(<ITER>)] | <F ADDR>
 ...
 <I ADDR> | <T ADDR> [(<ITER>)] | <F ADDR>

=head1 PROGRAM FILE EXAMPLE

 ##psim#1.0.a##

 01 | 02 # Comment
 02 | 03
 03 | 04 # Loop start
 04 | 05 
 05 | 06
 # Loop body

 06 | 07
 07 | 08
 08 | 03 (12) | 08 # Loop condition, repeats at most 12 times.
 09 # End of program

=head1 PROGRAM FILE DESCRIPTION

Each file represents the instructions of a program. There are three
types of lines within the file: a version line, a comment line, or an
instruction line. The file must start with a version line, and match
the format given in the FILE FORMAT section. A comment line begins
with a # mark, and has no effect on the contents. Blank lines are
ignored,

An instruction line represents an instruction and possible control
flow changes. The first instruction line corresponds to the first
instruction of a program. In this version of the simulator, an
instruction has three components: an address, a next if true address,
and a next if false address.

The <I ADDR> gives the address of the instruction on the line. The <T
ADDR> identifies the instruction that control will transfer 
the "true" case. The <F ADDR> identifies the instruction control will
transfer to in the "false" case. An instruction with only a <T ADDR>
has only one possible path, an instruction with a <T ADDR> and <N
ADDR> will have two possible paths, and an instruction with neither is
a terminal instruction.

For loops an instruction must have a parenthesized <ITER> number,
limiting the maximum number of times the loop may be repeated.

=over

=item <I ADDR> 

This instruction's address

=item <T ADDR>

The next instruction to execute in the "true" case. Or when there is
no <F ADDR>

=item <F ADDR>

The next instruction to execute in the "false" case.

=item (<ITER>)

The maximum number of iterations if the next address participates in a
loop. 

=back
