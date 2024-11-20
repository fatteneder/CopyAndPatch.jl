#include <julia.h>
#include <julia_internal.h>
#include <stdlib.h>

// @cfunctions provided from the Julia side

// which jl types do I need on this side?
// code.body =^= char *
// code =^= jl_value_t
// Stencil.relocations =^= Vector{Hole}
//    -> Hole.kind, Hole.symbol

jl_array_t *(*cpjit_mmap)(size_t);
jl_value_t *(*cpjit_get_stencil_name)(jl_value_t *ex);
jl_array_t *(*cpjit_get_stencil_body)(jl_value_t *name);
jl_array_t *(*cpjit_get_stencil_holes)(jl_value_t *name);

typedef struct {
   jl_value_t *rettype;
   jl_value_t *specTypes;
   jl_code_info_t *codeinfo;

   // alloced
   char *buf;
   uint64_t **slots;
   uint64_t **ssas;
   jl_array_t *static_prms;
   jl_array_t *gc_roots;

   int exc_thrown;
   int phioffset;
} cpjit_machinecode_t;

// TODO Homogenize this, e.g. try to use C native types only
typedef struct {
    int64_t offset;
    jl_value_t *kind;
    int64_t value;
    jl_value_t *symbol;
    int64_t addend;
} cpjit_hole;

cpjit_machinecode_t *cpjit_new_machinecode(
      jl_value_t *rettype, jl_value_t *specTypes,
      jl_code_info_t *codeinfo,
      size_t nbytes, size_t nslots, size_t nssas)
{
   cpjit_machinecode_t *mc = (cpjit_machinecode_t *)malloc(sizeof(cpjit_machinecode_t));
   if (!mc) { jl_errorf("failed to alloc mc"); }

   mc->rettype = rettype;
   mc->specTypes = specTypes;
   mc->codeinfo = codeinfo;

   /** mc->buf = (char *)malloc(sizeof(char)*nbytes); */
   /** if (!mc->buf) { jl_errorf("failed to alloc buf"); } */
   mc->buf = (char *)cpjit_mmap(nbytes);
   if (!mc->buf) { jl_errorf("failed to mmap buf"); }
   mc->slots = (uint64_t **)malloc(sizeof(uint64_t *)*nslots);
   if (!mc->slots) { jl_errorf("failed to alloc slots"); }
   mc->ssas = (uint64_t **)malloc(sizeof(uint64_t *)*nssas);
   if (!mc->ssas) { jl_errorf("failed to alloc ssas"); }
   // TODO Alloc static_prms, gc_roots arrays
   /** mc->static_prms = NULL; */
   /** mc->gc_roots = NULL; */

   mc->exc_thrown = 0;
   mc->phioffset = 0;

   return mc;
}

void cpjit_free_machinecode(cpjit_machinecode_t *mc)
{
   if (mc) {
      if (mc->buf) free(mc->buf); mc->buf = NULL;
      if (mc->slots) free(mc->slots); mc->slots = NULL;
      if (mc->ssas) free(mc->ssas); mc->ssas = NULL;
      if (mc->static_prms) free(mc->static_prms); mc->static_prms = NULL;
      if (mc->gc_roots) free(mc->gc_roots); mc->gc_roots = NULL;
      free(mc);
   }
}

static void get_stencil_name(jl_value_t *ex, char *stencil_name)
{

}

static void emit_code(cpjit_machinecode_t *mc, int ip, jl_value_t *expr, int *stencil_starts);

int cpjit_compile(jl_code_instance_t *ci, jl_code_info_t *src)
{
   size_t nslots = jl_array_len(src->slotnames);
   size_t nssas = jl_array_len(src->ssavaluetypes);
   size_t nstencils = jl_array_len(src->code);
   int *stencil_starts = (int *)malloc(sizeof(int)*nstencils);
   size_t nbytes = 0;
   jl_value_t *stencil_name;
   for (size_t i = 0; i < nstencils; i++) {
      jl_value_t *ex = jl_array_ptr_ref(src->code, i);
      stencil_starts[i] = nbytes;
      JL_GC_PUSH1(stencil_name);
      cpjit_get_stencil_body(stencil_name);
      jl_array_t *body = cpjit_get_stencil_body(name);
      JL_GC_POP();
      nbytes += jl_array_len(body);
   }
   cpjit_machinecode_t *mc = cpjit_new_machinecode(
         ci->rettype, ci->def->specTypes, src,
         nbytes, nslots, nssas
   );
   for (size_t ip = 0; ip < nslots; ip++) {
      emit_code(mc, ip, (jl_value_t *)jl_array_ptr_ref(src->code, ip), stencil_starts);
   }
   free(stencil_starts); stencil_starts = NULL;
   return 0;
}

