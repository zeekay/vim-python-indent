setlocal nolisp
setlocal autoindent
setlocal indentkeys+=<:>,=elif,=except
au FileType python setlocal indentexpr=python_indent#get_indent(v:lnum)
