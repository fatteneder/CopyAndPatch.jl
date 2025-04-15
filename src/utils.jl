@nospecialize
TODO() = error("Not implemented yet")
TODO(msg) = TODO("Not implemented yet: ", msg)
TODO(prefix, msg) = error(prefix, msg)
@specialize


is_little_endian() = ENDIAN_BOM == 0x04030201


# from stencils/libjuliahelpers.c
is_method_instance(mi) = @ccall LIBJULIAHELPERS_PATH[].is_method_instance(mi::Any)::Cint
function is_bool(b)
    p = box(b)
    return GC.@preserve b @ccall LIBJULIAHELPERS_PATH[].is_bool(p::Ptr{Cvoid})::Cint
end
is_concrete_immutable(x::DataType) =
    @ccall LIBJULIAHELPERS_PATH[].jl_is_concrete_immutable(x::Any)::Bool
is_pointerfree(x::DataType) =
    @ccall LIBJULIAHELPERS_PATH[].jl_is_pointerfree(x::Any)::Bool


# @nospecialize is needed here to return the desired pointer also for immutables.
# IIUC without it jl_value_ptr will not see the immutable container and instead
# return a pointer to the first field in x.
#
# Consider this MWE:
# ```julia
# struct ImmutDummy
#   x
#   y
# end
#
# x = ImmutDummy("string", 1)
# p = @ccall jl_value_ptr(x::Any)::Ptr{Cvoid}
# p1 = value_pointer(x)
# p2 = value_pointer_without_nospecialize(x)
#
# GC.@preserve x begin
#   unsafe_string(@ccall jl_typeof_str(p::Ptr{Cvoid})::Cstring)  # "ImmutDummy"
#   unsafe_string(@ccall jl_typeof_str(p1::Ptr{Cvoid})::Cstring) # "ImmutDummy"
#   unsafe_string(@ccall jl_typeof_str(p2::Ptr{Cvoid})::Cstring) # segfaults in global scope,
#                                                                # but gives "ImmutDummy" inside
#                                                                # function
#end
# ```
# jl_value_ptr actually returns jl_value_t *, so we should be using a ::Any return type
# however, doing so would convert the returned value into a julia type
# using instead ::Ptr{Cvoid} we obtain an address that seems to be working with the rest
# FWIW this is also how its being used in code_typed outputs.
value_pointer(@nospecialize(x)) = @ccall jl_value_ptr(x::Any)::Ptr{Cvoid}


