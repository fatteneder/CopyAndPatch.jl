# Style guide

- Never use `using`, or `import` specific symbols (except submodules) from packages.
  Instead use `import Base; import Core.Compiler as CC; import REPL.InteractiveUtils`, etc.
- Global variables have to be all caps!
- Code formatting is done with `[Runic.jl](https://github.com/fredrikekre/Runic.jl)`.
  Use the provided `format` script to do the formatting (requires `Runic.jl` to be installed).
  For formatting-only commits use `format commit` to submit changes.
