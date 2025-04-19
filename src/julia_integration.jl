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
    interp = Interpreter(; world=Base.tls_world_age(), owner)
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
    @ccall jl_method_lookup(Any[f, args...]::Ptr{Any}, (1+length(args))::Csize_t,
                            Base.tls_world_age()::Csize_t)::Ref{Core.MethodInstance}
end


function CC.transform_result_for_cache(
        interp::Interpreter, result::CC.InferenceResult, edges::CC.SimpleVector
    )
    return @invoke CC.transform_result_for_cache(interp::CC.AbstractInterpreter,
                                                 result::CC.InferenceResult,
                                                 edges::CC.SimpleVector)
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
