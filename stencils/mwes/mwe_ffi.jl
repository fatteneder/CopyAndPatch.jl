using CopyAndPatch
using Libdl

cif = CopyAndPatch.Ffi_cif(Clonglong, (Clonglong,))
handle = dlopen(CopyAndPatch.path_libffihelpers[])
fn = dlsym(handle, :my_square)
CopyAndPatch.ffi_call(cif, fn, [123]) == 123^2
