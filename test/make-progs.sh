#!/bin/bash

N=10
BLOCK_COUNT=68
BLOCK_LEN=12
BRANCH_F=0.09
LOOP_F=0.045
LOOP_I=20

JOBS=8
i=0
while ((i < N))
do
	running=0
	while [[ ($running -lt $JOBS) && ($i -lt $N) ]]
	do
		file=$(printf 'dat/p%03d.pp' $i)
		../src/simgen.pl -c ${BLOCK_COUNT} -a ${BLOCK_LEN} \
			  -b ${BRANCH_F} -l ${LOOP_F} \
			  -i ${LOOP_I} > $file &
		((i++))
		echo "Program ($i/$N)"
		((running++))
	done
	wait
done
