import Core.Intrinsics
import LLVM


LLVM.InitializeNativeTarget()
LLVM.InitializeNativeAsmPrinter()


function llvm_machine()
    triple = Sys.MACHINE
    target = LLVM.Target(; triple)
    tm = LLVM.TargetMachine(target, triple)
    LLVM.asm_verbosity!(tm, true)
    return tm
end


function llvm_ir_load_stencil_hole(sym::String, ty::Type)
    llvm_ty = string(convert(LLVM.LLVMType, ty))
    global_decl = """
    @_stencil_hole_$(sym) = external dso_local constant i8, align 1
    """
    instr = """
    %$(sym)Addr = getelementptr inbounds i8, ptr %stackBase, i64 sub (i64 ptrtoint (ptr @_stencil_hole_$(sym) to i64), i64 1)
    %$(sym)Val = load $(llvm_ty), ptr %$(sym)Addr, align 8
    """
    return global_decl, instr
end
function llvm_ir_store_stencil_hole(val::String, sym::String, ty::Type)
    llvm_ty = string(convert(LLVM.LLVMType, rty))
    global_decl = """
    @_stencil_hole_$(sym) = external dso_local constant i8, align 1
    """
    instr = """
    %$(sym)Addr = getelementptr inbounds i8, ptr %stackBase, i64 sub (i64 ptrtoint (ptr @_stencil_hole_$(sym) to i64), i64 1)
    store $(llvm_ty) %$(val), ptr %$(sym)Addr, align 8
    """
    return global_decl, instr
end


function generate_intrinsic_stencil(f::Core.IntrinsicFunction, sig::Tuple)
    return LLVM.@dispose ctx=LLVM.Context() begin
        with_ctx_generate_intrinsic_stencil(f, sig)
    end
end
function with_ctx_generate_intrinsic_stencil(f::Core.IntrinsicFunction, sig::Tuple)
    f_name = lowercase(string(f))
    f_generic_name = gensym(f_name)
    sym_args = Tuple(gensym("a") for _ in 1:length(sig))
    f_generic = @eval $(f_generic_name)($(sym_args...)) = $(f)($(sym_args...))
    _, rty = only(code_typed(f_generic, sig))

    # retriev LLVM Ir
    io = IOBuffer()
    code_llvm(io, f_generic, sig)
    ir = String(take!(io))
    # convert to LLVM.Module
    mod_impl = parse(LLVM.Module, ir)
    # extract LLVM function
    idx = findfirst(collect(LLVM.functions(mod_impl))) do f
        startswith(LLVM.name(f), "julia_"*string(f_generic_name))
    end |> something
    f_impl = collect(LLVM.functions(mod_impl))[idx]
    # set name
    f_impl_name = "impl_$(f_name)_$(rty)"
    if length(sig) > 0
        f_impl_name *= "_"*join(sig, "_")
    end
    f_impl_name = lowercase(f_impl_name)
    LLVM.name!(f_impl, f_impl_name)
    # mark alwaysinline
    push!(LLVM.function_attributes(f_impl), LLVM.StringAttribute("alwaysinline"))

    # generate llvm ir for stencil holes
    input_global_decls = String[]
    input_instrs = String[]
    for (i,ty) in enumerate(sig)
        decl, instr = llvm_ir_load_stencil_hole("a$i", ty)
        push!(input_global_decls, decl)
        push!(input_instrs, instr)
    end
    llvm_rty = string(convert(LLVM.LLVMType, rty))
    f_impl_sig = "$(llvm_rty) @$(f_impl_name)("
    for (i, ty) in enumerate(sig)
        llvm_ty = string(convert(LLVM.LLVMType, ty))
        name = "a$i"
        if i > 1
            f_impl_sig *= ", "
        end
        f_impl_sig *= "$(llvm_ty) %$(name)Val"
    end
    f_impl_sig *= ")"
    call_f_impl = """
    %outputVal = call $(f_impl_sig)
    """
    sym = "output"
    output_global_decl = """
    @_stencil_hole_$(sym) = external dso_local constant i8, align 1
    """
    output_instr = """
    %$(sym)Addr = getelementptr inbounds i8, ptr %stackBase, i64 sub (i64 ptrtoint (ptr @_stencil_hole_$(sym) to i64), i64 1)
    store $(llvm_rty) %$(sym)Val, ptr %$(sym)Addr, align 8
    """

    # actual stencil code
    llvm_ir = """
    $(input_global_decls...)
    $(output_global_decl)
    @_stencil_hole_continuation = external dso_local constant i8, align 1
    declare $(f_impl_sig)

    define dso_local ghccc void @$(f_name)(
        ptr %_1, ptr %stackBase, ptr %_3, ptr %_4,
        i64 %_5, ptr %_6, i64 %_7, i64 %_8, i64 %_9, i64 %_10,
        double %_11, double %_12, double %_13, double %_14, double %_15, double %_16)
    {
    $(input_instrs...)
    $(call_f_impl)
    $(output_instr)
    musttail call ghccc void @_stencil_hole_continuation(
        ptr undef, ptr %stackBase, ptr undef, ptr undef,
        i64 undef, ptr undef, i64 undef, i64 undef, i64 undef, i64 undef,
        double undef, double undef, double undef, double undef, double undef, double undef)
    ret void
    }
    """
    mod = parse(LLVM.Module, llvm_ir)

    # link f_impl, then inline it, then remove it again
    LLVM.link!(mod, mod_impl)
    LLVM.run!("inline", mod)
    for fn in LLVM.functions(mod)
        if LLVM.name(fn) == f_impl_name
            LLVM.erase!(fn)
            break
        end
    end
    LLVM.verify(mod)

    # generate textual assembly
    tm = llvm_machine()
    s = String(LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile))

    return s
