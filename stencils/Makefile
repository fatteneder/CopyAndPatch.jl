SRCLIBS=$(wildcard lib*.c)
SRC=$(wildcard *.c)
SRC+=$(wildcard mwes/*.c)
SRC:=$(filter-out $(SRCLIBS),$(SRC))

OBJ=$(SRC:.c=.o)
JSON=$(OBJ:.o=.json)
SO=$(SRCLIBS:.c=.so)
LL=$(SRC:.c=.ll)

BINOBJ=$(addprefix bin/,$(OBJ))
BINJSON=$(addprefix bin/,$(JSON))
BINSO=$(addprefix bin/,$(SO))
BINLL=$(addprefix bin/,$(LL))

$(shell mkdir -p bin)

CFLAGS=
CC=$(CLANG)

# makefile options
debug?=0
ifeq ($(debug),1)
CFLAGS+=-DJITDEBUG
endif

use_ghc_cc?=0
ifeq ($(use_ghc_cc),1)
CFLAGS+=-DUSE_GHC_CC
endif

emit_llvm?=0

# targets

ifeq ($(emit_llvm),0)
.SECONDARY:
all: $(BINJSON) $(BINSO)
else
.SECONDARY:
all: $(BINJSON) $(BINSO) $(BINLL)
endif

bin/%.o: %.c compile common.h
	./compile "$(CFLAGS)" $< bin/$*.o

bin/%.json: bin/%.o readobj
	./readobj $< > bin/$*.json

bin/%.ll: %.c compile common.h
	./compile "$(CFLAGS) -S -emit-llvm" $< bin/$*.ll

bin/libjuliahelpers.so: libjuliahelpers.c
	$(CC) -I'${JULIA_REPO_SRC}' -I'${JULIA_INCLUDE}' -I'${JULIA_INCLUDE}/julia' \
			-L'${JULIA_LIB}' -L'${JULIA_LIB}/julia' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o bin/libjuliahelpers.so libjuliahelpers.c

bin/libccalltest.so: libccalltest.c
	$(CC) -I'${JULIA_REPO_SRC}' -I'${JULIA_INCLUDE}' -I'${JULIA_INCLUDE}/julia' \
			-L'${JULIA_LIB}' -L'${JULIA_LIB}/julia' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o bin/libccalltest.so libccalltest.c

bin/libffihelpers.so: libffihelpers.c
	$(CC) -I'${LIBFFI_INCLUDE}' \
			-std=gnu11 -fPIC -lffi -shared \
			-o bin/libffihelpers.so libffihelpers.c

# TODO Remove
bin/libmwes.so:

clean:
	@rm -rf bin/
