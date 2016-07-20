.PHONY = virun  all run

run:
	perl wsp.pl test.wsp

virun: 
	tmux send-keys -t output:0.0 "make run" Enter

