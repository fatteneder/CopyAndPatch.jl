## TODOs

- Implement `code_native` for cpjit result.
  Maybe can utilize `llvm-mc` to do the parsing.
  Just works: `write("stencils/mwes/dump_jl_sext_int", join(string.(jl_sext_int),' '))`
  Then: `cat mwes/dump_jl_sext_int | llvm-mc --disassemble -triple=x86_64-unknown-linux-gnu`
