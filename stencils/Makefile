LIBS=$(wildcard lib*.c)
SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
SRC:=$(filter-out $(LIBS),$(SRC))
OBJ=$(SRC:.c=.o)
JSON=$(OBJ:.o=.json)
SO=$(LIBS:.c=.so)

%.o: %.c compile
	./compile $< $*.o

%.json: %.o readobj
	./readobj $< > $*.json

.SECONDARY:
all: $(JSON) $(SO)

libjl.so: libjl.c
	gcc -std=gnu11 -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -ljulia -shared -o libjl.so libjl.c

libffihelpers.so: libffihelpers.c
	gcc -std=gnu11 -I'${LIBFFI_INCLUDE}' -fPIC -lffi -shared -o libffihelpers.so libffihelpers.c

clean:
	@rm -f $(OBJ)
	@rm -f $(JSON)
	@rm -f $(SO)

clean-all:
	@rm -f $(wildcard *.o)
	@rm -f $(wildcard mwes/*.o)
	@rm -f $(wildcard *.json)
	@rm -f $(wildcard mwes/*.json)
	@rm -f $(wildcard *.so)
	@rm -f $(wildcard mwes/*.so)
