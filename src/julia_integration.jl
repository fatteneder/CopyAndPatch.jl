const CodegenDict = IdDict{Core.CodeInstance, Core.CodeInfo}


struct CacheOwner end
struct Interpreter <: CC.AbstractInterpreter
    world::UInt
    owner::CacheOwner
    inf_prms::CC.InferenceParams
    opt_prms::CC.OptimizationParams
    inf_cache::Vector{CC.InferenceResult}
    codegen_cache::CodegenDict

    function Interpreter(
            ;
            world::UInt = Base.get_world_counter(),
            owner::CacheOwner = CacheOwner(),
            inf_prms::CC.InferenceParams = CC.InferenceParams(),
            opt_prms::CC.OptimizationParams = CC.OptimizationParams(),
            inf_cache::Vector{CC.InferenceResult} = CC.InferenceResult[]
        )
        return new(world, owner, inf_prms, opt_prms, inf_cache, CodegenDict())
    end
end


CC.InferenceParams(interp::Interpreter) = interp.inf_prms
CC.OptimizationParams(interp::Interpreter) = interp.opt_prms
CC.get_inference_world(interp::Interpreter) = interp.world
CC.get_inference_cache(interp::Interpreter) = interp.inf_cache
CC.cache_owner(interp::Interpreter) = interp.owner
CC.codegen_cache(interp::Interpreter) = interp.codegen_cache


const MC_CACHE = IdDict{Core.CodeInstance, MachineCode}()


### adapted from CC.add_codeinsts_to_jit and kept their comments
function CC.add_codeinsts_to_jit!(interp::Interpreter, ci, source_mode::UInt8)
    @assert source_mode == CC.SOURCE_MODE_ABI
    @assert ci isa Core.CodeInstance
    ci isa Core.CodeInstance && !CC.ci_has_invoke(ci) || return ci
    codegen = CC.codegen_cache(interp)
    codegen === nothing && return ci
    inspected = IdSet{Core.CodeInstance}()
    tocompile = Vector{Core.CodeInstance}()
    push!(tocompile, ci)
    while !isempty(tocompile)
        # ci_has_real_invoke(ci) && return ci # optimization: cease looping if ci happens to get
        # compiled (not just jl_fptr_wait_for_compiled, but fully jl_is_compiled_codeinst)
        callee = pop!(tocompile)
        CC.ci_has_invoke(callee) && continue
        callee in inspected && continue
        src = get(codegen, callee, nothing)
        if !isa(src, Core.CodeInfo)
            src = @atomic :monotonic callee.inferred
            if isa(src, String)
                src = CC._uncompressed_ir(callee, src)
            end
            if !isa(src, Core.CodeInfo)
                newcallee = CC.typeinf_ext(interp, callee.def, source_mode)
                if newcallee isa Core.CodeInstance
                    callee === ci && (ci = newcallee) # ci stopped meeting the requirements after typeinf_ext last checked, try again with newcallee
                    push!(tocompile, newcallee)
                end
                if newcallee !== callee
                    push!(inspected, callee)
                end
                continue
            end
        end
        push!(inspected, callee)
        CC.collectinvokes!(tocompile, src)
        @assert src isa Core.CodeInfo
        abi = CC.ci_abi(callee)
        @assert length(abi.parameters) >= 1
        fn = abi.parameters[1]
        argtypes = Tuple(abi.parameters[i] for i in 2:length(abi.parameters))
        rettype = src.rettype
        # preserve mc
        mc = get(MC_CACHE, callee, nothing)
        if mc === nothing
            mc = jit(src, fn, rettype, argtypes)
            MC_CACHE[callee] = mc
        end
        p = invoke_pointer(mc)
        @atomic callee.invoke = p
    end
    return ci
end


### Using the example in Compiler/extra/src/CompilerDevTools.jl example to enter into our jit.
### below version adapted from 8a31ad6c4d1282d4c974ab1c357d43373ba4d578


@eval @noinline function CCPlugins.typeinf(owner::CacheOwner, mi::Core.MethodInstance, source_mode::UInt8)
    world = which(CCPlugins.typeinf, Tuple{CacheOwner, Core.MethodInstance, UInt8}).primary_world
    interp = Interpreter(; world = Base.tls_world_age(), owner)
    return Base.invoke_in_world(world, CC.typeinf_ext_toplevel, interp, mi, source_mode)
end


@eval @noinline function CCPlugins.typeinf_edge(
        ::CacheOwner, mi::Core.MethodInstance,
        parent_frame::CC.InferenceState, world::UInt, source_mode::UInt8
    )
    # TODO: This isn't quite right, we're just sketching things for now
    interp = Interpreter(; world)
    return CC.typeinf_edge(interp, mi.def, mi.specTypes, Core.svec(), parent_frame, false, false)
end


function lookup_method_instance(f, args...)
    return @ccall jl_method_lookup(
        Any[f, args...]::Ptr{Any}, (1 + length(args))::Csize_t,
        Base.tls_world_age()::Csize_t
    )::Ref{Core.MethodInstance}
end


function transform_ir_for_cpjit(ir::Compiler.IRCode)
    made_copy = false
    new_ir = ir
    for (ip, inst) in enumerate(ir.stmts)
        stmt = inst[:stmt]
        Base.isexpr(stmt, :call) || continue
        f = stmt.args[1]
        f === GlobalRef(Main, :cglobal) || continue
        symlib = stmt.args[2]
        # symlib requires a runtime call, so convert it to a separate SSA instr
        symlib isa Expr || continue
        @assert Base.isexpr(symlib, :call)
        if !made_copy
            new_ir = copy(ir)
            made_copy = true
        end
        new_inst = CC.NewInstruction(symlib, Any)
        new_ssa = CC.insert_node!(new_ir, Core.SSAValue(ip), new_inst)
        new_stmt = CC.getindex(CC.getindex(new_ir, Core.SSAValue(ip)), :stmt)
        new_stmt.args[2] = new_ssa
    end
    if made_copy
        new_ir = CC.compact!(new_ir)
    end
    return new_ir
end


# with this, code_typed(...; optimize=true, interp=Interpreter()) will run our IRCode trafo,
# but it won't for code_ircode(...; optimize=true, interp=Interpreter()) ...
function CC.optimize(interp::Interpreter, opt::CC.OptimizationState, caller::CC.InferenceResult)
    @invoke CC.optimize(interp::CC.AbstractInterpreter, opt::CC.OptimizationState, caller::CC.InferenceResult)
    return opt.optresult.ir = transform_ir_for_cpjit(opt.optresult.ir::CC.IRCode)
end


function with_new_compiler(f, args...; owner::CacheOwner = CacheOwner())
    return with_new_compiler(f, owner, args...)
end


function with_new_compiler(f, owner::CacheOwner, args...)
    isa(f, Core.Builtin) && return f(args...)
    mi = lookup_method_instance(f, args...)
    new_compiler_ci = CCPlugins.typeinf(owner, mi, CC.SOURCE_MODE_ABI)
    return invoke(f, new_compiler_ci, args...)
end
