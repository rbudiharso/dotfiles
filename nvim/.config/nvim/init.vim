"Credit joshdick
"Use 24-bit (true-color) mode in Vim/Neovim when outside tmux.
"If you're using tmux version 2.2 or later, you can remove the outermost $TMUX check and use tmux's 24-bit color support
"(see < http://sunaku.github.io/tmux-24bit-color.html#usage > for more information.)
if (has("nvim"))
  "For Neovim 0.1.3 and 0.1.4 < https://github.com/neovim/neovim/pull/2198 >
  let $NVIM_TUI_ENABLE_TRUE_COLOR=1
endif

" takac/vim-hardtime
" VIM the hard way
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1
let g:hardtime_ignore_quickfix = 1
let g:list_of_normal_keys = ["h", "j", "k", "l", "+", "<UP>", "<DOWN>", "<LEFT>", "<RIGHT>"]

let g:make = 'gmake'
if exists('make')
  let g:make = 'make'
endif

" minpac
packadd minpac
call minpac#init()

" minpac must have {'type': 'opt'} so that it can be loaded with `packadd`.
call minpac#add('k-takata/minpac', {'type': 'opt'})

" Add other plugins here.
call minpac#add('chrisbra/colorizer')
call minpac#add('Raimondi/delimitMate')
call minpac#add('Shougo/vimproc.vim', {'do': g:make})
call minpac#add('SirVer/ultisnips')
call minpac#add('Yggdroot/indentLine')
call minpac#add('adelarsq/vim-matchit')
call minpac#add('airblade/vim-gitgutter')
call minpac#add('andrewstuart/vim-kubernetes')
call minpac#add('ekalinin/Dockerfile.vim')
call minpac#add('honza/vim-snippets')
call minpac#add('pangloss/vim-javascript')
call minpac#add('mhinz/vim-startify')
" call minpac#add('neoclide/coc.nvim', {'branch': 'release'})
call minpac#add('racer-rust/vim-racer')
call minpac#add('rust-lang/rust.vim')
call minpac#add('sheerun/vim-polyglot')
call minpac#add('takac/vim-hardtime')
call minpac#add('tpope/vim-sensible')
call minpac#add('tpope/vim-commentary')
call minpac#add('tpope/vim-fugitive')
call minpac#add('tpope/vim-repeat')
call minpac#add('tpope/vim-rhubarb')
call minpac#add('tpope/vim-surround')
call minpac#add('tpope/vim-eunuch')
call minpac#add('vim-airline/vim-airline')
call minpac#add('vim-scripts/grep.vim')
call minpac#add('vim-scripts/vis')
call minpac#add('w0rp/ale')
call minpac#add('xolox/vim-misc')
call minpac#add('xolox/vim-session')
call minpac#add('mattn/gist-vim')
call minpac#add('mattn/webapi-vim')
call minpac#add('tmux-plugins/vim-tmux-focus-events')
call minpac#add('christoomey/vim-tmux-navigator')
call minpac#add('junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --bin' })
call minpac#add('junegunn/fzf.vim')
call minpac#add('kassio/neoterm')
call minpac#add('vimwiki/vimwiki')
call minpac#add('arcticicestudio/nord-vim')
call minpac#add('jacoborus/tender.vim')
call minpac#add('vifm/vifm.vim')

command! Pu call minpac#update()
command! Pc call minpac#clean()

" Load the plugins right now. (optional)
packloadall

" python binary path
let g:loaded_python_provider = 0
let g:python_host_prog = "~/.asdf/shims/python"
let g:python3_host_prog = '~/.asdf/shims/python'

" neoterm
let g:neoterm_default_mod = 'botright'
let g:neoterm_autoinsert = 1

" vimwiki
let g:vimwiki_list = [{'path': '~/Documents/wiki/', 'syntax': 'markdown', 'ext': '.md'}]

set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8

set hidden
set hlsearch
set incsearch
set ignorecase
set smartcase
set fileformats=unix,dos,mac

" Use modeline overrides
set modeline
set modelines=10

"" Tabs. May be overridden by autocmd rules
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab

" set number
set relativenumber

" enable true colors (24 bit color support)
set termguicolors
set cursorline

" use F5 to toggle paste mode
set pastetoggle=<F5>

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

" w0rp/ale
let g:ale_fixers = { 'javascript': [ 'eslint' ] }
let g:ale_linters = { 'javascript': [ 'eslint' ] }

" startify list of files
let g:startify_lists = [
      \ { 'type': 'dir',       'header': ['   MRU '. getcwd()] },
      \ ]
let g:startify_change_to_dir = 0
let g:startify_change_to_vcs_root = 1

" CSApprox
let g:CSApprox_loaded = 1

" IndentLine
let g:indentLine_enabled = 1
let g:indentLine_concealcursor = 0
let g:indentLine_char = '┆'
let g:indentLine_faster = 1

let Grep_Default_Options = '-IR'
let Grep_Skip_Files = '*.log *.db'
let Grep_Skip_Dirs = '.git node_modules'

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

" Clear highlighting
nnoremap <leader>c :nohl<CR>

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

