DECISIONS=dat/decisions
all: results.txt

results.txt: res/summary.txt

res/summary.txt: res/DONE
	@echo ""
	@echo "Summarizing the Data (summarize.sh)"
	@echo ""
	./summarize.sh > res/summary.txt
	cat res/summary.txt
	@echo ""
	@echo "Summarized results in res/summary.txt"


res/DONE: res dat/RUNS
	@echo ""
	@echo "Compiling Results (collect-data.sh)"
	@echo ""
	./collect-data.sh
	@echo "See the res directory for the cumulative results"
	@echo "For all programs, running 2 threads, with 512 lines of cache"
	@echo "  scheduled by bundle the file is res/cum-02t-0512c-bundle.dat"
	@echo "Each line of the file is:"
	@echo "  <instructions executed> <thread context switches> <cache misses>"
	touch res/DONE
res:
	mkdir res

dat/RUNS: dat/GENERATED
	@echo ""
	@echo "Simulating Execution (eval-progs.sh)"
	@echo ""
	./eval-progs.sh
	touch dat/RUNS

dat/GENERATED: dat/decisions
	@echo ""
	@echo "Generating Program Parameters (make-progs.sh)"
	@echo ""
	./make-progs.sh
	touch dat/GENERATED

dat/decisions: dat
	shuf -i 0-1 -n 200 -r | tr '\n' ' ' > $(DECISIONS)
	echo "" >> $(DECISIONS)
	shuf -i 1-40 -n 200 -r | tr '\n' ' ' >> $(DECISIONS)
	echo "" >> $(DECISIONS)

dat:
	mkdir dat

clean:
	rm -rf dat res
