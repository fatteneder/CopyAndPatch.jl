## Julia internals

Ways to call julia functions from C:
- `jl_invoke`
- `jl_apply`
    - `jl_call`
    - `jl_call2`
    - `jl_call3`
    - ...

Likely interesting dllexports from `julia.h` to interact with julia compiled functions
```
// "speccall" calling convention signatures.
// This describes some of the special ABI used by compiled julia functions.
extern jl_call_t jl_fptr_args;
JL_DLLEXPORT extern const jl_callptr_t jl_fptr_args_addr;
typedef jl_value_t *(*jl_fptr_args_t)(jl_value_t*, jl_value_t**, uint32_t);

extern jl_call_t jl_fptr_const_return;
JL_DLLEXPORT extern const jl_callptr_t jl_fptr_const_return_addr;

extern jl_call_t jl_fptr_sparam;
JL_DLLEXPORT extern const jl_callptr_t jl_fptr_sparam_addr;
typedef jl_value_t *(*jl_fptr_sparam_t)(jl_value_t*, jl_value_t**, uint32_t, jl_svec_t*);

extern jl_call_t jl_fptr_interpret_call;
JL_DLLEXPORT extern const jl_callptr_t jl_fptr_interpret_call_addr;

JL_DLLEXPORT extern const jl_callptr_t jl_f_opaque_closure_call_addr;
```

- Trying to understand how functions are called.
  - `REPL` uses `Core.eval`, which is defined in `base/boot.jl` for each new module,
    which in turn calls into `jl_toplevel_eval_in` and that calls `jl_toplevel_eval_flex`,
    both located in `src/toplevel.c`. IIUC then the last method here calls
    `jl_invoke` to hand things to codegen.
    What is interesting is that it is called with `jl_invoke(NULL,NULL,0,mi)`, where
    `mi` is a `jl_method_instance_t`, e.g. without knowledge about any arguments.
    But I am not sure if that is the right branch actually.
    The other branch says it hands things off to the interpreter, which also does some
    call stuff, I think. However, inside `src/interpreter.c` there is `do_call` which
    calls `jl_apply`, so I think I already gone full cycle.
    My problem is that I don't know how to generate a `jl_function_t *` from a
    julia function.
    `jl_toplevel_eval_flex` generates a `thunk` somewhere using `jl_evalexpr`,
    which is then handed off to either codegen or interpreter. But `jl_evalexpr`
    is just a call to `jl_array_ptr_ref` ...

Q:
- When using any of the above, do we need to root arguments?
- If we prepare stencils, do we need to `jl_init`?
  Probably not, because IIUC that's needed when julia is embedded in a C app,
  but we want to embed C into julia.
  However, assuming `jl_invoke, jl_apply` do the rooting for us (or we have to do it manually),
  how do we tell that it should use the julia process/thread from which we have called
  the stencil?
  No, we don't. Instead we just have to 'link' the stencil code with the current `libjulia`
  that is running the process.

- Found `Core.Intrinsics`. See also `src/intrinsics.cpp` which contains codegen to emit
  operations that work on unboxed isbits values. I think in there are the functions that
  one would like to directly copy&patch, like `+,-,*,/,etc`.

----

## Copy&Patch stencils

- How many do we need?
  (Almost) everything in julia is a method, even basics arithmetic operations like `+,-,*,/` etc.
  Maybe this helps with the complexity of the implementation in the sense that
  we do not have to generate so many stencils (manually or via templates) like in the
  ref paper. Assuming that is true, the resulting jit compiled code might perhaps then
  be faster to compile, because there are less stencils to look up, but then also
  slower to run, because the runtime has to do the lookup etc.


## More ideas

Assuming Copy&Patch can work as detailed above:
- Can we support a debugged jit compilation mode where we insert a "break point stencil"
  in between all other stencils?
  However, halting the code is just one problem. Debugging is also about reading
  (and potentially modifying) running code.
  So I guess the question is then how to retrieve debug info from such a tainted jit code?
  Furthermore, how would the performance compare with just interpreted code?
  IIUC one (not sure if major) performance hit for interpreters comes from the fact
  that it has to decide on the fly which operation is to be run next, which can become
  expensive for repeated patterns, e.g. for loops etc.
  The jitted code would have computed that once and converted them into 'machine-coded branches
  or loops' which should give it an edge, no?

---

## How to actually implement the copy&patch jit?

