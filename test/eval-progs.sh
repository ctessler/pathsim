#!/bin/bash

n=10
scheds="seq random bundle"
tmax="1 2 4 8 16"
caches="64 128 256 512 1024"

count=0
total=$((3 * 5 * 5 * $n))
for p in dat/*.pp
do
	for t in $tmax
	do
		for c in $caches
		do
			for s in $scheds
			do
				fname=$(printf "$p-%02dt-%04dc-%s.dat" $t $c $s)
				msg=$(printf "Working on $p (m:%2d, l:%4d, %06s)\t$fname" \
					     $t $c $s)
				echo "$msg"
				../src/psim.pl -l $c -s $s -p $p=$t -d dat/decisions \
					       > $fname &
			done
			wait
			((count += 3))
			pct=$(echo "($count / $total) * 100 " | bc -l)
			str=$(printf "%05d/%05d: %.03f%s done." $count $total $pct '%')
			echo $str
		done
	done
done
