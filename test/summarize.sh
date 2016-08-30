#!/bin/bash

scheds="seq random bundle"
tmax="1 2 4 8 16"
caches="64 128 256 512 1024"

function summary {
	s=$1
	l=$2
	t=$3

	for t in $tmax
	do
		pattern=$(printf 'res/cum-%02dt-%04dc-%s.dat' $t $l $s)

		tmp=$(awk '{a+=$3} END{print a/NR}' $pattern)
		tmp=$(printf '(t=%d %5d)' $t $tmp)
		avg="$avg $tmp"
	done
	str=$(printf '%-6s %-5d' $s $l)
	echo "$str $avg"
	avg=""
}


echo "Sched. Cache Avg Misses (t=#threads #misses)"
echo "       Lines"
for s in $scheds
do
	for l in $caches
	do
		for t in $tmax
		do
			summary $s $l $t
		done
	done
done
