#!/bin/bash

scheds="seq random bundle"
tmax="1 2 4 8 16"
caches="64 128 256 512 1024"

function collect {
	s=$1
	l=$2
	t=$3

	pattern=$(printf 'dat/*-%02dt-%04dc-%s.dat' $t $l $s)
	cum=$(printf 'res/cum-%02dt-%04dc-%s.dat' $t $l $s)
	echo "$pattern"

	cat $pattern | egrep '^[[:digit:]]' > $cum
}


for s in $scheds
do
	for l in $caches
	do
		for t in $tmax
		do
			collect $s $l $t
		done
	done
done
