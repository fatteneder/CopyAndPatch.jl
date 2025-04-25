import Core.Intrinsics
import LLVM

include("utils.jl")


LLVM.InitializeNativeTarget()
LLVM.InitializeNativeAsmPrinter()


function generate_ast_stencil(ir::String)
    return LLVM.@dispose ctx=LLVM.Context() builder=LLVM.IRBuilder() tm=llvm_machine() begin
        with_ctx_generate_ast_stencil(ir, builder, tm)
    end
end
function with_ctx_generate_ast_stencil(ir::String, builder::LLVM.IRBuilder, tm::LLVM.TargetMachine)
    mod = parse(LLVM.Module, ir)
    f_jitentry = LLVM.functions(mod)["_JIT_ENTRY"]
    bbs = LLVM.blocks(f_jitentry)

    # parse the ghccc stencil decl
    ir_def_stencil = """
    declare dso_local ghccc void @_JIT_STENCIL_GHCCC(
        ptr %_1, ptr %stackBase, ptr %_3, ptr %_4,
        i64 %_5, ptr %_6, i64 %_7, i64 %_8, i64 %_9, i64 %_10,
        double %_11, double %_12, double %_13, double %_14, double %_15, double %_16)
    """
    idx_stackBase = 2
    mod_def_stencil = parse(LLVM.Module, ir_def_stencil)
    f = LLVM.functions(mod_def_stencil)["_JIT_STENCIL_GHCCC"]
    prms = LLVM.parameters(f)
    ftype = LLVM.function_type(f)
    prms_types = LLVM.parameters(ftype)

    # clone ghccc stencil decl into our module
    new_f = LLVM.Function(mod, LLVM.name(f), ftype)
    LLVM.linkage!(new_f, LLVM.API.LLVMExternalLinkage)
    value_map = Dict{LLVM.Value, LLVM.Value}(LLVM.parameters(f) .=> LLVM.parameters(new_f))
    LLVM.clone_into!(new_f, f; value_map)

    # substitute the previous stencil call
    for bb in bbs
        for instr in LLVM.instructions(bb)
            instr isa LLVM.CallInst || continue
            f = LLVM.called_value(instr)
            LLVM.name(f) == "_JIT_STENCIL" || continue
            break
            LLVM.position!(builder, instr)
            arg = only(LLVM.arguments(instr))
            # copy over all function, parameter and return attributes at declaration and call site
            new_args = LLVM.Value[ LLVM.UndefValue(ty) for ty in prms_types ]
            new_args[idx_stackBase] = arg
            for attr in collect(LLVM.parameter_attributes(f, 1))
                push!(LLVM.parameter_attributes(new_f, idx_stackBase), attr)
            end
            for attr in collect(LLVM.function_attributes(f))
                push!(LLVM.function_attributes(new_f), attr)
            end
            for attr in collect(LLVM.return_attributes(f))
                push!(LLVM.return_attributes(new_f), attr)
            end
            new_instr = LLVM.call!(builder, ftype, new_f, new_args)
            for attr in collect(LLVM.argument_attributes(instr, 1))
                push!(LLVM.argument_attributes(new_instr, idx_stackBase), attr)
            end
            for attr in collect(LLVM.function_attributes(instr))
                push!(LLVM.function_attributes(new_instr), attr)
            end
            for attr in collect(LLVM.return_attributes(instr))
                push!(LLVM.return_attributes(new_instr), attr)
            end
            LLVM.replace_uses!(instr, new_instr)
            LLVM.erase!(instr)
            break
        end
    end
    LLVM.verify(mod)

    # generate textual assembly
    asm = String(LLVM.emit(tm, mod, LLVM.API.LLVMAssemblyFile))

    return asm
end

let

indir = joinpath(@__DIR__, "..", "stencils", "bin")
fname = joinpath(indir, "abi.ll")
llvm_ir = String(read(fname))
asm = generate_ast_stencil(llvm_ir)

outdir = joinpath(@__DIR__, "bin")
!isdir(outdir) && mkdir(outdir)
out_fname = joinpath(outdir, "abi")
asm_fname = out_fname*".s"
obj_fname = out_fname*".o"
json_fname = out_fname*".json"

open(asm_fname, "w") do f
    write(f, asm)
end
compile_script = joinpath(@__DIR__, "..", "stencils", "compile")
run(Cmd([compile_script, "", asm_fname, obj_fname]))
readobj_script = joinpath(@__DIR__, "..", "stencils", "readobj")
run(pipeline(Cmd([readobj_script, obj_fname]), json_fname))

end
