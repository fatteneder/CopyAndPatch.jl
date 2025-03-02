const CodegenDict = IdDict{Core.CodeInstance, Core.CodeInfo}


struct Interpreter <: CC.AbstractInterpreter
    native::CC.NativeInterpreter
    world::UInt
    inf_prms::CC.InferenceParams
    opt_prms::CC.OptimizationParams
    cache::CodegenDict
end


function Interpreter()
    native = CC.NativeInterpreter()
    opt_prms = CC.OptimizationParams(CC.OptimizationParams(native); inlining = false)
    return Interpreter(
        native, Base.get_world_counter(), CC.InferenceParams(native), opt_prms,
        CodegenDict()
    )
end


CC.InferenceParams(interp::Interpreter) = interp.inf_prms
CC.OptimizationParams(interp::Interpreter) = interp.opt_prms
CC.get_inference_world(interp::Interpreter) = CC.get_inference_world(interp.native)
CC.get_inference_cache(interp::Interpreter) = CC.get_inference_cache(interp.native)
CC.codegen_cache(interp::Interpreter) = interp.cache
# Setting nothing here adds the compilation result to julia's builtin cache, which is needed for invoke to work
CC.cache_owner(interp::Interpreter) = nothing
# struct CacheToken
#     token::Any
# end
# CC.cache_owner(interp::Interpreter) = CacheToken(CC.cache_owner(interp.native))


function compile(@nospecialize(fn), @nospecialize(ts::Tuple))
    # query MethodInstance, there is also MethodAnalysis.methodinstance(fn, args)
    mi = FromGPUCompiler.methodinstance(typeof(fn), Base.to_tuple_type(ts))
    interp = Interpreter()
    ci = CC.typeinf_ext_toplevel(interp, mi, CC.SOURCE_MODE_ABI)
    # sanity check, from GPUCompiler.jl:src/jlgen.jl/ci_cache_populate
    cache = CC.code_cache(interp)
    world = Base.get_world_counter()
    wvc = CC.WorldView(cache, world, world)
    @assert CC.haskey(wvc, mi)
    return
end


const MC_CACHE = IdDict{Core.CodeInstance, MachineCode}()


# adapted from CC.add_codeinsts_to_jit and kept their comments
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
                    if callee === ci
                        # ci stopped meeting the requirements after typeinf_ext last checked, try again with newcallee
                        ci = newcallee
                    end
                    push!(tocompile, newcallee)
                    #else
                    #    println("warning: could not get source code for ", callee.def)
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
