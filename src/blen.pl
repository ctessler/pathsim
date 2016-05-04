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

# False entry point for perl
sub main {
	init_verbose();

	my %args;
	my $rv = parse_args(\%args);
	if (!$rv || $args{usage}) {
		pod2usage(1);
		return 1;
	}

	open (FILE, "<$args{file}") or die "Could not open $args{file}";
	my ($startre, $endre, $bb_len, $in_bb, $bb_count, $bb_sum);
	$startre = '^(define|; \<label)';
	$endre = '^(\}|; \<label)';
	$bb_count = $bb_sum = $in_bb = 0;
	while (my $line = <FILE>) {
		chomp($line);
		if ($line eq '') {
			next;
		}
		print $vout "\t$line\n";
		if ($line =~ /$startre/) {
			print $vout "Starting a new block\n";
			$in_bb = 1;
			$bb_count++;
			next;
		}
		$bb_len++ if ($in_bb);
		if ($line =~ /$endre/) {
			print $vout "Ends a basic block\n";
			$in_bb = 0;
			next;
		}
	}
	close(FILE);

	print "Total Instructions\tNumber of Blocks\tAverage Block Length\n";
	printf("%-18d\t%-17d\t%-20f\n", $bb_len, $bb_count, ($bb_len / $bb_count));
	
	return 0;
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

sub parse_args {
	my $href = shift;

	my $rv = GetOptions(
	    "verbose" => \$href->{verbose}
	    );

	if (defined($href->{verbose})) {
		set_verbose();
		printf $vout "Verbose logging enabled\n";
	}

	my $file = shift @ARGV;
	if (!defined($file)) {
		print STDERR "A llvm file is required\n";
		return 0;
	}

	$href->{file} = $file;

	return 1;
}

exit main();

__END__

