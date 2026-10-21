all:
	$(MAKE) -C average all

run:
	$(MAKE) -C average run FILE=data.txt

clean:
	$(MAKE) -C average clean

.PHONY: all run clean
