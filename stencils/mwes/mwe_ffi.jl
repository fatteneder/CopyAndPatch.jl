using CopyAndPatch
using Libdl

cif = CopyAndPatch.Ffi_cif(Clonglong, (Clonglong,))
handle = dlopen(CopyAndPatch.libffihelpers_path[])
fn = dlsym(handle, :my_square)
CopyAndPatch.ffi_call(cif, fn, [123]) == 123^2
