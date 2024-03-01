const stencils = Dict{String,Any}()


function init_stencils()

    stencildir = joinpath(@__DIR__, "..", "stencils")
    files = readdir(stencildir, join=true)
    filter!(files) do f
        endswith(f, ".json")
    end

    empty!(stencils)
    for f in files
        s = StencilGroup(f)
        bvec = ByteVector(UInt8.(s.code.body[1]))
        bvec_data = if !isempty(s.data.body)
            ByteVector(UInt8.(s.data.body[1]))
        else
            ByteVector(0)
        end
        patch_default_deps!(bvec, bvec_data, s)

        # mmap stencils to make them executable
        buf_bvec      = mmap(Vector{UInt8}, length(bvec), shared=false, exec=true)
        buf_bvec_data = mmap(Vector{UInt8}, length(bvec_data), shared=false, exec=true)
        copy!(buf_bvec, bvec)
        copy!(buf_bvec_data, bvec_data)

        name = first(splitext(basename(f)))
        stencils[name] = (s,buf_bvec,buf_bvec_data)
    end

    return
end


function patch_default_deps!(bvec::ByteVector, bvec_data::ByteVector, s::StencilGroup)
    holes = s.code.relocations
    for h in holes
        startswith(h.symbol, "_JIT_") && continue
        ptr = if startswith(h.symbol, "jl_")
            p = dlsym(libjulia[], h.symbol, throw_error=false)
            if isnothing(p)
                p = dlsym(libjuliainternal[], h.symbol)
            end
            p
        elseif startswith(h.symbol, ".rodata")
            @assert h.addend+1 < length(bvec_data)
            pointer(bvec_data.d, h.addend+1)
        else
            dlsym(libc[], h.symbol)#, throw_error=false)
            # @assert !isnothing(p)
            # p
        end
        bvec[h.offset+1] = ptr
    end
end


const Stack = Vector{Ptr{UInt64}}


function jit(@nospecialize(fn::Function), @nospecialize(args))

    init_stencils()

    optimize = true
    code = code_typed(fn, args; optimize)
    @assert length(code) == 1
    codeinfo = code[1].first
    ret = code[1].second

    stack = Stack()
    # -1 because first arg is the function
    nargs = isnothing(codeinfo.slottypes) ? 0 : length(codeinfo.slottypes)-1
    args = ByteVector(nargs*sizeof(Ptr{UInt64}))
    nssas = length(codeinfo.ssavaluetypes)
    ssas = ByteVector(nssas*sizeof(Ptr{UInt64}))
    for ex in reverse(codeinfo.code)
        display(ex)
        emitcode!(stack, args, ssas, ex)
    end

    return stack, args, ssas
end


# CodeInfo can contain following symbols
# (from https://juliadebug.github.io/JuliaInterpreter.jl/stable/ast/)
# - %2 ... single static assignment (SSA) value
#          see CodeInfo.ssavaluetypes, CodeInfo.ssaflags
# - _2 ... slot variable; either a function argument or a local variable
#          _1 refers to function, _2 to first arg, etc.
#          see CodeInfo.slottypes, CodeInfo.slotnames
#
# Our calling convention:
# stack[end-3] = continuation_ptr
# stack[end-2] = fn_ptr
# stack[end-3] = pointer(boxes(args))
# stack[end]   = nargs
#
# TODO Does the jit code need to handle argstack?
emitcode!(stack::Stack, args::ByteVector, ssas::ByteVector, ex) = TODO(typeof(ex))
function emitcode!(stack::Stack, args::ByteVector, ssas::ByteVector, ex::Core.ReturnNode)
    _, bvec, _ = stencils["jit_end"]
    push!(stack, pointer(bvec))
end
function emitcode!(stack::Stack, args::ByteVector, ssas::ByteVector, ex::Expr)
    if isexpr(ex, :call)
        fn = ex.args[1]
        fn_ptr = pointer_from_function(fn)
        push!(stack, fn_ptr)
        ex_args = @view ex.args[2:end]
        boxes = Ptr{UInt64}[]
        for a in ex_args
            if a isa Core.Argument
                push!(boxes, pointer(args, UInt64, a.n))
            elseif a isa Core.SSAValue
                push!(boxes, pointer(ssas, UInt64, a.id))
            else
                push!(boxes, box(a))
            end
        end
        push!(stack, pointer(boxes))
        nargs = length(args)
        push!(stack, UInt64(nargs))
        _, bvec, _ = stencils["jit_call"]
        push!(stack, pointer(bvec))
    else
        TODO(ex.head)
    end
end
