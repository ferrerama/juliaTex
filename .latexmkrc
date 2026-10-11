# juliatex: LuaLaTeX con -shell-escape para poder lanzar Julia desde el .tex
$pdf_mode = 4;
$lualatex = 'lualatex -shell-escape %O %S';
# El paquete viene en la carpeta juliatex/ del repositorio (no hace falta instalarlo)
ensure_path('TEXINPUTS', './juliatex//');