static void _patch(char *buf, int st_ip, jl_value_t *code, char *name, uint64_t val)
{
   void *src;
   size_t n, offset;
   memcpy(buf+offset, src, n);
}
#define patch(buf, st_ip, code, name, val) \
   _patch(buf, st_ip, code, name, (uint64_t)val)

static void *box_arg(jl_value_t *ex, cpjit_machinecode_t *mc) {
   if (jl_is_argument(ex)) {
      ssize_t n = jl_slot_number(ex)-1;
      return mc->slots[n];
   } else if (jl_is_ssavalue(ex)) {
      ssize_t id = ((jl_ssavalue_t*)ex)->id - 1;
      return mc->ssas[id];
   } else {
      if (jl_is_nothing(ex)) {
         jl_array_t *a = jl_alloc_array_1d((jl_value_t *)jl_nothing_type, 1);
         // TODO safe address
         /** jl_array_ptr_1d_append(mc->static_prms, (jl_value_t *)a); */
      /** } else if (jl_is_quotenode(ex) || jl_is_type(ex)) { */
      } else {
         jl_errorf("unkown ex");
      }
      return (void *)jl_array_ptr_ref(mc->static_prms, jl_array_len(mc->static_prms)-1);
   }
}

static jl_array_t *box_args(jl_array_t *exs, cpjit_machinecode_t *mc) {
   // TODO
   return NULL;
}

