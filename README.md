# juliatex: Julia dentro de LaTeX

Escribe el código de Julia dentro del `.tex` y, al compilar, sus resultados (texto, valores y gráficas) quedan en el PDF.
Con la opción `[md]` sale además un `.md` con los mismos resultados, listo para verse en GitHub.

**Ejemplo:** [`analisis.tex`](analisis.tex) → [`analisis.md`](analisis.md) (se ve aquí en GitHub) y [`analisis.pdf`](analisis.pdf).

[![Gráfica generada por Julia al compilar analisis.tex](amortiguada.svg)](analisis.md)

```latex
\usepackage[md]{juliatex}   % [md] es opcional: además escribe <documento>.md

\begin{juliacode}           % muestra el código y debajo su resultado
f(x) = exp(-0.1x) * sin(x)
round.(f.(0:2:8), digits = 3)
\end{juliacode}

\begin{juliarun}            % solo ejecuta (preparar datos, guardar gráficas...)
using Plots
plot(0:0.1:50, f.(0:0.1:50)); savefig("amortiguada.pdf")
\end{juliarun}

\juliagraphics[width=0.7\linewidth]{amortiguada.pdf}   % la gráfica que Julia guardó
El máximo es \juliav{round(maximum(f.(0:0.1:50)), digits = 4)}.   % valor en el texto
```

## Cómo funciona

- Todo el código comparte una sola sesión de Julia, en el orden del documento.
- Corre en el entorno del `Project.toml` del proyecto (aquí, solo `Plots`), nunca en el entorno global de Julia.
  Otra carpeta de entorno: variable `JULIATEX_PROJECT`.
- Los resultados se guardan en `.juliatex/<documento>/`: si el código no cambió, Julia no vuelve a correr y la compilación tarda lo mismo que un LaTeX normal (~2 s).
- Un servidor de Julia en segundo plano mantiene la sesión y los paquetes cargados (se apaga solo tras 30 min sin uso): si cambias el bloque *k*, solo se ejecuta de *k* en adelante.
- Un error de Julia se muestra en rojo en el documento, en el lugar del bloque, y los demás bloques siguen.
- El `.md` lo escribe pandoc (unas décimas de segundo) solo en la última pasada y solo si algo cambió.
  Las gráficas: GitHub no muestra PDF dentro de un `.md`, así que si junto a `x.pdf` hay un `x.svg` (o `x.png`), el `.md` usa ese.
  Por eso el ejemplo hace `savefig` dos veces.

## Requisitos

| | Windows | Linux |
|---|---|---|
| LaTeX con LuaLaTeX y latexmk | [TinyTeX](https://yihui.org/tinytex/) o TeX Live | TinyTeX o TeX Live (`texlive-luatex`, `latexmk`) |
| Julia ≥ 1.10 | `winget install --id JuliaLang.Juliaup` | `curl -fsSL https://install.julialang.org \| sh` |
| pandoc (solo para `[md]`) | `winget install --id JohnMacFarlane.Pandoc` | `sudo apt install pandoc` (o el de tu distribución) |
| Visor de PDF (opcional) | `winget install --id SumatraPDF.SumatraPDF` | zathura |

Con TinyTeX, los paquetes que usa el ejemplo:

```sh
tlmgr install latexmk titling babel-spanish hyphen-spanish listings
```

`julia`, `pandoc`, `lualatex` y `latexmk` tienen que estar en el `PATH`.

## Uso

```sh
git clone https://github.com/ferrerama/juliaTex
cd juliaTex
julia --project=. -e "using Pkg; Pkg.instantiate()"   # solo la primera vez (Plots tarda unos minutos)
latexmk analisis.tex
```

El `.latexmkrc` ya pide LuaLaTeX con `-shell-escape` (necesario para lanzar Julia) y le dice a LaTeX que el paquete está en `juliatex/`: no hay que instalar nada en el sistema.

Para tu propio documento, copia a su carpeta `juliatex/`, `.latexmkrc` y `Project.toml` (con los paquetes de Julia que uses).

## Neovim (opcional)

[`nvim/init.lua`](nvim/init.lua) es una configuración mínima, independiente de la tuya:

```sh
nvim -u nvim/init.lua analisis.tex
```

- La primera vez descarga [lazy.nvim](https://github.com/folke/lazy.nvim), [vimtex](https://github.com/lervag/vimtex) y el tema nord dentro de `nvim/.lazy/` (necesita `git`).
- **F5** en un `.tex`: compilación continua con latexmk y el PDF abierto en el visor; cada vez que guardas se actualizan el PDF y el `.md`.
  En un `.jl`: abre un REPL de Julia con el archivo cargado.
- Código de Julia resaltado dentro de `juliacode`/`juliarun`, ortografía en español e inglés.
- Visor: SumatraPDF en Windows (lo busca en el `PATH`, en la instalación por defecto o en la variable `SUMATRA`), zathura en Linux.

`chktexrc` (Windows) y `.chktexrc` (Linux) le dicen a chktex que el código de Julia no es texto LaTeX.

## Licencia

MIT, ver [LICENSE](LICENSE).
