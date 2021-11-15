set nomodeline
set relativenumber
set nowrap linebreak
set wildmenu wildignorecase
set undofile
set incsearch
set hlsearch
set ignorecase
set scrolloff=3
set pastetoggle=<F2>
set ffs=unix
set smartcase
set smartindent
set smarttab
set history=300
set tags=tags;/
set tabstop=2 shiftwidth=2 expandtab
set list listchars=tab:>\
set cursorline
set hidden
set noshowmode
set autoread

set title
set titleold="Terminal"
set titlestring=%F
set noshowmode

filetype plugin indent on

call plug#begin()
Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-cmdline'
Plug 'hrsh7th/nvim-cmp'
Plug 'quangnguyen30192/cmp-nvim-ultisnips'
Plug 'ConradIrwin/vim-bracketed-paste'
Plug 'SirVer/ultisnips'
Plug 'Yggdroot/indentLine'
Plug 'adelarsq/vim-matchit'
Plug 'airblade/vim-gitgutter'
Plug 'andrewstuart/vim-kubernetes'
Plug 'christoomey/vim-tmux-navigator'
Plug 'dhruvasagar/vim-table-mode'
Plug 'ekalinin/Dockerfile.vim'
Plug 'godlygeek/tabular'
Plug 'hashivim/vim-terraform'
Plug 'honza/vim-snippets'
Plug 'junegunn/fzf'
Plug 'junegunn/fzf.vim'
Plug 'kassio/neoterm'
Plug 'kkga/vim-envy'
Plug 'mattn/gist-vim'
Plug 'mattn/webapi-vim'
Plug 'mhinz/vim-startify'
Plug 'pangloss/vim-javascript'
Plug 'tmux-plugins/vim-tmux-focus-events'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-surround'
Plug 'vifm/vifm.vim'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'vim-scripts/grep.vim'
Plug 'w0rp/ale'
Plug '~/.config/nvim/dracula_pro'
call plug#end()

let g:dracula_colorterm = 0
colorscheme dracula_pro

if exists('$SHELL')
  set shell=$SHELL
else
  set shell=/bin/sh
endif

"" Copy/Paste/Cut
if has('unnamedplus')
  set clipboard=unnamed,unnamedplus
endif

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

" session management
let g:session_directory = "~/.config/nvim/session"
let g:session_autoload = "no"
let g:session_autosave = "no"
let g:session_command_aliases = 1

" UltiSnip trigger
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<c-b>"
let g:UltiSnipsJumpBackwardTrigger="<c-z>"

augroup terminal
  autocmd!
  autocmd TermOpen * startinsert
  autocmd TermOpen * setlocal bufhidden=delete
augroup END

"" yaml
augroup vimrc-yaml
  autocmd!
  autocmd FileType yaml setlocal tabstop=2 softtabstop=2 expandtab shiftwidth=2
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

noremap ; :
noremap j gj
noremap k gk

nnoremap <leader>t :split +terminal<CR>

noremap <c-k> <c-\><c-n>
cnoremap <c-k> <c-\><c-n>
inoremap <c-k> <c-\><c-n>
tnoremap <c-k> <c-\><c-n>

" Clipboard functionality (paste from system)
vnoremap <leader>y "+y
nnoremap <leader>y "+y
vnoremap <leader>p "+p
nnoremap <leader>p "+p

" vim-airline
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif

" airline symbols
let g:airline_symbols.branch = ''
let g:airline_symbols.linenr = ''
let g:airline_symbols.dirty = ' *'
let g:airline_symbols.readonly = ''
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#ale#enabled = 1
let g:airline_skip_empty_sections = 1

" airline theme
let g:airline_theme='dracula_pro'

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

nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>e :GFiles<CR>

"" Split
noremap <Leader>h :split<CR>
noremap <Leader>v :vsplit<CR>

" grep.vim
nnoremap <silent> <leader>f :Rgrep<CR>
let Grep_Default_Options = '-IR'
let Grep_Skip_Files = '*.log *.db'
let Grep_Skip_Dirs = '.git node_modules'

" remove trailing whitespaces
command! FixWhitespace :%s/\s\+$//e

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

set completeopt=menu,menuone,noselect

luafile ~/.config/nvim/config.lua
