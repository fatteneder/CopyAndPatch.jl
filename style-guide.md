# Style guide

- Never use `using`, or `import` specific symbols (except submodules) from packages.
  Instead use `import Base; import Core.Compiler as CC; import REPL.InteractiveUtils`, etc.
- Global variables have to be all caps!
- Code formatting is done with `[Runic.jl](https://github.com/fredrikekre/Runic.jl)`.
  Keep code formatting changes separate from other changes.
  Use the provided `format` script to the formatting (requires `Runic.jl` to be installed).
  Use `format commit` to finish and commit the formatting changes.
