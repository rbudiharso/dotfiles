" minpac
packadd minpac
call minpac#init()

" minpac must have {'type': 'opt'} so that it can be loaded with `packadd`.
call minpac#add('k-takata/minpac', {'type': 'opt'})

" Add other plugins here.
call minpac#add('zivtech/vim-base')
call minpac#add('tpope/vim-sensible')
call minpac#add('Shougo/vimproc.vim', {'do': 'make'})
call minpac#add('Yggdroot/indentLine')
call minpac#add('adelarsq/vim-matchit')
call minpac#add('airblade/vim-gitgutter')
call minpac#add('andrewstuart/vim-kubernetes')
call minpac#add('ekalinin/Dockerfile.vim')
call minpac#add('honza/vim-snippets')
call minpac#add('pangloss/vim-javascript')
call minpac#add('mhinz/vim-startify')
call minpac#add('tpope/vim-sensible')
call minpac#add('tpope/vim-commentary')
call minpac#add('tpope/vim-fugitive')
call minpac#add('tpope/vim-repeat')
call minpac#add('tpope/vim-surround')
call minpac#add('tpope/vim-eunuch')
call minpac#add('vim-airline/vim-airline')
call minpac#add('vim-airline/vim-airline-themes')
call minpac#add('vim-scripts/grep.vim')
call minpac#add('w0rp/ale')
call minpac#add('mattn/gist-vim')
call minpac#add('mattn/webapi-vim')
call minpac#add('tmux-plugins/vim-tmux-focus-events')
call minpac#add('christoomey/vim-tmux-navigator')
call minpac#add('junegunn/fzf')
call minpac#add('junegunn/fzf.vim')
call minpac#add('vifm/vifm.vim')
call minpac#add('ConradIrwin/vim-bracketed-paste')
call minpac#add('kassio/neoterm')
call minpac#add('kkga/vim-envy')
call minpac#add('dhruvasagar/vim-table-mode')
call minpac#add('sonph/onehalf', { 'subdir': 'vim' })
call minpac#add('arcticicestudio/nord-vim')

command! Pu call minpac#update()
command! Pc call minpac#clean()

" Load the plugins right now. (optional)
packloadall
packadd! dracula_pro

if (has('termguicolors'))
  set termguicolors
endif

" set persistent undo
set undofile
set undodir=~/.dotfiles/nvim/.config/nvim/undodir

" set relative number
set relativenumber

set cursorline
set scrolloff=3

"" Encoding
set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8

"" Tabs. May be overridden by autocmd rules
set tabstop=4
set softtabstop=0
set shiftwidth=4
set expandtab

"" Enable hidden buffers
set hidden

"" Searching
set hlsearch
set fileformats=unix,dos,mac

" shell
if exists('$SHELL')
    set shell=$SHELL
else
    set shell=/bin/sh
endif

" session management
let g:session_directory = "~/.config/nvim/session"
let g:session_autoload = "no"
let g:session_autosave = "no"
let g:session_command_aliases = 1
let no_buffers_menu=1

"" Use modeline overrides
set modeline
set modelines=10

set title
set titleold="Terminal"
set titlestring=%F
set noshowmode

" w0rp/ale
let g:ale_fixers = { 'javascript': [ 'eslint' ] }
let g:ale_linters = { 'javascript': [ 'eslint' ] }

" startify list of files
let g:startify_lists = [{ 'type': 'dir', 'header': ['MRU'. getcwd()] }]
let g:startify_change_to_dir = 0
let g:startify_change_to_vcs_root = 1

" IndentLine
let g:indentLine_enabled = 1
let g:indentLine_concealcursor = 0
let g:indentLine_char = '┆'
let g:indentLine_faster = 1

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

"" no one is really happy until you have this shortcuts
cnoreabbrev W! w!
cnoreabbrev Q! q!
cnoreabbrev Qall! qall!
cnoreabbrev Wq wq
cnoreabbrev Wa wa
cnoreabbrev wQ wq
cnoreabbrev WQ wq
cnoreabbrev W w
cnoreabbrev Q q
cnoreabbrev Qall qall

" grep.vim
nnoremap <silent> <leader>f :Rgrep<CR>
let Grep_Default_Options = '-IR'
let Grep_Skip_Files = '*.log *.db'
let Grep_Skip_Dirs = '.git node_modules'

" remove trailing whitespaces
command! FixWhitespace :%s/\s\+$//e

if !exists('*s:setupWrapping')
  function s:setupWrapping()
    set wrap
    set wm=2
    set textwidth=79
  endfunction
endif

" terminal emulation
nnoremap <silent> <leader>sh :terminal<CR>
augroup terminal-setting
    autocmd!
    autocmd TermOpen,TermEnter * startinsert
    autocmd TermOpen,TermEnter * setlocal scrolloff=0 listchars= nonumber norelativenumber
    autocmd TermClose,TermLeave * setlocal scrolloff=3
augroup END

