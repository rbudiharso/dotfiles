let g:python_host_prog = "~/.asdf/shims/python"

" vim-javascript
augroup vimrc-javascript
  autocmd!
  autocmd FileType javascript setl tabstop=2|setl shiftwidth=2|setl expandtab softtabstop=2
augroup END

set termguicolors
set cursorline
set relativenumber

" vim-airline/vim-airline
" vim-airline/vim-airline-themes
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
let g:airline_powerline_fonts = 1
let g:airline_symbols.branch = ''
let g:airline_symbols.dirty = ' *'
let g:airline_symbols.readonly = ''
let g:airline#extensions#tabline#enabled = 0
let g:airline_theme = 'gruvbox'

" w0rp/ale
" ALE fixers
let g:ale_fixers = {
\   'javascript': [
\       'eslint',
\   ],
\}

if has('nvim')
    " map ESC to exit terminal mode
    tnoremap <Esc> <C-\><C-n>
    tnoremap <A-[> <Esc>

    " map for moving from terminal buffer
    tnoremap <A-h> <C-\><C-n><C-w>h
    tnoremap <A-j> <C-\><C-n><C-w>j
    tnoremap <A-k> <C-\><C-n><C-w>k
    tnoremap <A-l> <C-\><C-n><C-w>l
    nnoremap <A-h> <C-w>h
    nnoremap <A-j> <C-w>j
    nnoremap <A-k> <C-w>k
    nnoremap <A-l> <C-w>l

    " Alt-R to paste from the register to terminal buffer
    tnoremap <expr> <A-r> '<C-\><C-N>"'.nr2char(getchar()).'pi'
endif

" morhetz/gruvbox
let g:gruvbox_italic=1
colorscheme gruvbox

" Use fd for ctrlp.
if executable('fd')
    let g:ctrlp_user_command = 'fd -c never "" %s'
    let g:ctrlp_use_caching = 0
endif

" takac/vim-hardtime
" VIM the hard way
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1

" whatyouhide/vim-lengthmatters
" highlight color for character past 80 column
call lengthmatters#highlight_link_to('DiffDelete')

set pastetoggle=<F5>
