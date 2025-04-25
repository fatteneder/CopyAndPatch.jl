function llvm_machine()
    triple = Sys.MACHINE
    target = LLVM.Target(; triple)
    tm = LLVM.TargetMachine(target, triple)
    LLVM.asm_verbosity!(tm, true)
    return tm
end
