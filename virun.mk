.PHONY = all unsweet run compile prep
all:
	tmux send-keys -t output:0.0 "make -f virun.mk simpletest" Enter


simpletest:
	perl wsp.pl test.lit test.w

unsweet:
	./unsweeten test.w  | tee test.sscm 


run: unsweet 
	@echo "" > header
	@#perl prep.pl test.lit test.racket HEADER > header 
	@cat header test.sscm > test.scm
	@tmux send-keys -t output:0.1 "gosh ./test.scm"  Enter
	@#tmux send-keys -t output:0.1 "guile ./test.scm"  Enter
	@#tmux send-keys -t output:0.1 "(load \"$$(pwd)/test.scm\")" Enter

compile:
	@./unsweeten test.w | tee test.scm && tmux send-keys -t output:0.1 "make run" Enter

gauche:
	@perl prep.pl test.lit test.gauche | tee test.w && tmux send-keys -t output:0.1 "make -f virun.mk run" Enter

racket:
	@perl prep.pl test.lit test.racket | tee test.w && make -f virun.mk run

guile:
	@perl prep.pl test.lit test.guile | tee test.w && make -f virun.mk run

