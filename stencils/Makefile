SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
OBJ=$(SRC:.c=.o)
JSON=$(SRC:.c=.json)

%.o: %.c compile
	./compile $< $*.o

%.json: %.o readobj
	./readobj $< > $*.json

.SECONDARY:
all: $(JSON) libjl.so

libjl.so: libjl.c
	gcc -std=gnu11 -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -ljulia -shared -o $*.so $<

clean:
	rm -f $(JSON)
	rm -f $(OBJ)