end

# Floats = (Float16,Float32,Float64,Core.BFloat16)
Floats = (Float16,Float32,Float64)
SInts = (Int8,Int16,Int32,Int64,Int128)
UInts = (UInt8,UInt16,UInt32,UInt64,UInt128)
Ints = (Bool,Int8,Int16,Int32,Int64,Int128,UInt8,UInt32,UInt64,UInt128)


    # /*  wrap and unwrap */ \
    # ADD_I(bitcast, 2) \
    # /*  arithmetic */ \
    # ADD_I(neg_int, 1) \
    # ADD_I(add_int, 2) \
    # ADD_I(sub_int, 2) \
    # ADD_I(mul_int, 2) \
    # ADD_I(sdiv_int, 2) \
    # ADD_I(udiv_int, 2) \
    # ADD_I(srem_int, 2) \
    # ADD_I(urem_int, 2) \
    # ADD_I(neg_float, 1) \
    # ADD_I(add_float, 2) \
    # ADD_I(sub_float, 2) \
    # ADD_I(mul_float, 2) \
    # ADD_I(div_float, 2) \
    # ADD_I(min_float, 2) \
    # ADD_I(max_float, 2) \
    # ADD_I(fma_float, 3) \
    # ADD_I(muladd_float, 3) \
    # /*  fast arithmetic */ \
    # ALIAS(neg_float_fast, neg_float) \
    # ALIAS(add_float_fast, add_float) \
    # ALIAS(sub_float_fast, sub_float) \
    # ALIAS(mul_float_fast, mul_float) \
    # ALIAS(div_float_fast, div_float) \
    # ALIAS(min_float_fast, min_float) \
    # ALIAS(max_float_fast, max_float) \
    # /*  same-type comparisons */ \
    # ADD_I(eq_int, 2) \
    # ADD_I(ne_int, 2) \
    # ADD_I(slt_int, 2) \
    # ADD_I(ult_int, 2) \
    # ADD_I(sle_int, 2) \
    # ADD_I(ule_int, 2) \
    # ADD_I(eq_float, 2) \
    # ADD_I(ne_float, 2) \
    # ADD_I(lt_float, 2) \
    # ADD_I(le_float, 2) \
    # ALIAS(eq_float_fast, eq_float) \
    # ALIAS(ne_float_fast, ne_float) \
    # ALIAS(lt_float_fast, lt_float) \
    # ALIAS(le_float_fast, le_float) \
    # ADD_I(fpiseq, 2) \
    # /*  bitwise operators */ \
    # ADD_I(and_int, 2) \
    # ADD_I(or_int, 2) \
    # ADD_I(xor_int, 2) \
    # ADD_I(not_int, 1) \
    # ADD_I(shl_int, 2) \
    # ADD_I(lshr_int, 2) \
    # ADD_I(ashr_int, 2) \
    # ADD_I(bswap_int, 1) \
    # ADD_I(ctpop_int, 1) \
    # ADD_I(ctlz_int, 1) \
    # ADD_I(cttz_int, 1) \
    # /*  conversion */ \
    # ADD_I(sext_int, 2) \
    # ADD_I(zext_int, 2) \
    # ADD_I(trunc_int, 2) \
    # ADD_I(fptoui, 2) \
    # ADD_I(fptosi, 2) \
    # ADD_I(uitofp, 2) \
    # ADD_I(sitofp, 2) \
    # ADD_I(fptrunc, 2) \
    # ADD_I(fpext, 2) \
    # /*  checked arithmetic */ \
    # ADD_I(checked_sadd_int, 2) \
    # ADD_I(checked_uadd_int, 2) \
    # ADD_I(checked_ssub_int, 2) \
    # ADD_I(checked_usub_int, 2) \
    # ADD_I(checked_smul_int, 2) \
    # ADD_I(checked_umul_int, 2) \
    # ADD_I(checked_sdiv_int, 2) \
    # ADD_I(checked_udiv_int, 2) \
    # ADD_I(checked_srem_int, 2) \
    # ADD_I(checked_urem_int, 2) \
    # /*  functions */ \
    # ADD_I(abs_float, 1) \
    # ADD_I(copysign_float, 2) \
    # ADD_I(flipsign_int, 2) \
    # ADD_I(ceil_llvm, 1) \
    # ADD_I(floor_llvm, 1) \
    # ADD_I(trunc_llvm, 1) \
    # ADD_I(rint_llvm, 1) \
    # ADD_I(sqrt_llvm, 1) \
    # ADD_I(sqrt_llvm_fast, 1) \
    # /*  pointer arithmetic */ \
    # ADD_I(add_ptr, 2) \
    # ADD_I(sub_ptr, 2) \
    # /*  pointer access */ \
    # ADD_I(pointerref, 3) \
    # ADD_I(pointerset, 4) \
    # /*  pointer atomics */ \
    # ADD_I(atomic_fence, 1) \
    # ADD_I(atomic_pointerref, 2) \
    # ADD_I(atomic_pointerset, 3) \
    # ADD_I(atomic_pointerswap, 3) \
    # ADD_I(atomic_pointermodify, 4) \
    # ADD_I(atomic_pointerreplace, 5) \
    # /*  c interface */ \
    # ADD_I(cglobal, 2) \
    # ALIAS(llvmcall, llvmcall) \
    # /*  cpu feature tests */ \
    # ADD_I(have_fma, 1) \
    # /*  hidden intrinsics */ \
    # ADD_HIDDEN(cglobal_auto, 1)