augroup nord-theme-overrides
  autocmd!
  autocmd ColorScheme nord highlight Normal guibg=#121212
  autocmd ColorScheme nord highlight SignColumn guibg=#121212
  autocmd ColorScheme nord highlight CursorLine guibg=#303030
augroup END

"" The PC is fast enough, do syntax highlight syncing from start unless 200 lines
augroup vimrc-sync-fromstart
  autocmd!
  autocmd BufEnter * :syntax sync maxlines=200
augroup END

"" Remember cursor position
augroup vimrc-remember-cursor-position
  autocmd!
  autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
augroup END

"" javascript
augroup javascript-space
  autocmd!
  autocmd BufRead,BufNewFile *.js setlocal tabstop=2 shiftwidth=2 softtabstop=2 expandtab
augroup END

"" txt
augroup vimrc-wrapping
  autocmd!
  autocmd BufRead,BufNewFile *.txt call s:setupWrapping()
augroup END

"" make/cmake
augroup vimrc-make-cmake
  autocmd!
  autocmd FileType make setlocal noexpandtab
  autocmd BufNewFile,BufRead CMakeLists.txt setlocal filetype=cmake
augroup END

set autoread

"" yaml
augroup vimrc-yaml
  autocmd!
  autocmd FileType yaml setlocal tabstop=2 softtabstop=2 expandtab shiftwidth=2
augroup END

"" Split
noremap <Leader>h :split<CR>
noremap <Leader>v :vsplit<CR>

"" Git
noremap <Leader>ga :Gwrite<CR>
noremap <Leader>gc :Gcommit<CR>
noremap <Leader>gsh :Gpush<CR>
noremap <Leader>gll :Gpull<CR>
noremap <Leader>gs :Gstatus<CR>
noremap <Leader>gb :Gblame<CR>
noremap <Leader>gd :Gvdiff<CR>
noremap <Leader>gr :Gremove<CR>

"" fzf.vim
set wildmode=list:longest,list:full
set wildignore+=*.o,*.obj,.git,*.rbc,*.pyc,__pycache__
let $FZF_DEFAULT_COMMAND =  "find * -path '*/\.*' -prune -o -path 'node_modules/**' -prune -o -path 'target/**' -prune -o -path 'dist/**' -prune -o  -type f -print -o -type l -print 2> /dev/null"

" The Silver Searcher
if executable('ag')
  let $FZF_DEFAULT_COMMAND = 'ag --hidden --ignore .git -g ""'
  set grepprg=ag\ --nogroup\ --nocolor
endif

" ripgrep
if executable('rg')
  let $FZF_DEFAULT_COMMAND = 'rg --files --hidden --follow --glob "!.git/*"'
  set grepprg=rg\ --vimgrep
  command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>).'| tr -d "\017"', 1, <bang>0)
endif

cnoremap <C-P> <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>e :GFiles<CR>
"Recovery commands from history through FZF
nmap <leader>y :History:<CR>

" snippets
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<tab>"
let g:UltiSnipsJumpBackwardTrigger="<c-b>"
let g:UltiSnipsEditSplit="vertical"

" ale
let g:ale_linters = {}

"" Copy/Paste/Cut
if has('unnamedplus')
  set clipboard=unnamed,unnamedplus
endif

noremap YY "+y<CR>
noremap <leader>p "+gP<CR>
noremap XX "+x<CR>

"" Buffer nav
noremap <leader>z :bp<CR>
noremap <leader>q :bp<CR>
noremap <leader>x :bn<CR>
noremap <leader>w :bn<CR>

"" Close buffer
noremap <leader>c :bd<CR>

"" Clean search (highlight)
nnoremap <silent> <leader><space> :noh<cr>

"" Switching windows
noremap <C-j> <C-w>j
noremap <C-k> <C-w>k
noremap <C-l> <C-w>l
noremap <C-h> <C-w>h

"" Vmap for maintain Visual Mode after shifting > and <
vmap < <gv
vmap > >gv

"" Move visual block
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Vifm mapping
nnoremap <silent> - :Vifm<CR>

" Run commands with semicolon
nnoremap ; :

" Save the current buffer using the leader key
noremap <Leader>w :w<CR>

" Clipboard functionality (paste from system)
vnoremap <leader>y "+y
nnoremap <leader>y "+y
vnoremap <leader>p "+p
nnoremap <leader>p "+p

" vim-airline
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
" let g:airline_powerline_fonts = 1

" airline symbols
let g:airline_symbols.branch = ''
let g:airline_symbols.linenr = ''
let g:airline_symbols.dirty = ' *'
let g:airline_symbols.readonly = ''
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#ale#enabled = 1
let g:airline_skip_empty_sections = 1
let g:airline_theme='dracula_pro'

let g:dracula_colorterm = 0

" Visual
colorscheme dracula_pro_van_helsing

" italic for comment
" place this after colorscheme
highlight Comment cterm=italic gui=italic
highlight Normal ctermbg=none guibg=none
