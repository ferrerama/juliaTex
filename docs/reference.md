# juliatex reference

Everything `juliatex.sty` offers, and what happens when a document compiles.
For a first look, see the [README](../README.md) and the [example](../example/analysis.tex).

## Loading the package

```latex
\usepackage{juliatex}
\usepackage[md]{juliatex}   % also writes <document>.md
```

| Option | Effect |
|---|---|
| `md` | After the last pass, writes `<document>.md` (GitHub Markdown) next to the PDF with the same Julia outputs. Needs [pandoc](https://pandoc.org) ≥ 3. See [Markdown output](#markdown-output). |

Requirements of the document:

- **LuaLaTeX** (the package stops with an error under pdfLaTeX or XeLaTeX).
- **`-shell-escape`**, so that LaTeX can launch Julia. Without it, compiling stops with an error that says what to put in `.latexmkrc`.
- A **`Project.toml`** in the document's folder or above it, or the `JULIATEX_PROJECT` variable. See [Julia environment](#julia-environment).

The package loads `iftex`, `xcolor`, `listings` and `graphicx`.

## Environments

Both environments take their lines verbatim: LaTeX never reads the code, so `%`, `#`, `_`, `\` and braces reach Julia untouched.
Put `\begin{...}` and `\end{...}` on lines of their own: the code starts on the line after `\begin` and ends at the first line that starts with `\end{...}`.

### `juliacode`

```latex
\begin{juliacode}
x = [1, 2, 3]
println("sum: ", sum(x))
x .^ 2
\end{juliacode}
```

Shows the code (highlighted) and, below it, its output:

- everything the block printed (stdout and stderr), and
- the value of the last expression, as the REPL shows it (at most 30 lines × 90 columns).
  It is not shown if it is `nothing` or if the block ends with `;`, also as in the REPL.

A block that prints nothing and ends with `;` shows only the code.

### `juliarun`

```latex
\begin{juliarun}
using Plots
p = plot(sin, 0, 2π)
savefig(p, "resources/sine.pdf");
\end{juliarun}
```

Runs the code and shows nothing: for loading packages, preparing data or saving figures.
If it fails, the error is shown in red where the block is.

## Commands

### `\juliav{expr}`

```latex
The WACC is \juliav{round(100w, digits = 2)}\,\%.
```

Inserts the value of one Julia expression into the text, as `print` writes it.
The text goes in as is, without LaTeX interpreting it: `_`, `$` or `%` in the value are printed, not executed.
For numbers, format them in Julia (`round`, `string`, `Printf.@sprintf`…).
If the expression fails, a red `error` appears in its place.

The argument has to be a single expression with balanced braces.

### `\juliagraphics[options]{file}`

```latex
\juliagraphics[width=0.7\linewidth]{resources/sine.pdf}
```

Includes a figure that Julia saves while compiling.
The options are those of `\includegraphics`, and the path is relative to the `.tex`'s folder: the code runs in that folder, so `savefig("resources/sine.pdf")` and `\juliagraphics{resources/sine.pdf}` point to the same file.

While the file does not exist yet (the first pass), a framed box with `??` and the file name holds its place.
LaTeX includes a copy kept in `.juliatex/<document>/`, so that Julia can rewrite the original during the pass without damaging the PDF being written.
It works inside `figure`, with `\caption` and `\label` as usual.

## Execution

- **One session, in order.** All blocks and `\juliav` of a document share one Julia session and run in the order they appear, so a `\juliav` can use variables from the blocks above it.
- **Errors do not stop the document.** A failing block shows `ERROR: <message>` in red and the following ones keep running. The full error with its backtrace goes to `.juliatex/<document>/julia.log`, and the LaTeX log gets a warning with the line of the block.
- **Working folder.** The code runs in the `.tex`'s folder.
- **No windows.** `GKSwstype=100` is set, so Plots (GR) saves figures without opening any windows.
- **Not on the first pass.** Julia runs at the end of a pass, so its results appear on the next one (`??` until then), just like `\ref`. latexmk does the extra passes by itself; with `lualatex` alone, compile twice.

## Julia environment

The code runs in the environment of the nearest `Project.toml`, looking from the document's folder upwards (like `julia --project=@.`), and never in Julia's global environment.
List there every package the document uses.

To use another environment, set `JULIATEX_PROJECT` to its folder.

## Caching and the Julia server

Outputs are kept in `.juliatex/<document>/`.
On each compile, juliatex compares the code of all blocks (and the environment) with the last run:

- **Nothing changed:** Julia does not run, and compiling takes as long as plain LaTeX.
- **Something changed:** the code goes to a background Julia server, which keeps one session per document with the packages already loaded. If block *k* changed, blocks 1 to *k*−1 keep their outputs and only *k* onwards run. If the first block changed, the session starts over.

The server starts by itself the first time and shuts down after 30 minutes without requests.
There is one per environment; its port is kept in `juliatex-<id>.port` in the temporary folder (`TEMP` or `TMPDIR`).
If the server cannot be used, a fresh Julia runs all the blocks instead.

The server keeps the packages that were loaded when it started: after updating or adding packages to the environment, end the background `julia` process (or wait for it to shut down) so that the next compile picks them up.

To force everything to run again, delete `.juliatex/<document>/`.

## Markdown output

With `[md]`, after the last pass pandoc turns the `.tex` into `<document>.md` (GitHub Markdown) using the outputs Julia already produced; nothing runs again.
It is rewritten only if the `.tex`, an output or a figure changed.

| In the `.tex` | In the `.md` |
|---|---|
| `juliacode` | a `julia` code block and its output |
| `juliarun` | nothing, unless it failed (then its error) |
| `\juliav{expr}` | the value |
| `\juliagraphics{x.pdf}` | the image; `x.svg` or `x.png` next to it if there is one, because GitHub does not show PDF inside a `.md` |
| `figure` with `\caption` | the image and "Figure *n*: caption" below it |
| `\ref` to a figure | its number |
| `\title`, `\author` | a top-level heading and the author; sections go down one level |
| `equation` | `$$ … $$` |

So that the `.md` shows a plot, save it twice:

```julia
savefig(p, "resources/plot.pdf")   # for the PDF
savefig(p, "resources/plot.svg")   # for the .md
```

## Environment variables

| Variable | Use |
|---|---|
| `JULIATEX_PROJECT` | Folder of the Julia environment, instead of the nearest `Project.toml` |
| `JULIATEX_PANDOC` | pandoc executable for `[md]` (default: `pandoc` on the `PATH`) |
| `TEMP` / `TMPDIR` | Where the server's port file is kept |

## Files

| File | Contents |
|---|---|
| `.juliatex/<document>/NNN.jl` | the code of block (or `\juliav`) number NNN |
| `.juliatex/<document>/NNN.out` | its output |
| `.juliatex/<document>/NNN.status` | `ok` or `error` |
| `.juliatex/<document>/julia.log` | full errors with backtraces |
| `.juliatex/<document>/fig-*` | the copies of the figures included in the PDF |
| `<document>.md` | with `[md]` |

`.juliatex/` can be deleted at any time (Julia runs again) and is best kept out of git.

## Checking with chktex

chktex would report the Julia code as LaTeX mistakes.
`juliatex/chktexrc` (Windows) and `juliatex/.chktexrc` (Linux) tell it to skip `juliacode`, `juliarun` and the argument of `\juliav`: point the `CHKTEXRC` variable to `juliatex/` (the Neovim setup does).

## Security

`-shell-escape` lets the document run programs, and the Julia code runs with your user's permissions.
Only compile documents you trust.
