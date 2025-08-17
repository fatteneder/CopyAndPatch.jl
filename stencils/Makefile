SRCLIBS=$(wildcard lib*.c)
SRCMWES=$(wildcard mwe_*.c)
SRC=$(wildcard *.c)
SRC:=$(filter-out $(SRCLIBS) $(SRCMWES),$(SRC))

OBJ=$(SRC:.c=.o)
JSON=$(OBJ:.o=.json)
SO=$(SRCLIBS:.c=.so)
LL=$(SRC:.c=.ll)

ifeq ($(BINDIR),)
	BINDIR:=/tmp/cpjit-bin/
endif
$(shell mkdir -p $(BINDIR))
$(info compiling into $(BINDIR) ...)

BINOBJ=$(addprefix $(BINDIR),$(OBJ))
BINJSON=$(addprefix $(BINDIR),$(JSON))
BINSO=$(addprefix $(BINDIR),$(SO))
BINLL=$(addprefix $(BINDIR),$(LL))

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

$(BINDIR)%.o: %.c compile common.h
	./compile "$(CFLAGS)" $< $(BINDIR)$*.o

$(BINDIR)%.json: $(BINDIR)%.o readobj
	./readobj $< > $(BINDIR)$*.json

$(BINDIR)%.ll: %.c compile common.h
	./compile "$(CFLAGS) -S -emit-llvm" $< $(BINDIR)$*.ll

$(BINDIR)libjuliahelpers.so: libjuliahelpers.c
	$(CC) -I'${JULIA_REPO_SRC}' -I'${JULIA_INCLUDE}' -I'${JULIA_INCLUDE}/julia' \
			-L'${JULIA_LIB}' -L'${JULIA_LIB}/julia' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o $(BINDIR)libjuliahelpers.so libjuliahelpers.c

$(BINDIR)libccalltest.so: libccalltest.c
	$(CC) -I'${JULIA_REPO_SRC}' -I'${JULIA_INCLUDE}' -I'${JULIA_INCLUDE}/julia' \
			-L'${JULIA_LIB}' -L'${JULIA_LIB}/julia' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -shared \
			-o $(BINDIR)libccalltest.so libccalltest.c

$(BINDIR)libffihelpers.so: libffihelpers.c
	$(CC) -I'${LIBFFI_INCLUDE}' \
			-std=gnu11 -fPIC -lffi -shared \
			-o $(BINDIR)libffihelpers.so libffihelpers.c

# TODO Remove
$(BINDIR)libmwes.so: libmwes.c
	$(CC) -I'${JULIA_INCLUDE}/julia' -I'${LIBFFI_INCLUDE}' \
			-L'${JULIA_LIB}' \
			-Wl,--export-dynamic -Wl,-rpath,'${JULIA_LIB}' -Wl,-rpath,'${JULIA_LIB}/julia' \
			-std=gnu11 -fPIC -ljulia -ljulia-internal -lffi -shared \
			-o $(BINDIR)libmwes.so libmwes.c

clean:
	@rm -rf $(BINDIR)