IIUC Python had an easier start on the cpjit, because they already had a byte code compiler available.
Given that all python code will end up in this format, one immediately knows which stencils
will be needed.
Here are resources on how Python impelemented the cpjit:
- [Discourse announcement](https://discuss.python.org/t/pep-744-jit-compilation/50756)
- [PEP 744](https://peps.python.org/pep-0744/) (also see refs linked in this PEP)
- [Initial PR](https://github.com/python/cpython/pull/113465/files)
With Julia its different, because everthing is just-ahead-of-time compiled.
There are these `Core.IntrinsicFunction` types floating around, which I think, as their name suggests,
are some intrinsics (or atomic) parts of the Julia compiler which would offer themselves for
a stencil implementation.
However, these are far viewer than the number of byte codes in Python.
I think using the number of stencils needed is not a good metric to decide which approach
is correct, because even the initial paper showed two cpjits which each used quite a different
number of stencils.

The Julia AST docs https://docs.julialang.org/en/v1/devdocs/ast/ list the available elements
one will encounter in a `CodeInfo` object, which is returned by `code_typed`.
The most important elements to handle (for now) will be
- `invoke` ... static dispatch
- `call` ... dynamic dispatch
- `Core.IntrinsicFunction` ... intrinsic methods, see `julia_internal.h` for all intrinsics.

The original paper said that the continuation passing style is very important in order to have
a performant jit. This is probably not something that is going to be changed in the Julia
compiler, hence, our version of cpjit will either have to only use continuation passing style
in the cpjit or not used it at all.
The latter choice might be a relevant option, because if you can't preserve registers in between
julia calls and cpjitted code, then it might not really help with performance again
and so what's the point of using continuation passing style then?

I would like to understand how Python handles calling into foreign C code.
I can't seem to find the right answer that I am looking for.
In particular I would like to know when Python calls to C, if the cpjit also maintains
the continuation pass style, but I think it can't really, no?
Clang does not use continuation passing style, so whatever goes on on the C side is opaque
to the Python jit.
TBH I am just guessing here. I think I should just implement the simplest thing I can and
then go from there and ask for help.

Regarding intrinsics: This post seems to convey the idea well:
https://stackoverflow.com/a/2268599
TLDR: Intrinsics are place holders for which the compiler generates code in-line
without having to fall back to source code to generate it.
If this is true, then it should make sense to generate continuation pass style
stencils for these functions.
However, what about a situtation like
```
%1 = invoke f(1,2) -> Union{Int32,Int64}
Base.add_mul(%1, %2)
```
How would be generate the right code?
I guess this would fall back to a union-split, no?
And if the union is too wide, we have to do a `jl_call` with arg-packing and
call the intrinsics?
It makes sense that a cpjit compiler is not going to fix a type instability issue.

So this means I should start the implementation with all the intrinsic stencils
(maybe use CPS) and also implement the `jl_call` fallback.


Another thought/observation:
There will be situations where I can precompute/constant-propagate certain operations
(e.g. jl_box_...), in other situations I won't.
If I can constant-propagate, then I can spare out the extra stack call -- easy.
If I can't how do I then do it? Do I use a stencil via a stack (but then its not really
a stencil anymore), or do I also patch it with a separately allocated pointer?

---

# I need a better strategy

I am quite quite confused right now. There seem to be several issues right now:
- can't ccall intrinsic's, because `Core.IntrinsicFunction` does not seem to have
  'stable' funtion pointers; instead I have to utilize stencils for this.
  But why should that not work? I have to determine the pointer in every session regardless.
  Ok, so I remember that the problem is that I can't generate a `jl_function_t *` from
  an intrinsic, that's why I have to patch stencils here. (or was it that `jl_call` failed?)
  Anyways, fine, I just use the stencils for this.
- I don't really know where to put the return values from stencils.
  I can put them onto a return stack, but I could also work with passthroughs here too.
  I think I should skip the latter for now, because I don't know yet how often I can/shall
  use the passthroughs.
  I think a good use for passthroughs might be the boxing for the intrinsic calls.
- I really need to set up tests asap. Atm nothing works reliably and it seems like I am
  exlusively fixing the same segfaults over and over.
  The number of box/unbox functions as well as intrinsics is graspable, just need to
  understand what these do.

What intrinsics are there?
- `srem,urem` ... signed/unsigned remainder (=^= modulo)
- `sdiv,udiv` ... signed/unsigned division
- `slt,ult` ... signed/unsigned less than (=^= modulo)
- `sle,ule` ... signed/unsigned less equal
- `fpiseq` ... floating pt is equal???
- `shl` ... shift left
- `lshr` ... logical shift right
- `ashr` ... arithmetic shift right
- `bswap` ... ???
- `ctpop` ... count number of set bits (count population)
- `ctlz` ... count leading zeros
- `cttz` ... count trailing zeros
- `sext` ... sign extend
- `zext` ... zero extend
- `trunc` ... truncate
- `sitofp` ... signed int to floating pt
- `uitofp` ... unsigned int to floating pt
- `fptoui` ... inserve
- `fptosi` ... inserve
- `fptrunc` ... floating point extend
- `fpext` ... floating point extend

---

# Implementing AST nodes

Atm I can deal with some :call, :invoke and Core.ReturnNodes.

But looking at Core.GotoIfNot I think we need a more sophisticated design.
The problem is that GotoIfNot brings a program counter with it,
but the current 'stack' used is just a 'chain' of stencils where the program counter
was lost.
This calls for a `Frame` object a la JuliaInterpreter.jl. Or how does interpreter.c handle this?

What are the requirements for a `Frame` object?
Atm my idea for the implementation of a GotoIfNot node would be to use a cp-stencil of the form
```
if (cond) {
  // load dest fptr
  // call fptr
} else {
  // call most recent fptr
}
```
The load above will need to ask the Frame for the fptr.
So it would suffice if we can access that from a vector of pointers, similar to how our
current stack looks like.

Ok, looking at `interpreter.c` there is also a struct to keep track of this:
```
typedef struct {
    jl_code_info_t *src; // contains the names and number of slots
    jl_method_instance_t *mi; // MethodInstance we're executing, or NULL if toplevel
    jl_module_t *module; // context for globals
    jl_value_t **locals; // slots for holding local slots and ssavalues
    jl_svec_t *sparam_vals; // method static parameters, if eval-ing a method body
    size_t ip; // Leak the currently-evaluating statement index to backtrace capture
    int preevaluation; // use special rules for pre-evaluating expressions (deprecated--only for ccall handling)
    int continue_at; // statement index to jump to after leaving exception handler (0 if none)
} interpreter_state;
```
How much of this is needed for the cpjit?

The interpreter execution in julia is done by
```
static jl_value_t *eval_body(jl_array_t *stmts, interpreter_state *s, size_t ip, int toplevel)
```
IIUC then
- `jl_array_t *stmts` are the statements to be executed (prepared as SSA form).
  This would correspond to the `@code_typed` output in my jit.
- `interpreter_state *s` is there for book keeping.
- `size_t ip` is the program counter. I think it is used to walk `*stmts`.
- `int toplevel` is just a flag that indicates if the statements are executed on the toplevel
  and so one can define methods, globals etc.
This makes sense.
So it seems that the difference between `eval_body` and my approach (inspired by Python) is that
the former has to args (stmts, ip) and the latter one (stack_pointer).
So I guess one saves an extra variable and the pointer indirection.

I think the problem with the current approach is that the stack 'shrinks',
and I thought the Python jit does that too, or is that wrong?
[Python jit does that too, see below.]
~~Would it be enough to not shrink the stack, but instead just move the pointer in it?~~
We don't shrink the stack, we just move the pointer.
I guess this would be simplified by not using such a intertwined stack where
`fptr, arglist, argnumbers, continuation` are intermixed.
Why not move that into a separate struct, because then we can just use a simple
program counter and not mess with strides/offsets?
The question is whether a struct with all those fields is enough?
I fear that these args are only used for :call, :invoke nodes.
Indeed, the Core.ReturnNode already only pushes a single fptr.
Should check again how python does that.

(This is on commit 2e7771a03d8975ee8a9918ce754c665508c3f682)
Looking at CPython again (`Python/jit.c`) things seem to have changed a bit since the last
time I looked at it, or maybe I just did not understand it correctly back then.
Nevermind, I `Python/jit.c` is really just the jit that is generating the code on runtime.
What I looked at before was in `Tools/jit/template.c`.
The cp-template defined there has the following signature
```
_Py_CODEUNIT * _JIT_ENTRY(_PyInterpreterFrame *frame, PyObject **stack_pointer, PyThreadState *tstate)
```
~~It seems that `stack_pointer` is only needed to go from one tier to another one,
and it is used to call continuations, but I can't see any loads from it.
The same seems to hold for `frame`, only used in the `exit_...` labels at the end of that function.~~
Nevermind, all argumets to `_JIT_ENTRY` are required for the actual copy-patched instructors
which are included from `Python/executor_cases.c.h`.
From what I can tell their `stack_pointer` is also a wild mixture of objects.
Does their jit see this stack pointer at all? Yes, it does.

```
_PyJIT_Compile(_PyExecutorObject *executor, const _PyUOpInstruction *trace, size_t length)
```
is the function that does online jit compilation. It is defined in `Python/jit.c`.
It roughly works like that
- it determines the number of stencils that need to be copy-patched for the given function
  that is to be compiled
- it allocs the memory for the stencils
- it walks the function to be compiled
    - it extracts the stencil group for each instruction
    - it gathers all patches to complete the stencil
- it inserts a 'fatal error' stencil at the end as a safety measure
- it stiches together the stencils with the patches
- it marks the jit memory executable
- done


`Objects/frame_layout.md` contains an explanation of the `_PyInterpreterFrame` struct.
Hmm, tough read, need to digest that first.


---

# Comparing JuliaInterpreter.jl and src/interpreter.c


From `src/interpreter.c`
```
typedef struct {
    jl_code_info_t *src; // contains the names and number of slots
    jl_method_instance_t *mi; // MethodInstance we're executing, or NULL if toplevel
    jl_module_t *module; // context for globals
    jl_value_t **locals; // slots for holding local slots and ssavalues
    jl_svec_t *sparam_vals; // method static parameters, if eval-ing a method body
    size_t ip; // Leak the currently-evaluating statement index to backtrace capture
    int preevaluation; // use special rules for pre-evaluating expressions (deprecated--only for ccall handling)
    int continue_at; // statement index to jump to after leaving exception handler (0 if none)
} interpreter_state;
```
From `JuliaInterpreter.jl/src/types.jl`
```

"""
`FrameCode` holds static information about a method or toplevel code.
One `FrameCode` can be shared by many calling `Frame`s.

Important fields:
- `scope`: the `Method` or `Module` in which this frame is to be evaluated.
- `src`: the `CodeInfo` object storing (optimized) lowered source code.
- `methodtables`: a vector, each entry potentially stores a "local method table" for the corresponding
  `:call` expression in `src` (undefined entries correspond to statements that do not
  contain `:call` expressions).
- `used`: a `BitSet` storing the list of SSAValues that get referenced by later statements.
"""
struct FrameCode
    scope::Union{Method,Module}
    src::CodeInfo
    methodtables::Vector{Union{Compiled,_DispatchableMethod{FrameCode}}} # line-by-line method tables for generic-function :call Exprs
    breakpoints::Vector{BreakpointState}
    slotnamelists::Dict{Symbol,Vector{Int}}
    used::BitSet
    generator::Bool   # true if this is for the expression-generator of a @generated function
    report_coverage::Bool
    unique_files::Set{Symbol}
end

"""
`FrameData` holds the arguments, local variables, and intermediate execution state
in a particular call frame.

Important fields:
- `locals`: a vector containing the input arguments and named local variables for this frame.
  The indexing corresponds to the names in the `slotnames` of the src. Use [`locals`](@ref)
  to extract the current value of local variables.
- `ssavalues`: a vector containing the
  [Static Single Assignment](https://en.wikipedia.org/wiki/Static_single_assignment_form)
  values produced at the current state of execution.
- `sparams`: the static type parameters, e.g., for `f(x::Vector{T}) where T` this would store
  the value of `T` given the particular input `x`.
- `exception_frames`: a list of indexes to `catch` blocks for handling exceptions within
  the current frame. The active handler is the last one on the list.
- `last_exception`: the exception `throw`n by this frame or one of its callees.
"""
struct FrameData
    locals::Vector{Union{Nothing,Some{Any}}}
    ssavalues::Vector{Any}
    sparams::Vector{Any}
    exception_frames::Vector{Int}
    current_scopes::Vector{Scope}
    last_exception::Base.RefValue{Any}
    caller_will_catch_err::Bool
    last_reference::Vector{Int}
    callargs::Vector{Any}  # a temporary for processing arguments of :call exprs
end

"""
`Frame` represents the current execution state in a particular call frame.
Fields:
- `framecode`: the [`FrameCode`](@ref) for this frame.
- `framedata`: the [`FrameData`](@ref) for this frame.
- `pc`: the program counter (integer index of the next statment to be evaluated) for this frame.
- `caller`: the parent caller of this frame, or `nothing`.
- `callee`: the frame called by this one, or `nothing`.

The `Base` functions `show_backtrace` and `display_error` are overloaded such that
`show_backtrace(io::IO, frame::Frame)` and `display_error(io::IO, er, frame::Frame)`
shows a backtrace or error, respectively, in a similar way as to how Base shows
them.
"""
mutable struct Frame
    framecode::FrameCode
    framedata::FrameData
    pc::Int
    assignment_counter::Int64
    caller::Union{Frame,Nothing}
    callee::Union{Frame,Nothing}
    last_codeloc::Int32
end
function Frame(framecode::FrameCode, framedata::FrameData, pc=1, caller=nothing)
    if length(junk_frames) > 0
        frame = pop!(junk_frames)
        frame.framecode = framecode
        frame.framedata = framedata
        frame.pc = pc
        frame.assignment_counter = 1
        frame.caller = caller
        frame.callee = nothing
        frame.last_codeloc = 0
        return frame
    else
        return Frame(framecode, framedata, pc, 1, caller, nothing, 0)
    end
end
```

Comparing these data structs we see:
- interpreter.c combines locals and ssa values into one vector `**locals`,
  whereas JuliaInterpreter.jl uses two separate fields in `FrameData`.
  Both implementations use a separate field for `sparams`.
- The `*src, *mi, *module` fields from `interpreter_state` are contained in `FrameCode`
  together with more meta data needed for debuggers (I think?).
- The programm counter `ip` in `interpreter_state` is contained in `Frame`.
- I think `preevaluation` is not present in JuliaInterpreter.jl, maybe because its deprecated?
- Not sure what `continue_at` refers to in JuliaInterpreter.jl, maybe the last element
  in `exception_frames` in FrameData?

In summary I think it is safe to say that `interpreter_state` is a condensed version
of JuliaInterpreter.jl's types. Or rather that JuliaInterpreter.jl's types are
a generalization with extra meta data added that is needed for debugger support.

I think adapting a data structure similar to `interperter_state`, if not the exact same,
should be the next attempt I start.

Atm I want to write the cpjit in Julia itself, just because I imagine it being simpler.
However, if we want to use an approach similar to `src/interpreter.c` (or Python's jit)
where the interpreter processes a C struct `interpreter_state` (or `_PyInterpreterFrame`),
then I think this implies that I need to build stencils to interact with such a struct.
Is this really what I want?
Right now I have this "monster stack_pointer" where I just push everything onto it.
This has the advantage that I can easily read/write it from both sides.
Would that be more complicated if I would do that with a struct that is shared between Julia and C?

What if I try to just convert all of `eval_body` into separate stencils?
I think this is what I should try.

---

# Mmap jit code

In #53463 I have been struggling to mmap with exec permissions on windows due to
how ACLs work. As noted by myself in that issue, the mmapping should be done using
the virtual alloc calls. This is also how CPython does it in `Python/jit.c`
(this is on commit 2e7771a03d8975ee8a9918ce754c665508c3f682)
```
static unsigned char *
jit_alloc(size_t size)
{
    assert(size);
    assert(size % get_page_size() == 0);
#ifdef MS_WINDOWS
    int flags = MEM_COMMIT | MEM_RESERVE;
    unsigned char *memory = VirtualAlloc(NULL, size, flags, PAGE_READWRITE);
    int failed = memory == NULL;
#else
    int flags = MAP_ANONYMOUS | MAP_PRIVATE;
    unsigned char *memory = mmap(NULL, size, PROT_READ | PROT_WRITE, flags, -1, 0);
    int failed = memory == MAP_FAILED;
#endif
    if (failed) {
        jit_error("unable to allocate memory");
        return NULL;
    }
    return memory;
}
```
And this is how CPython makes the code executable
```
static int
mark_executable(unsigned char *memory, size_t size)
{
    if (size == 0) {
        return 0;
    }
    assert(size % get_page_size() == 0);
    // Do NOT ever leave the memory writable! Also, don't forget to flush the
    // i-cache (I cannot begin to tell you how horrible that is to debug):
#ifdef MS_WINDOWS
    if (!FlushInstructionCache(GetCurrentProcess(), memory, size)) {
        jit_error("unable to flush instruction cache");
        return -1;
    }
    int old;
    int failed = !VirtualProtect(memory, size, PAGE_EXECUTE_READ, &old);
#else
    __builtin___clear_cache((char *)memory, (char *)memory + size);
    int failed = mprotect(memory, size, PROT_EXEC | PROT_READ);
#endif
    if (failed) {
        jit_error("unable to protect executable memory");
        return -1;
    }
    return 0;
```
Here is a SO post about `__builtin___clear_cache`: https://stackoverflow.com/questions/35741814/how-does-builtin-clear-cache-work

---

# Papers

- Self-Optimizing AST Interpreters, Wuerthinger+, 2012.
  The abstract says something about being able to avoid the cost of boxed representation of
  primmitive values. If this means what I am thinking then it should be of help.
  I read the paper, its very approachable, but not sure which parts could/should be incorporated.

---

# TODOs

- Do we need to prepare the IR similarly to the call to `jl_code_for_interpreter`
  in `src/interpreter.c`?
