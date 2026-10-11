# juliatex: LuaLaTeX with -shell-escape so that the .tex can launch Julia
$pdf_mode = 4;
$lualatex = 'lualatex -shell-escape %O %S';
# The package ships in the repository's juliatex/ folder (no installation needed).
# In your own project, point this to wherever you copy juliatex/
ensure_path('TEXINPUTS', '../juliatex//');
