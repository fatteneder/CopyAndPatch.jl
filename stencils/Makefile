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

# makefile options
CFLAGS=

debug?=0
ifeq ($(debug),1)
CFLAGS+=-DJITDEBUG
endif

use_ghc_cc?=0
ifeq ($(use_ghc_cc),1)
CFLAGS+=-DUSE_GHC_CC
endif

# targets

.SECONDARY:
all: $(BINJSON) $(BINSO) $(BINMWES)

bin/%.o: %.c compile common.h
	./compile "$(CFLAGS)" $< bin/$*.o

bin/%.json: bin/%.o readobj
	./readobj $< > bin/$*.json

bin/libjuliahelpers.so: libjuliahelpers.c
	gcc -I'${JULIA_INCLUDE}' -I'${JULIA_INCLUDE}/julia' -I'${JULIA_INTERNAL_INCLUDE}' \
			-L'${JULIA_LIB}' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o bin/libjuliahelpers.so libjuliahelpers.c

bin/libffihelpers.so: libffihelpers.c
	gcc -I'${LIBFFI_INCLUDE}' \
			-std=gnu11 -fPIC -lffi -shared \
			-o bin/libffihelpers.so libffihelpers.c

bin/libmwes.so: libmwes.c
	gcc -I'${JULIA_INCLUDE}/julia' -I'${LIBFFI_INCLUDE}' \
			-L'${JULIA_LIB}' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -lffi -shared \
			-o bin/libmwes.so libmwes.c

bin/libccalltest.so: libccalltest.c
	gcc -I'${JULIA_INCLUDE}/julia' \
			-L'${JULIA_LIB}' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o bin/libccalltest.so libccalltest.c

bin/mwe_libffi: mwe_libffi.c
	gcc -I'${JULIA_INCLUDE}/julia' -I'${LIBFFI_INCLUDE}' \
			-L'${JULIA_LIB}' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -lffi \
			-o bin/mwe_libffi mwe_libffi.c

clean:
	@rm -rf bin/
