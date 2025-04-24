function llvm_machine()
    triple = Sys.MACHINE
    target = LLVM.Target(; triple)
    tm = LLVM.TargetMachine(target, triple)
    LLVM.asm_verbosity!(tm, true)
    return tm
end


struct CallSiteAttrSet
    instr::LLVM.CallInst
    idx::LLVM.API.LLVMAttributeIndex
end

"""
    function_attributes(instr::CallInst)

Get the function attributes of the given parameter of the given call instruction.

This is a mutable iterator, supporting `push!`, `append!` and `delete!`.
"""
function_attributes(instr::LLVM.CallInst) =
    CallSiteAttrSet(instr, reinterpret(LLVM.API.LLVMAttributeIndex, LLVM.API.LLVMAttributeFunctionIndex))

"""
    parameter_attributes(instr::CallInst, idx::Integer)

Get the parameter attributes of the given parameter of the given call instruction.

This is a mutable iterator, supporting `push!`, `append!` and `delete!`.
"""
parameter_attributes(instr::LLVM.CallInst, idx::Integer) =
    CallSiteAttrSet(instr, LLVM.API.LLVMAttributeIndex(idx))

"""
    return_attributes(instr::CallInst)

Get the return attributes of the given parameter of the given call instruction.

This is a mutable iterator, supporting `push!`, `append!` and `delete!`.
"""
return_attributes(instr::LLVM.CallInst) = CallSiteAttrSet(instr, LLVM.API.LLVMAttributeReturnIndex)

Base.eltype(::CallSiteAttrSet) = Attribute

function Base.collect(iter::CallSiteAttrSet)
    elems = Vector{LLVM.API.LLVMAttributeRef}(undef, length(iter))
    if length(iter) > 0
      # FIXME: this prevents a nullptr ref in LLVM similar to D26392
      LLVM.API.LLVMGetCallSiteAttributes(iter.instr, iter.idx, elems)
    end
    return LLVM.Attribute[LLVM.Attribute(elem) for elem in elems]
end

Base.push!(iter::CallSiteAttrSet, attr::LLVM.Attribute) =
    LLVM.API.LLVMAddCallSiteAttribute(iter.instr, iter.idx, attr)

Base.delete!(iter::CallSiteAttrSet, attr::LLVM.EnumAttribute) =
    LLVM.API.LLVMRemoveCallSiteEnumAttribute(iter.instr, iter.idx, kind(attr))

Base.delete!(iter::CallSiteAttrSet, attr::LLVM.TypeAttribute) =
    LLVM.API.LLVMRemoveCallSiteEnumAttribute(iter.instr, iter.idx, kind(attr))

function Base.delete!(iter::CallSiteAttrSet, attr::LLVM.StringAttribute)
    k = kind(attr)
    LLVM.API.LLVMRemoveCallSiteStringAttribute(iter.instr, iter.idx, k, length(k))
end

function Base.length(iter::CallSiteAttrSet)
    LLVM.API.LLVMGetCallSiteAttributeCount(iter.instr, iter.idx)
end
