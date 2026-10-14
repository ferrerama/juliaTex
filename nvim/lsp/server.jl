# Julia language server for nvim/juliatex-lsp.lua, run with --project=nvim/lsp.
# ARGS[1]: the environment of the code at startup (nvim then sends the right one).
# Its output goes to stderr: stdout is the channel to Neovim.
if !isfile(joinpath(@__DIR__, "Manifest.toml"))
    import Pkg
    Pkg.instantiate(io = stderr)
end
using LanguageServer

env   = get(ARGS, 1, dirname(Base.active_project()))
# Empty: SymbolServer uses Julia's default depots
depot = get(ENV, "JULIA_DEPOT_PATH", "")

run(LanguageServerInstance(stdin, stdout, env, depot))
