function llvm_machine()
    triple = Sys.MACHINE
    target = LLVM.Target(; triple)
    tm = LLVM.TargetMachine(target, triple;
                            optlevel=LLVM.API.LLVMCodeGenLevelAggressive,
                            reloc=LLVM.API.LLVMRelocStatic,
                            code=LLVM.API.LLVMCodeModelLarge)
    LLVM.asm_verbosity!(tm, true)
    return tm
end
