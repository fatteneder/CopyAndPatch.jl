SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
OBJ=$(SRC:.c=.o)
JSON=$(SRC:.c=.json)

%.o: %.c compile
	./compile $< $*.o

%.json: %.o readobj
	./readobj $< > $*.json

.SECONDARY:
all: $(JSON)

clean:
	rm -f $(JSON)
	rm -f $(OBJ)
