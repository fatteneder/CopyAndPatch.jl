import Clang_jll
import Libffi_jll
import LLVM_jll

stencil_dir = joinpath(@__DIR__, "..", "stencils")
submod_julia_dir = joinpath(@__DIR__, "..", "julia")
vendored_julia_dir = joinpath(Sys.BINDIR, "..")

libLLVM_path = joinpath(vendored_julia_dir, "lib", "libLLVM.so")
if !isfile(libLLVM_path)
    # source builds put them into lib/julia
    libLLVM_path = joinpath(vendored_julia_dir, "lib", "julia", "libLLVM.so")
    if !isfile(libLLVM_path)
        error("can't find julia's libLLVM.so")
    end
end

clang_cmd = Clang_jll.clang()
idx = findfirst(clang_cmd.env) do e
    startswith(e, "LD_LIBRARY_PATH=")
end |> something
ld_library_path = split(clang_cmd.env[idx], "=")[2]

env = copy(ENV)
env["JULIA_REPO_SRC"] = joinpath(submod_julia_dir, "src")
env["JULIA_INCLUDE"] = joinpath(vendored_julia_dir, "include")
env["JULIA_LIB"] = joinpath(vendored_julia_dir, "lib")
env["LIBFFI_INCLUDE"] = joinpath(Libffi_jll.artifact_dir, "include")
env["READOBJ"] = joinpath(LLVM_jll.artifact_dir, "tools", "llvm-readobj")
env["DUMPOBJ"] = joinpath(LLVM_jll.artifact_dir, "tools", "llvm-dumpobj")
env["CLANG"] = joinpath(Clang_jll.clang_path)
# needed for clang
env["LD_LIBRARY_PATH"] = "$(get!(env, "LD_LIBRARY_PATH", "")):$(ld_library_path)"
# env["CLANG"] = "clang-17"
# env["READOBJ"] = "llvm-readobj-17"
# env["DUMPOBJ"] = "llvm-objdump-17"

nthreads = Sys.CPU_THREADS ÷ 2

# need to download julia's dependencies to be able to use julia internal headers in stencils
run(Cmd(`make -C $(submod_julia_dir)/deps -j$(nthreads)`))
# compile our stencils
run(Cmd(`make -C $(stencil_dir) -j$(nthreads)`; env))
