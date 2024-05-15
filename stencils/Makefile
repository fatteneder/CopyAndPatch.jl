SRCLIBS=$(wildcard lib*.c)
SRCMWES=$(wildcard mwe_*.c)
SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
SRC:=$(filter-out $(SRCLIBS) $(SRCMWES),$(SRC))

OBJ=$(SRC:.c=.o)
JSON=$(OBJ:.o=.json)
SO=$(SRCLIBS:.c=.so)
MWES=$(SRCMWES:.c=)

BINOBJ=$(addprefix bin/,$(OBJ))
BINJSON=$(addprefix bin/,$(JSON))
BINSO=$(addprefix bin/,$(SO))
BINMWES=$(addprefix bin/,$(MWES))

$(shell mkdir -p bin/mwes)

bin/%.o: %.c compile
	./compile $< bin/$*.o

bin/%.json: bin/%.o readobj
	./readobj $< > bin/$*.json

.SECONDARY:
all: $(BINJSON) $(BINSO) $(BINMWES)

bin/libjuliahelpers.so: libjuliahelpers.c
	gcc -std=gnu11 -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -ljulia -shared -o bin/libjuliahelpers.so libjuliahelpers.c

bin/libffihelpers.so: libffihelpers.c
	gcc -std=gnu11 -I'${LIBFFI_INCLUDE}' -fPIC -lffi -shared -o bin/libffihelpers.so libffihelpers.c

bin/mwe_libffi: mwe_libffi.c
	gcc -std=gnu11 -I'${JULIA_INTERNAL_INCLUDE}' -I'${JULIA_INCLUDE}' -fPIC -L'${JULIA_LIB}' -Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' -I'${LIBFFI_INCLUDE}' -ljulia -ljulia-internal -lffi -o bin/mwe_libffi mwe_libffi.c

clean:
	@rm -rf bin/
