# Julia language server for nvim/juliatex-lsp.lua, run with --project=nvim/lsp.
# ARGS[1]: the environment of the code at startup (nvim then sends the right one).
# Its output goes to stderr: stdout is the channel to Neovim.
#
# LanguageServer 4 runs on Julia 1.10 and 6 on 1.11+, so the Manifest belongs to one Julia
# version: resolved again (and installed) the first time, or when Julia changes
manifest = joinpath(@__DIR__, "Manifest.toml")
if !isfile(manifest) ||
   !occursin("julia_version = \"$(VERSION.major).$(VERSION.minor).", read(manifest, String))
    import Pkg
    Pkg.update(io = stderr)
end
using LanguageServer

env = get(ARGS, 1, dirname(Base.active_project()))
# On LanguageServer 4 the symbol server indexes packages in another Julia process, which
# only gets JULIA_DEPOT_PATH if it is passed here: without it, it would look for them in
# ~/.julia. LanguageServer 6 has no symbol server and no depot argument: its 4th argument
# is the error handler
if pkgversion(LanguageServer) < v"5"
    depot = get(ENV, "JULIA_DEPOT_PATH", "")
    run(LanguageServerInstance(stdin, stdout, env, depot))
else
    run(LanguageServerInstance(stdin, stdout, env))
end
