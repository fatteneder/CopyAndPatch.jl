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
	gcc -std=gnu11 -I'/home/flo/.julia/juliaup/julia-1.10.1+0.x64.linux.gnu/include/julia' -fPIC -L'/home/flo/.julia/juliaup/julia-1.10.1+0.x64.linux.gnu/lib' -Wl,--export-dynamic -Wl,-rpath,'/home/flo/.julia/juliaup/julia-1.10.1+0.x64.linux.gnu/lib' -Wl,-rpath,'/home/flo/.julia/juliaup/julia-1.10.1+0.x64.linux.gnu/lib/julia' -ljulia -shared -o $*.so $<

clean:
	rm -f $(JSON)
	rm -f $(OBJ)
