if exists("g:python_indent_loaded")
    finish
endif
let g:python_indent_loaded = 1

let s:keepcpo= &cpo
set cpo&vim

" maximum number of lines to look backwards for ()
let s:maxoff = 50

function! python_indent#get_indent(lnum)
  " If this line is explicitly joined: If the previous line was also joined,
  " line it up with that one, otherwise one 'shiftwidth'.
  if getline(a:lnum - 1) =~ '\\$'
    " if a:lnum > 1 && getline(a:lnum - 2) =~ '\\$'
    "   return indent(a:lnum - 1)
    " endif
    " return indent(a:lnum - 1) + (exists("g:pyindent_continue") ? eval(g:pyindent_continue) : shiftwidth())
    return indent(a:lnum - 1)
  endif

  " If the start of the line is in a string don't change the indent.
  if has('syntax_items')
	\ && synIDattr(synID(a:lnum, 1, 1), "name") =~ "String$"
    return -1
  endif

  " Search backwards for the previous non-empty line.
  let plnum = prevnonblank(v:lnum - 1)

  if plnum == 0
    " This is the first non-empty line, use zero indent.
    return 0
  endif

  " If the previous line is inside parenthesis, use the indent of the starting
  " line.
  " Trick: use the non-existing "dummy" variable to break out of the loop when
  " going too far back.
  call cursor(plnum, 1)
  let parlnum = searchpair('(\|{\|\[', '', ')\|}\|\]', 'nbW',
	  \ "line('.') < " . (plnum - s:maxoff) . " ? dummy :"
	  \ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
	  \ . " =~ '\\(Comment\\|Todo\\|String\\)$'")
  if parlnum > 0
    let plindent = indent(parlnum)
    let plnumstart = parlnum
  else
    let plindent = indent(plnum)
    let plnumstart = plnum
  endif


  " When inside parenthesis: If at the first line below the parenthesis add
  " two 'shiftwidth', otherwise same as previous line.
  " i = (a
  "       + b
  "       + c)
  call cursor(a:lnum, 1)
  let p = searchpair('(\|{\|\[', '', ')\|}\|\]', 'bW',
	  \ "line('.') < " . (a:lnum - s:maxoff) . " ? dummy :"
	  \ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
	  \ . " =~ '\\(Comment\\|Todo\\|String\\)$'")
  if p > 0
    if p == plnum
      " When the start is inside parenthesis, only indent one 'shiftwidth'.
      let pp = searchpair('(\|{\|\[', '', ')\|}\|\]', 'bW',
	  \ "line('.') < " . (a:lnum - s:maxoff) . " ? dummy :"
	  \ . " synIDattr(synID(line('.'), col('.'), 1), 'name')"
	  \ . " =~ '\\(Comment\\|Todo\\|String\\)$'")
      if pp > 0
	    return indent(plnum) + (exists("g:pyindent_nested_paren") ? eval(g:pyindent_nested_paren) : shiftwidth())
      endif
      " Modified from built-in which does shiftwidth()*2
      return indent(plnum) + (exists("g:pyindent_open_paren") ? eval(g:pyindent_open_paren) : shiftwidth())
    endif
    if plnumstart == p
      return indent(plnum)
    endif
    return plindent
  endif


  " Get the line and remove a trailing comment.
  " Use syntax highlighting attributes when possible.
  let pline = getline(plnum)
  let pline_len = strlen(pline)
  if has('syntax_items')
    " If the last character in the line is a comment, do a binary search for
    " the start of the comment.  synID() is slow, a linear search would take
    " too long on a long line.
    if synIDattr(synID(plnum, pline_len, 1), "name") =~ "\\(Comment\\|Todo\\)$"
      let min = 1
      let max = pline_len
      while min < max
	let col = (min + max) / 2
	if synIDattr(synID(plnum, col, 1), "name") =~ "\\(Comment\\|Todo\\)$"
	  let max = col
	else
	  let min = col + 1
	endif
      endwhile
      let pline = strpart(pline, 0, min - 1)
    endif
  else
    let col = 0
    while col < pline_len
      if pline[col] == '#'
	let pline = strpart(pline, 0, col)
	break
      endif
      let col = col + 1
    endwhile
  endif

  " If the previous line ended with a colon, indent this line
  if pline =~ ':\s*$'
    return plindent + shiftwidth()
  endif

  " If the previous line was a stop-execution statement...
  if getline(plnum) =~ '^\s*\(break\|continue\|raise\|return\|pass\)\>'
    " See if the user has already dedented
    if indent(a:lnum) > indent(plnum) - shiftwidth()
      " If not, recommend one dedent
      return indent(plnum) - shiftwidth()
    endif
    " Otherwise, trust the user
    return -1
  endif

  " If the current line begins with a keyword that lines up with "try"
  if getline(a:lnum) =~ '^\s*\(except\|finally\)\>'
    let lnum = a:lnum - 1
    while lnum >= 1
      if getline(lnum) =~ '^\s*\(try\|except\)\>'
	let ind = indent(lnum)
	if ind >= indent(a:lnum)
	  return -1	" indent is already less than this
	endif
	return ind	" line up with previous try or except
      endif
      let lnum = lnum - 1
    endwhile
    return -1		" no matching "try"!
  endif

  " If the current line begins with a header keyword, dedent
  if getline(a:lnum) =~ '^\s*\(elif\|else\)\>'

    " Unless the previous line was a one-liner
    if getline(plnumstart) =~ '^\s*\(for\|if\|try\)\>'
      return plindent
    endif

    " Or the user has already dedented
    if indent(a:lnum) <= plindent - shiftwidth()
      return -1
    endif

    return plindent - shiftwidth()
  endif

  " When after a () construct we probably want to go back to the start line.
  " a = (b
  "       + c)
  " here
  if parlnum > 0
    return plindent
  endif

  return -1

endfunction

let &cpo = s:keepcpo
unlet s:keepcpo

function! s:vim_python#run_buffer(...)
    let fn = expand('%:p')
    if fn == ''
        echoerr 'Save buffer to file first'
        return
    endif

    " setup python command so virtualenv gets activated if necessary
    if exists('g:virtualenv_name')
        let cmd = 'source '.g:virtualenv_directory.'/'.g:virtualenv_name.'/bin/activate && python '
    else
        let cmd = 'python '
    endif

    " handle arguments to python script
    if a:0
        let args = ' '.join(a:000)
    else
        let args = ''
    endif

    " write file out
    exe 'w'

    " create new preview window and read results into it
    pclose! | botright 10 new
    try
        silent exe '0r! '.cmd.' '.fn.' '.args
    catch /.*/
        close
        echoerr 'Command failed'
    endtry
    redraw
    normal gg
    setlocal buftype=nofile bufhidden=delete noswapfile nowrap previewwindow
    wincmd p
endfunction

let &cpo = s:keepcpo
unlet s:keepcpo
