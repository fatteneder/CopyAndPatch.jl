SRCLIBS=$(wildcard lib*.c)
SRCMWES=$(wildcard mwe_*.c)
SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
SRC:=$(filter-out $(SRCLIBS) $(SRCMWES),$(SRC))
$(info $(SRC))
OBJ=$(SRC:.c=.o)
JSON=$(OBJ:.o=.json)
SO=$(SRCLIBS:.c=.so)
MWES=$(SRCMWES:.c=.o)

%.o: %.c compile
	./compile $< $*.o

%.json: %.o readobj
	./readobj $< > $*.json

.SECONDARY:
all: $(JSON) $(SO) $(OBJMWES)

libjl.so: libjl.c
	gcc -std=gnu11 -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -ljulia -shared -o libjl.so libjl.c

libffihelpers.so: libffihelpers.c
	gcc -std=gnu11 -I'${LIBFFI_INCLUDE}' -fPIC -lffi -shared -o libffihelpers.so libffihelpers.c

mwe_libffi: mwe_libffi.c
	gcc -std=gnu11 -I'${JULIA_INTERNAL_INCLUDE}' -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -I'${LIBFFI_INCLUDE}' -ljulia -ljulia-internal -lffi -o mwe_libffi mwe_libffi.c

clean:
	@rm -f $(OBJ)
	@rm -f $(JSON)
	@rm -f $(SO)
	@rm -f $(MWES)

clean-all:
	@rm -f $(wildcard *.o)
	@rm -f $(wildcard mwes/*.o)
	@rm -f $(wildcard *.json)
	@rm -f $(wildcard mwes/*.json)
	@rm -f $(wildcard *.so)
	@rm -f $(wildcard mwes/*.so)