# runic: off
float_intrinsics = [
     (:neg_float, 1),
     (:add_float, 2),
     (:sub_float, 2),
     (:mul_float, 2),
     (:div_float, 2),
     (:min_float, 2),
     (:max_float, 2),
     (:fma_float, 3),
     (:muladd_float, 3),
     (:eq_float, 2),
     (:ne_float, 2),
     (:lt_float, 2),
     (:le_float, 2),
     (:abs_float, 1),
     (:copysign_float, 2),
]
integer_intrinsics = [
     (:neg_int, 1),
     (:add_int, 2),
     (:sub_int, 2),
     (:mul_int, 2),
     (:sdiv_int, 2),
     (:udiv_int, 2),
     (:srem_int, 2),
     (:urem_int, 2),
     (:eq_int, 2),
     (:ne_int, 2),
     (:slt_int, 2),
     (:ult_int, 2),
     (:sle_int, 2),
     (:ule_int, 2),
     (:and_int, 2),
     (:or_int, 2),
     (:xor_int, 2),
     (:not_int, 1),
     (:shl_int, 2),
     (:lshr_int, 2),
     (:ashr_int, 2),
     (:bswap_int, 1),
     (:ctpop_int, 1),
     (:ctlz_int, 1),
     (:cttz_int, 1),
     (:sext_int, 2),
     (:zext_int, 2),
     (:trunc_int, 2),
     (:checked_sadd_int, 2),
     (:checked_uadd_int, 2),
     (:checked_ssub_int, 2),
     (:checked_usub_int, 2),
     (:checked_smul_int, 2),
     (:checked_umul_int, 2),
     (:checked_sdiv_int, 2),
     (:checked_udiv_int, 2),
     (:checked_srem_int, 2),
     (:checked_urem_int, 2),
     (:flipsign_int, 2),
     (:rint_llvm, 1),
]
# runic: on

for (sym,nargs) in float_intrinsics
    intr = getproperty(Core.Intrinsics, sym)
    for ty in Floats
        sig = Tuple(ty for _ in 1:nargs)
        generate_intrinsic_stencil(intr, sig)
    end
end
# for (sym,nargs) in integer_intrinsics
#     intr = getproperty(Core.Intrinsics, sym)
#     @show intr
#     for ty in Ints
#         sig = Tuple(ty for _ in 1:nargs)
#         @show sig
#         generate_intrinsic_stencil(intr, sig)
#     end
# end