# missing a few:
# - jl_value_t *jl_box_char(uint32_t x);
# - jl_value_t *jl_box_ssavalue(size_t x);
# - jl_value_t *jl_box_slotnumber(size_t x);
#
# - void *jl_unbox_voidpointer(jl_value_t *v) JL_NOTSAFEPOINT;
# - uint8_t *jl_unbox_uint8pointer(jl_value_t *v) JL_NOTSAFEPOINT;
#
# Here is a list of default primitives:
# https://docs.julialang.org/en/v1/manual/types/#Primitive-Types
# It also contains Float16, UInt128, Int128, but we don't have box methods for them.
# Why? Because they are emulated in software?
#
# Why are there box methods for char, ssavalue, slotnumber, but no unbox methods?
#
const Boxable = Union{Bool, Int8, Int16, Int32, Int64, UInt8, UInt32, UInt64, Float32, Float64, Ptr}
const Unboxable = Union{Bool, Int8, Int16, Int32, Int64, UInt8, UInt32, UInt64, Float32, Float64}
box(x::Bool) = @ccall jl_box_bool(x::Int8)::Ptr{Cvoid}
box(x::Int8) = @ccall jl_box_int8(x::Int8)::Ptr{Cvoid}
box(x::Int16) = @ccall jl_box_int16(x::Int16)::Ptr{Cvoid}
box(x::Int32) = @ccall jl_box_int32(x::Int32)::Ptr{Cvoid}
box(x::Int64) = @ccall jl_box_int64(x::Int64)::Ptr{Cvoid}
box(x::UInt8) = @ccall jl_box_uint8(x::UInt8)::Ptr{Cvoid}
box(x::UInt16) = @ccall jl_box_uint16(x::UInt16)::Ptr{Cvoid}
box(x::UInt32) = @ccall jl_box_uint32(x::UInt32)::Ptr{Cvoid}
box(x::UInt64) = @ccall jl_box_uint64(x::UInt64)::Ptr{Cvoid}
box(x::Float32) = @ccall jl_box_float32(x::Float32)::Ptr{Cvoid}
box(x::Float64) = @ccall jl_box_float64(x::Float64)::Ptr{Cvoid}
box(x::Ptr{UInt8}) = @ccall jl_box_uint8pointer(x::Ptr{UInt8})::Ptr{Cvoid}
box(x::Ptr{T}) where {T} = @ccall jl_box_voidpointer(x::Ptr{T})::Ptr{Cvoid}
unbox(::Type{Bool}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_bool(ptr::Ptr{Cvoid})::Bool
unbox(::Type{Int8}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_int8(ptr::Ptr{Cvoid})::Int8
unbox(::Type{Int16}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_int16(ptr::Ptr{Cvoid})::Int16
unbox(::Type{Int32}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_int32(ptr::Ptr{Cvoid})::Int32
unbox(::Type{Int64}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_int64(ptr::Ptr{Cvoid})::Int64
unbox(::Type{UInt8}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_uint8(ptr::Ptr{Cvoid})::UInt8
unbox(::Type{UInt16}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_uint16(ptr::Ptr{Cvoid})::UInt16
unbox(::Type{UInt32}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_uint32(ptr::Ptr{Cvoid})::UInt32
unbox(::Type{UInt64}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_uint64(ptr::Ptr{Cvoid})::UInt64
unbox(::Type{Float32}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_float32(ptr::Ptr{Cvoid})::Float32
unbox(::Type{Float64}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_float64(ptr::Ptr{Cvoid})::Float64
unbox(::Type{Ptr{UInt8}}, ptr::Ptr{Cvoid}) = @ccall jl_unbox_uint8pointer(ptr::Ptr{UInt8})::Ptr{UInt8}
unbox(::Type{Ptr{T}}, ptr::Ptr{Cvoid}) where {T} = @ccall jl_unbox_voidpointer(ptr::Ptr{Cvoid})::Ptr{T}
# TODO This def needed?
unbox(T::Type, ptr::Integer) = unbox(T, Ptr{Cvoid}(UInt64(ptr)))


### Codegen utils


# based on julia/src/ccall.cpp:convert_cconv
function convert_cconv(lhd::Symbol)
    if lhd === :stdcall
        return :x86_stdcall, false
    elseif lhd === :cdecl || lhd === :ccall
        # `ccall` calling convention is a placeholder for when there isn't one provided
        # it is not by itself a valid calling convention name to be specified in the surface
        # syntax.
        return :cconv_c, false
    elseif lhd === :fastcall
        return :x86_fastcall, false
    elseif lhd === :thiscall
        return :x86_thiscall, false
    elseif lhd === :llvmcall
        error("ccall: CopyAndPatch can't perform llvm calls")
        return :cconv_c, true
    end
    error("ccall: invalid calling convetion $lhd")
end


# static evaluation for ccall fptr interpreter
# based on julia/src/{codegen,ccall}.cpp
static_eval(arg::Any, cinfo::Core.CodeInfo) = arg
static_eval(arg::Union{Core.Argument, Core.SlotNumber, Core.MethodInstance}, cinfo::Core.CodeInfo) = nothing
static_eval(arg::QuoteNode, cinfo::Core.CodeInfo) = getfield(arg, 1)
function static_eval(arg::Symbol, cinfo::Core.CodeInfo)
    TODO()
    method = cinfo.parent.def
    mod = method.var"module"
    bnd, bpart, bkind = get_binding_and_partition_and_kind(mod, arg, cinfo.min_world, cinfo.max_world)
    bkind_is_const = @ccall jl_bkind_is_some_constant(bkind::UInt8)::Cint
    if bpart != C_NULL && Bool(bkind_is_const)
        return bpart[].restriction
    end
    return nothing
end
function static_eval(arg::Core.SSAValue, cinfo::Core.CodeInfo)
    # TODO What to do here?
    return nothing
    # ssize_t idx = ((jl_ssavalue_t*)ex)->id - 1;
    # assert(idx >= 0);
    # if (ctx.ssavalue_assigned[idx]) {
    #     return ctx.SAvalues[idx].constant;
    # }
    # return NULL;
end
function static_eval(arg::GlobalRef, cinfo::Core.CodeInfo)
    mod, name = arg.mod, arg.name
    bnd = convert(Core.Binding, arg)
    bpart = walk_binding_partitions_all(bnd.partitions, cinfo.min_world, cinfo.max_world)
    bkind = bpart.kind
    bkind = Base.binding_kind(bpart)
    bkind_is_const = Base.is_some_const_binding(bkind)
    if bpart !== nothing && bkind_is_const
        v = bpart.restriction
        # TODO Deprecation warning
        return v
    end
    return nothing
end
function static_eval(ex::Expr, cinfo::Core.CodeInfo)
    min_world, max_world = cinfo.min_world, cinfo.max_world
    if Base.isexpr(ex, :call)
        f = static_eval(ex.args[1], cinfo)
        if f != nothing
            if length(ex.args) == 3 && (f == Core.getfield || f == Core.getglobal)
                m = static_eval(ex.args[2], cinfo)
                if m != nothing || !(m isa Module)
                    return nothing
                end
                s = static_eval(ex.args[3], cinfo)
                if s != nothing && s isa Symbol
                    bnd, bpart, bkind = get_binding_and_partition_and_kind(m, s, min_world, max_world)
                end
                if bpart != C_NULL && Bool(bkind_is_const)
                    v = bpart[].restriction
                    if v != nothing
                        @ccall jl_binding_deprecation_warning(mod::Ref{Module}, name::Symbol, bnd::Ref{Core.Binding})::Cvoid
                        println(stderr)
                    end
                    return v
                end
            elseif f == Core.Tuple || f == Core.apply_type
                n = length(ex.args) - 1
                if n == 0 && f == Core.Tuple
                    return ()
                end
                v = Vector{Any}(undef, n + 1)
                v[1] = f
                for i in 1:n
                    v[i + 1] = static_eval(ex.args[i + 1])
                    if v[i + 1] == nothing
                        return nothing
                    end
                end
            end
            return try
                Base.invoke_in_world(1, v, n + 1)
            catch
                nothing
            end
        end
    elseif Base.isexpr(ex, :static_parameter)
        idx = ex.args[1]
        mi = cinfo.parent
        if idx <= length(mi.sparam_vals)
            e = mi.sparam_vals[idx]
            return e isa TypeVar ? nothing : e
        end
    end
    return nothing
end

function walk_binding_partitions_all(
        bpart::Union{Nothing, Core.BindingPartition},
        min_world::UInt64, max_world::UInt64
    )
    while true
        if bpart === nothing
            return bpart
        end
        bkind = Base.binding_kind(bpart)
        if !Base.is_some_imported(bkind)
            return bpart
        end
        bnd = bpart.restriction
        bpart = bnd.partitions
    end
    return
end


# ccall fptr interpretation
Base.@kwdef mutable struct NativeSymArg
    jl_ptr::Any = nothing
    fptr::Ptr = C_NULL
    f_name::String = "" # if the symbol name is known
    f_lib::String = "" # if a library name is specified
    lib_expr::Ptr = C_NULL # expression to compute library path lazily
    gcroot::Any = nothing
end

function interpret_func_symbol(ex, cinfo::Core.CodeInfo; is_ccall::Bool=true)
    symarg = NativeSymArg()
    ptr = static_eval(ex, cinfo)
    if ptr === nothing
        if ex isa Expr && Base.isexpr(ex, :call) && length(ex.args) == 3 &&
                ex.args[1] isa GlobalRef && ex.args[1].mod == Core && ex.args[1].name == :tuple
            # attempt to interpret a non-constant 2-tuple expression as (func_name, lib_name()), where
            # `lib_name()` will be executed when first used.
            name_val = static_eval(ex.args[2], cinfo)
            if name_val isa Symbol
                symarg.f_name = string(name_val)
                symarg.lib_expr = value_pointer(ex.args[3])
                return symarg
            elseif name_val isa String
                symarg.f_name = string(name_val)
                symarg.gcroot = [name_val]
                symarg.lib_expr = value_pointer(ex.args[3])
                return symarg
            end
        end
        if ex isa Core.SSAValue || ex isa Core.Argument
            symarg.jl_ptr = ex
            return symarg
        end
        if !(ex isa Ptr)
            if !is_ccall
                return symarg
            end
            TODO("emit cpointer check")
        else
            TODO(ex)
        end
    else
        symarg.gcroot = ptr
        if ptr isa Tuple && length(ptr) == 1
            ptr = ptr[1]
        end
        if ptr isa Symbol
            symarg.f_name = string(ptr)
        elseif ptr isa String
            symarg.f_name = ptr
        end
        if !isempty(symarg.f_name)
            # @assert !llvmcall
            iname = string("i", symarg.f_name)
            if Libdl.dlsym(LIBJULIAINTERNAL[], iname, throw_error = false) !== nothing
                symarg.f_lib = Libdl.dlpath("libjulia-internal.so")
                symarg.f_name = iname
            else
                symarg.f_lib = Libdl.find_library(iname)
            end
        elseif ptr isa Ptr
            TODO()
            symarg.f = value_pointer(ptr)
            # else if (jl_is_cpointer_type(jl_typeof(ptr))) {
            #     fptr = *(void(**)(void))jl_data_ptr(ptr);
            # }
        elseif ptr isa Tuple && length(ptr) > 1
            t1 = ptr[1]
            if t1 isa Symbol
                symarg.f_name = string(t1)
            elseif t1 isa String
                symarg.f_name = t1
            end
            t2 = ptr[2]
            if t2 isa Symbol
                symarg.f_lib = string(t2)
            elseif t2 isa String
                symarg.f_lib = t2
            else
                TODO()
                symarg.lib_expr = t2
            end
        end
    end
    return symarg
end