// TODO ips should be size_t
static void emit_code(cpjit_machinecode_t *mc, int ip, jl_value_t *ex, int *stencil_starts)
{
   int idx;
   jl_errorf("WE ARE HERE");
   jl_value_t *stencil_data = cpjit_get_stencil(ex);
   jl_value_t *bvec = jl_get_nth_field(stencil_data, 1);
   jl_value_t *code = jl_get_nth_field(stencil_data, 2);
   int st_ip = stencil_starts[ip];
   memcpy(mc->buf+st_ip, bvec, jl_array_len(bvec));
   if (jl_is_enternode(ex)) {
      void *new_scope = NULL;
      idx = jl_field_index(jl_enternode_type, jl_symbol("scope"), 0/*err*/);
      if (idx != -1 && jl_field_isdefined(ex, idx)) new_scope = box_arg(jl_get_nth_field(ex, idx), mc);
      uint64_t *ret = mc->ssas[ip];
      idx = jl_field_index(jl_enternode_type, jl_symbol("catch_dest"), 1/*err*/);
      int catch_ip = jl_unbox_int32(jl_get_nth_field(ex, idx))-1;
      int leave_ip = catch_ip-1;
      patch(mc->buf, st_ip, code, "_JIT_IP",          ip);
      patch(mc->buf, st_ip, code, "_JIT_NEW_SCOPE",   new_scope);
      patch(mc->buf, st_ip, code, "_JIT_RET",         ret);
      patch(mc->buf, st_ip, code, "_JIT_EXC_THROWN",  &mc->exc_thrown);
      patch(mc->buf, st_ip, code, "_JIT_CALL",        mc->buf+stencil_starts[ip+1]);
      patch(mc->buf, st_ip, code, "_JIT_CONT_LEAVE",  mc->buf+stencil_starts[leave_ip]);
      patch(mc->buf, st_ip, code, "_JIT_CONT_CATCH",  mc->buf+stencil_starts[catch_ip]);
   } else if (jl_is_globalref(ex)) {
      jl_value_t *val = box_arg(ex, mc);
      void *ret = mc->ssas[ip];
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
      patch(mc->buf, st_ip, code, "_JIT_VAL",  (void *)val);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_gotoifnot(ex)) {
      idx = jl_field_index(jl_gotoifnot_type, jl_symbol("cond"), 0/*err*/);
      void *test = box_arg(jl_get_nth_field(ex, idx), mc);
      idx = jl_field_index(jl_gotoifnot_type, jl_symbol("dest"), 0/*err*/);
      int ip_dest = jl_unbox_int32(jl_get_nth_field(ex, idx))-1;
      patch(mc->buf, st_ip, code, "_JIT_IP",    ip);
      patch(mc->buf, st_ip, code, "_JIT_TEST",  test);
      patch(mc->buf, st_ip, code, "_JIT_CONT1", mc->buf+stencil_starts[ip_dest]);
      patch(mc->buf, st_ip, code, "_JIT_CONT2", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_gotonode(ex)) {
      idx = jl_field_index(jl_gotonode_type, jl_symbol("label"), 0/*err*/);
      int ip_label = jl_unbox_int32(jl_get_nth_field(ex, idx))-1;
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip_label]);
   } else if (jl_is_phinode(ex)) {
      // TODO
   } else if (jl_is_phicnode(ex)) {
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_pinode(ex)) {
      // https://docs.julialang.org/en/v1/devdocs/ssair/#Phi-nodes-and-Pi-nodes
      // PiNodes are ignored in the interpreter, so ours also only copy values into ssas[ip]
      idx = jl_field_index(jl_pinode_type, jl_symbol("val"), 1/*err*/);
      void *val = box_arg(jl_get_nth_field(ex, idx), mc);
      void *ret = mc->ssas[ip];
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
      patch(mc->buf, st_ip, code, "_JIT_VAL",  val);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_returnnode(ex)) {
      void *val = NULL;
      idx = jl_field_index(jl_returnnode_type, jl_symbol("val"), 0/*err*/);
      if (idx != -1 && jl_field_isdefined(ex, idx)) val = box_arg(jl_get_nth_field(ex, idx), mc);
      void *ret = mc->ssas[ip];
      patch(mc->buf, st_ip, code, "_JIT_IP",  ip);
      patch(mc->buf, st_ip, code, "_JIT_RET", ret);
      patch(mc->buf, st_ip, code, "_JIT_VAL", val);
   } else if (jl_is_upsilonnode(ex)) {
      void *val = NULL;
      idx = jl_field_index(jl_upsilonnode_type, jl_symbol("val"), 0/*err*/);
      if (idx != -1 && jl_field_isdefined(ex, idx)) val = box_arg(jl_get_nth_field(ex, idx), mc);
      int n_code = jl_array_len(code), ssa_ip = ip, ret_ip = -1;
      for (int i = ip+1; i<n_code && ret_ip < 0; i++) {
         jl_value_t *e = jl_array_ptr_ref(code, i);
         if (jl_is_phicnode(e)) {
            idx = jl_field_index(jl_phicnode_type, jl_symbol("values"), 1/*err*/);
            jl_value_t *values = jl_get_nth_field(e, idx);
            for (int j = 0; j < jl_array_len((jl_array_t *)values); j++) {
               int v = jl_unbox_int32(jl_array_ptr_ref(values, i));
               if (v == ssa_ip) ret_ip = j + ip;
            }
         }
      }
      assert(ret_ip >= 0);
      void *ret = mc->ssas[ret_ip];
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
      patch(mc->buf, st_ip, code, "_JIT_VAL",  val);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_nothing(ex)) {
      patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
      patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
   } else if (jl_is_expr(ex)) {
      jl_sym_t *head = ((jl_expr_t*)ex)->head;
      if (head == jl_call_sym) {
         // TODO
        /** g = ex.args[1] */
        /** fn = g isa GlobalRef ? unwrap(g) : g */
        /** if fn isa Core.IntrinsicFunction */
        /**     ex_args = @view ex.args[2:end] */
        /**     nargs = length(ex_args) */
        /**     boxes = box_args(ex_args, mc) */
        /**     push!(mc.gc_roots, boxes) */
        /**     retbox = pointer(mc.ssas, ip) */
        /**     name = string("jl_", Symbol(fn)) */
        /**     st, bvec, _ = get(STENCILS[], name) do */
        /**         error("don't know how to handle intrinsic $name") */
        /**     end */
        /**     copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec)) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP", Cint(ip)) */
        /**     for n in 1:nargs */
        /**         patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_A$n", boxes[n]) */
        /**     end */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",  retbox) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT", pointer(mc.buf, mc.stencil_starts[ip+1])) */
        /** # elseif iscallable(fn) || g isa Core.SSAValue */
        /** else */
        /**     nargs = length(ex.args) */
        /**     boxes = box_args(ex.args, mc) */
        /**     push!(mc.gc_roots, boxes) */
        /**     retbox = pointer(mc.ssas, ip) */
        /**     copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec)) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",    pointer(boxes)) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",      Cint(ip)) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",   nargs) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",     retbox) */
        /**     patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",    pointer(mc.buf, mc.stencil_starts[ip+1])) */
        /** # else */
        /** #     TODO(fn) */
        /** end */
      } else if (head == jl_invoke_sym) {
         idx = jl_field_index(jl_expr_type, jl_symbol("args"), 1/*err*/);
         jl_array_t *args = (jl_array_t *)jl_get_nth_field(ex, idx);
         jl_value_t *mi = jl_array_ptr_ref(args, 0);
         jl_value_t *g  = jl_array_ptr_ref(args, 1);
         assert((jl_datatype_t *)jl_typeof(mi) == jl_method_instance_type);
         jl_array_t *boxes = box_args(args, mc);
         jl_array_ptr_1d_append(mc->gc_roots, boxes);
         size_t n_args = jl_array_len(boxes);
         void *retbox = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_ARGS",  jl_array_ptr(boxes));
         patch(mc->buf, st_ip, code, "_JIT_IP",    ip);
         patch(mc->buf, st_ip, code, "_JIT_NARGS", n_args);
         patch(mc->buf, st_ip, code, "_JIT_RET",   retbox);
         patch(mc->buf, st_ip, code, "_JIT_CONT",  mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_new_sym) {
         idx = jl_field_index(jl_expr_type, jl_symbol("args"), 1/*err*/);
         jl_array_t *args = (jl_array_t *)jl_get_nth_field(ex, idx);
         jl_array_t *boxes = box_args(args, mc);
         jl_array_ptr_1d_append(mc->gc_roots, boxes);
         size_t n_args = jl_array_len(boxes);
         void *retbox = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_ARGS",  jl_array_ptr(boxes));
         patch(mc->buf, st_ip, code, "_JIT_IP",    ip);
         patch(mc->buf, st_ip, code, "_JIT_NARGS", n_args);
         patch(mc->buf, st_ip, code, "_JIT_RET",   retbox);
         patch(mc->buf, st_ip, code, "_JIT_CONT",  mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_foreigncall_sym) {
         // TODO
        /** fname, libname = if ex.args[1] isa QuoteNode */
        /**     ex.args[1].value, nothing */
        /** elseif ex.args[1] isa Expr */
        /**     @assert Base.isexpr(ex.args[1], :call) */
        /**     @assert ex.args[1].args[2] isa QuoteNode */
        /**     ex.args[1].args[2].value, ex.args[1].args[3] */
        /** elseif ex.args[1] isa Core.SSAValue || ex.args[1] isa Core.Argument */
        /**     ex.args[1], nothing */
        /** else */
        /**     fname = ex.args[1].args[2].value */
        /**     libname = if ex.args[1].args[3] isa GlobalRef */
        /**         unwrap(ex.args[1].args[3]) */
        /**     else */
        /**         unwrap(ex.args[1].args[3].args[2]) */
        /**     end */
        /**     fname, libname */
        /** end */
        /** rettype = ex.args[2] */
        /** argtypes = ex.args[3] */
        /** nreq = ex.args[4] */
        /** @assert length(argtypes) ≥ nreq */
        /** conv = ex.args[5] */
        /** @assert conv isa QuoteNode */
        /** @assert conv.value === :ccall || first(conv.value) === :ccall */
        /** args = ex.args[6:5+length(ex.args[3])] */
        /** gc_roots = ex.args[6+length(ex.args[3])+1:end] */
        /** boxes = box_args(args, mc) */
        /** boxed_gc_roots = box_args(gc_roots, mc) */
        /** push!(mc.gc_roots, boxes) */
        /** push!(mc.gc_roots, boxed_gc_roots) */
        /** nargs = length(boxes) */
        /** retbox = pointer(mc.ssas, ip) */
        /** ffi_argtypes = [ Cint(ffi_ctype_id(at)) for at in argtypes ] */
        /** push!(mc.gc_roots, ffi_argtypes) */
        /** ffi_rettype = Cint(ffi_ctype_id(rettype, return_type=true)) */
        /** # push!(mc.gc_roots, ffi_rettype) # kept alive through FFI_TYPE_CACHE */
        /** sz_ffi_arg = Csize_t(ffi_rettype == -2 ? sizeof(rettype) : sizeof_ffi_arg()) */
        /** ffi_retval = Vector{UInt8}(undef, sz_ffi_arg) */
        /** push!(mc.gc_roots, ffi_retval) */
        /** rettype_ptr = pointer_from_objref(rettype) */
        /** cif = Ffi_cif(rettype, tuple(argtypes...)) */
        /** push!(mc.gc_roots, cif) */
        /** # set up storage for cargs array */
        /** # - the first nargs elements hold pointers to the values */
        /** # - the remaning elements are storage for pass-by-value arguments */
        /** sz_cboxes = sizeof(Ptr{UInt64})*nargs */
        /** for (i,ffi_at) in enumerate(ffi_argtypes) */
        /**     if 0 ≤ ffi_at ≤ 10 || ffi_at == -2 */
        /**         at = argtypes[i] */
        /**         @assert sizeof(at) > 0 */
        /**         sz_cboxes += sizeof(at) */
        /**     end */
        /** end */
        /** cboxes = ByteVector(sz_cboxes) */
        /** push!(mc.gc_roots, cboxes) */
        /** offset = sizeof(Ptr{UInt64})*nargs+1 */
        /** for (i,ffi_at) in enumerate(ffi_argtypes) */
        /**     if 0 ≤ ffi_at ≤ 10 || ffi_at == -2 */
        /**         at = argtypes[i] */
        /**         cboxes[UInt64,i] = pointer(cboxes,UInt8,offset) */
        /**         offset += sizeof(at) */
        /**     end */
        /** end */
        /** sz_argtypes = Cint[ ffi_argtypes[i] == -2 ? sizeof(argtypes[i]) : 0 for i in 1:nargs ] */
        /** push!(mc.gc_roots, sz_argtypes) */
        /** static_f = true */
        /** fptr = if isnothing(libname) */
        /**     if fname isa Symbol */
        /**         h = dlopen(dlpath("libjulia.so")) */
        /**         p = dlsym(h, fname, throw_error=false) */
        /**         if isnothing(p) */
        /**             h = dlopen(dlpath("libjulia-internal.so")) */
        /**             p = dlsym(h, fname) */
        /**         end */
        /**         p */
        /**     else */
        /**         static_f = false */
        /**         box_arg(fname, mc) */
        /**     end */
        /** else */
        /**     if libname isa GlobalRef */
        /**         libname = unwrap(libname) */
        /**     elseif libname isa Expr */
        /**         @assert Base.isexpr(libname, :call) */
        /**         @show libname.args */
        /**         libname = unwrap(libname.args[2]) */
        /**     end */
        /**     dlsym(dlopen(libname isa Ref ? libname[] : libname), fname) */
        /** end */
        /** copyto!(mc.buf, mc.stencil_starts[ip], bvec, 1, length(bvec)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGS",        pointer(boxes)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CARGS",       pointer(cboxes)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CIF",         pointer(cif)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_F",           fptr) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_STATICF",     Cint(static_f)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_GCROOTS",     pointer(boxed_gc_roots)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NGCROOTS",    Cint(length(boxed_gc_roots))) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_IP",          Cint(ip)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_ARGTYPES",    pointer(ffi_argtypes)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_SZARGTYPES",  pointer(sz_argtypes)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPE",     ffi_rettype) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RETTYPEPTR",  rettype_ptr) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_FFIRETVAL",   pointer(ffi_retval)) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_NARGS",       nargs) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_RET",         retbox) */
        /** patch!(mc.buf, mc.stencil_starts[ip], st.code, "_JIT_CONT",        pointer(mc.buf, mc.stencil_starts[ip+1])) */
      } else if (head == jl_boundscheck_sym) {
         void *ret = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
         patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
         patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_leave_sym) {
         idx = jl_field_index(jl_expr_type, jl_symbol("args"), 1/*err*/);
         jl_array_t *args = (jl_array_t *)jl_get_nth_field(ex, idx);
         size_t n_args = jl_array_len(args), hand_n_leave = 0;
         for (size_t i = 0; i < n_args; i++) {
            jl_value_t *a = jl_array_ptr_ref(args, i);
            if (!jl_is_nothing(a)) {
               idx = jl_field_index(jl_enternode_type, jl_symbol("id"), 1/*err*/);
               jl_value_t *aa = jl_array_ptr_ref(code, idx);
               if (!jl_is_nothing(aa)) hand_n_leave += 1;
            }
         }
         patch(mc->buf, st_ip, code, "_JIT_IP",           ip);
         patch(mc->buf, st_ip, code, "_JIT_HAND_N_LEAVE", hand_n_leave);
         patch(mc->buf, st_ip, code, "_JIT_EXC_THROWN",   &mc->exc_thrown);
         patch(mc->buf, st_ip, code, "_JIT_CONT",         mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_pop_exception_sym) {
         idx = jl_field_index(jl_expr_type, jl_symbol("args"), 1/*err*/);
         jl_array_t *args = (jl_array_t *)jl_get_nth_field(ex, idx);
         jl_value_t *e = jl_array_ptr_ref(args, 0);
         assert(jl_is_ssavalue(e));
         idx = jl_field_index(jl_ssavalue_type, jl_symbol("id"), 1/*err*/);
         int id = jl_unbox_int32(jl_get_nth_field(e, idx));
         void *prev_state = mc->ssas[id];
         patch(mc->buf, st_ip, code, "_JIT_IP",         ip);
         patch(mc->buf, st_ip, code, "_JIT_PREV_STATE", prev_state);
         patch(mc->buf, st_ip, code, "_JIT_CONT",       mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_exc_sym) {
         void *ret = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
         patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
         patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
      } else if (head == jl_throw_undef_if_not_sym) {
         idx = jl_field_index(jl_expr_type, jl_symbol("args"), 1/*err*/);
         jl_array_t *args = (jl_array_t *)jl_get_nth_field(ex, idx);
         void *var  = box_arg(jl_array_ptr_ref(args, 0), mc);
         void *cond = box_arg(jl_array_ptr_ref(args, 1), mc);
         void *ret = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
         patch(mc->buf, st_ip, code, "_JIT_COND", cond);
         patch(mc->buf, st_ip, code, "_JIT_VAR",  var);
         patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
         patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);

      } else if (head == jl_meta_sym || head == jl_coverageeffect_sym || head == jl_inbounds_sym || head == jl_loopinfo_sym ||
             head == jl_aliasscope_sym || head == jl_popaliasscope_sym || head == jl_inline_sym || head == jl_noinline_sym) {
      } else if (head == jl_meta_sym || head == jl_coverageeffect_sym || head == jl_inbounds_sym ||
                 head == jl_loopinfo_sym || head == jl_aliasscope_sym || head == jl_popaliasscope_sym ||
                 head == jl_inline_sym || head == jl_noinline_sym ||
                 head == jl_gc_preserve_begin_sym || head == jl_gc_preserve_end_sym) {
         void *ret = mc->ssas[ip];
         patch(mc->buf, st_ip, code, "_JIT_IP",   ip);
         patch(mc->buf, st_ip, code, "_JIT_RET",  ret);
         patch(mc->buf, st_ip, code, "_JIT_CONT", mc->buf+stencil_starts[ip+1]);
      } else {
         jl_errorf("don't know how to patch this ast expr node TODO");
      }
   } else {
      jl_errorf("don't know how to patch this ast node TODO");
   }
   return;
   jl_errorf("unknown ast node");
}

jl_value_t *cpjit_call(cpjit_machinecode_t *mc, jl_value_t *args)
{
   return NULL;
}
