# juliatex: Julia inside LaTeX

[![CI](https://github.com/ferrerama/juliaTex/actions/workflows/CI.yml/badge.svg)](https://github.com/ferrerama/juliaTex/actions/workflows/CI.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Julia](https://img.shields.io/badge/Julia-1.10%2B-9558B2?logo=julia)](https://julialang.org)

Write Julia code inside your `.tex` and, when you compile, its results (text, values and plots) end up in the PDF.
With the `[md]` option you also get a `.md` with the same results, ready to be viewed on GitHub.

**Example:** a company valuation (cost of capital, DCF, sensitivity) with [CorporateFinance.jl](https://github.com/ferrerama/CorporateFinance.jl):
[`example/analysis.tex`](example/analysis.tex) → [`analysis.md`](example/analysis.md) (rendered right here on GitHub) and [`analysis.pdf`](example/analysis.pdf).

[![Valuation bridge built by Julia when compiling analysis.tex](example/resources/bridge.gif)](example/analysis.md)

```latex
\usepackage[md]{juliatex}   % [md] is optional: also writes <document>.md

\begin{juliacode}           % shows the code and its output below it
using CorporateFinance
fcf = [120_000, 135_000, 150_000, 160_000, 170_000]
r = dcf_valuation(fcf; wacc = 0.0959, g = 0.02)
\end{juliacode}

\begin{juliarun}            % only runs it (prepare data, save plots...)
using Plots
bar(1:5, fcf); savefig("resources/fcf.pdf")
\end{juliarun}

\juliagraphics[width=0.7\linewidth]{resources/fcf.pdf}   % the plot Julia saved
The enterprise value is \juliav{round(Int, r.enterprise_value)}.   % a value in the text
```

## Layout

| | |
|---|---|
| `juliatex/` | The package: `juliatex.sty`, its Lua and Julia parts, and the pandoc filter for `[md]` |
| `example/` | A complete example: `analysis.tex` and its results (`analysis.md`, `analysis.pdf`, plots in `resources/`) |
| `example/Project.toml` | The Julia environment of the example (`CorporateFinance` and `Plots`) |
| `example/.latexmkrc` | LuaLaTeX with `-shell-escape`, and tells LaTeX where the package is |
| `nvim/` | Optional minimal Neovim setup |
| `.github/workflows/CI.yml` | Compiles the example on every push (Linux and Windows) |

## How it works

- All code shares a single Julia session, in document order.
- It runs in the environment of the project's `Project.toml` (in the example, `CorporateFinance` and `Plots`), never in Julia's global environment.
  For another environment folder: the `JULIATEX_PROJECT` variable.
- Outputs are stored in `.juliatex/<document>/`: if the code did not change, Julia does not run again and compiling takes as long as plain LaTeX (~2 s).
- A background Julia server keeps the session and packages loaded (it shuts down by itself after 30 min idle): if you change block *k*, only blocks *k* onwards run.
- A Julia error is shown in red in the document, where the block is, and the other blocks keep running.
- pandoc writes the `.md` (a few tenths of a second) only on the last pass and only if something changed.
  Plots: GitHub does not show PDF inside a `.md`, so if there is an `x.svg` (or `x.png`) next to `x.pdf`, the `.md` uses that one.
  That is why the example calls `savefig` twice.

## Requirements

| | Windows | Linux |
|---|---|---|
| LaTeX with LuaLaTeX and latexmk | [TinyTeX](https://yihui.org/tinytex/) or TeX Live | `sudo apt install texlive-luatex texlive-latex-extra latexmk` (or TinyTeX) |
| Julia ≥ 1.10 | `winget install --id JuliaLang.Juliaup` | `curl -fsSL https://install.julialang.org \| sh` |
| pandoc ≥ 3 (only for `[md]`) | `winget install --id JohnMacFarlane.Pandoc` | `sudo apt install pandoc` (Ubuntu 24.04 or later) |
| PDF viewer (optional) | `winget install --id SumatraPDF.SumatraPDF` | zathura |

With TinyTeX, the packages the example uses:

```sh
tlmgr install latexmk titling listings
```

`julia`, `pandoc`, `lualatex` and `latexmk` must be on the `PATH`.
With MiKTeX instead of TinyTeX, latexmk also needs Perl (for example [Strawberry Perl](https://strawberryperl.com/)).

## Usage

```sh
git clone https://github.com/ferrerama/juliaTex
cd juliaTex/example
julia --project=. -e "using Pkg; Pkg.instantiate()"   # first time only (Plots takes a few minutes)
latexmk analysis.tex
```

CorporateFinance.jl is not in the General registry yet: `Project.toml` points to its GitHub repository (`[sources]`, Julia 1.11+).
On Julia 1.10, install it first with `julia --project=. -e "using Pkg; Pkg.add(url=\"https://github.com/ferrerama/CorporateFinance.jl\")"`.

The `.latexmkrc` already asks for LuaLaTeX with `-shell-escape` (needed to launch Julia) and tells LaTeX the package is in `../juliatex/`: nothing has to be installed system-wide.

> [!WARNING]
> `-shell-escape` lets the document run programs on your computer, and the Julia code in a `.tex` runs with your user's permissions.
> Only compile documents you trust, as you would only run scripts you trust.

The CI workflow compiles the example from scratch on Linux and Windows, with Julia 1.10 (LTS) and the latest 1.x.

For your own document, start from a copy of `example/` and point the `TEXINPUTS` line of its `.latexmkrc` to wherever `juliatex/` is; list the Julia packages you use in `Project.toml`.

## Neovim (optional)

[`nvim/init.lua`](nvim/init.lua) is a minimal setup, independent of your own:

```sh
cd example
nvim -u ../nvim/init.lua analysis.tex
```

- The first time it downloads [lazy.nvim](https://github.com/folke/lazy.nvim), [vimtex](https://github.com/lervag/vimtex) and the nord theme into `nvim/.lazy/` (needs `git`).
- **F5** in a `.tex`: continuous build with latexmk and the PDF open in the viewer; every save updates the PDF and the `.md`.
  In a `.jl`: opens a Julia REPL with the file loaded.
- Julia code highlighted inside `juliacode`/`juliarun`, English spell checking.
- Viewer: SumatraPDF on Windows (looked up on the `PATH`, in the default install, or in the `SUMATRA` variable), zathura on Linux.

`example/chktexrc` (Windows) and `example/.chktexrc` (Linux) tell chktex that Julia code is not LaTeX text.

## License

MIT, see [LICENSE](LICENSE).