" Nord theme
let g:nord_cursor_line_number_background = 1
let g:nord_italic = 1
let g:nord_italic_comments = 1
augroup nord-theme-overrides
  autocmd!
  autocmd ColorScheme nord highlight Normal guibg=black
  autocmd ColorScheme nord highlight LineNr guibg=black guifg=#7f828a
  autocmd ColorScheme nord highlight CursorLine guibg=#2e3440
augroup END
colorscheme tender

" neoclide/coc.nvim
" use <c-space>for trigger completion
inoremap <silent><expr> <c-space> coc#refresh()
inoremap <expr> <Tab> pumvisible() ? "\<C-n>" : "\<Tab>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
inoremap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
autocmd! CompleteDone * if pumvisible() == 0 | pclose | endif

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

" no one is really happy until you have this shortcuts
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

" remove trailing whitespaces
command! FixWhitespace :%s/\s\+$//e

"*****************************************************************************
"" Functions
"*****************************************************************************
if !exists('*s:setupWrapping')
  function s:setupWrapping()
    set wrap
    set wm=2
    set textwidth=79
  endfunction
endif

"*****************************************************************************
"" Autocmd Rules
"*****************************************************************************
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

"*****************************************************************************
"" Mappings
"*****************************************************************************

"" Split
noremap <Leader>h :<C-u>split<CR>
noremap <Leader>v :<C-u>vsplit<CR>

"" Git
noremap <Leader>ga :Gwrite<CR>
noremap <Leader>gc :Gcommit<CR>
noremap <Leader>gsh :Gpush<CR>
noremap <Leader>gll :Gpull<CR>
noremap <Leader>gs :Gstatus<CR>
noremap <Leader>gb :Gblame<CR>
noremap <Leader>gd :Gvdiff<CR>
noremap <Leader>gr :Gremove<CR>

" session management
nnoremap <leader>so :OpenSession<Space>
nnoremap <leader>ss :SaveSession<Space>
nnoremap <leader>sd :DeleteSession<CR>
nnoremap <leader>sc :CloseSession<CR>

"" Tabs
nnoremap <Tab> gt
nnoremap <S-Tab> gT
nnoremap <silent> <S-t> :tabnew<CR>

"" Set working directory
nnoremap <leader>. :lcd %:p:h<CR>

" ripgrep
if executable('rg')
  let $FZF_DEFAULT_COMMAND = 'rg --files --hidden --follow --glob "!.git/*"'
  set grepprg=rg\ --vimgrep
  command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>).'| tr -d "\017"', 1, <bang>0)
endif

cnoremap <C-P> <C-R>=expand("%:p:h") . "/" <CR>
nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>e :FZF -m<CR>
" Recovery commands from history through FZF
nmap <leader>y :History:<CR>

" snippets
let g:UltiSnipsExpandTrigger="<tab>"
let g:UltiSnipsJumpForwardTrigger="<tab>"
let g:UltiSnipsJumpBackwardTrigger="<c-b>"
let g:UltiSnipsEditSplit="vertical"

" Vmap for maintain Visual Mode after shifting > and <
vmap < <gv
vmap > >gv

"" Move visual block
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

"" Open current line on GitHub
nnoremap <Leader>o :.Gbrowse<CR>

"*****************************************************************************
"" Custom configs
"*****************************************************************************

" rust
" Vim racer
au FileType rust nmap gd <Plug>(rust-def)
au FileType rust nmap gs <Plug>(rust-def-split)
au FileType rust nmap gx <Plug>(rust-def-vertical)
au FileType rust nmap <leader>gd <Plug>(rust-doc)

autocmd BufNewFile,BufRead *.js,*.jsx,*.vue setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2

augroup completion_preview_close
  autocmd!
  if v:version > 703 || v:version == 703 && has('patch598')
    autocmd CompleteDone * if !&previewwindow && &completeopt =~ 'preview' | silent! pclose | endif
  endif
augroup END

" javascript
let g:javascript_enable_domhtmlcss = 1

"*****************************************************************************
"" Convenience variables
"*****************************************************************************

" vim-airline
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
let g:airline_powerline_fonts = 1

" airline symbols
let g:airline_left_sep = ''
let g:airline_left_alt_sep = '|'
let g:airline_right_sep = ''
let g:airline_right_alt_sep = '|'
let g:airline_symbols.branch = ''
let g:airline_symbols.linenr = ''
let g:airline_symbols.dirty = ' *'
let g:airline_symbols.readonly = ''
let g:airline#extensions#branch#enabled = 1
let g:airline#extensions#ale#enabled = 1
let g:airline_skip_empty_sections = 1

let g:airline_theme = 'tender'

" Term handling
" When term starts, auto go into insert mode
autocmd TermOpen * startinsert

" Turn off line numbers etc
autocmd TermOpen * setlocal listchars= nonumber norelativenumber

nnoremap <silent> <C-Space> :Tnew<CR>

noremap <silent> <M-h> :TmuxNavigateLeft<CR>
noremap <silent> <M-j> :TmuxNavigateDown<CR>
noremap <silent> <M-k> :TmuxNavigateUp<CR>
noremap <silent> <M-l> :TmuxNavigateRight<CR>

