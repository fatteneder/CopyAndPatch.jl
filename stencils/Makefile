# flags obtained from running the julia-config.jl script

SRC=$(wildcard *.c)
OBJ=$(SRC:.c=.o)
JSON=$(SRC:.c=.json)

%.o: %.c compile
	./compile $<

%.json: %.o readobj
	./readobj $< > $*.json

.SECONDARY:
all: $(JSON)

clean:
	rm *.json
	rm *.o
