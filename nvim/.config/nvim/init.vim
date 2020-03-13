" BASIC CONFIGURATION
let g:python3_host_prog = '~/.asdf/shims/python'
let g:loaded_python_provider = 0

" Enable syntax highlighting
syntax on

filetype plugin indent on

set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8

set backspace=indent,eol,start
set hidden
set hlsearch
set incsearch
set ignorecase
set smartcase
set fileformats=unix,dos,mac
set autoread

" keep 3 lines from top/bottom when scrolling
set scrolloff=3

" Status bar
set laststatus=2

" Use modeline overrides
set modeline
set modelines=10

set title
set titleold="Terminal"
set titlestring=%F

"" Tabs. May be overridden by autocmd rules
set tabstop=2
set shiftwidth=2
set softtabstop=2
set expandtab

set ruler
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

let g:make = 'gmake'
if exists('make')
  let g:make = 'make'
endif

" takac/vim-hardtime
" VIM the hard way
let g:hardtime_default_on = 1
let g:hardtime_showmsg = 1
let g:hardtime_ignore_quickfix = 1
let g:list_of_normal_keys = ["h", "j", "k", "l", "+", "<UP>", "<DOWN>", "<LEFT>", "<RIGHT>"]

let g:python_host_prog = "~/.asdf/shims/python"

" w0rp/ale
" ALE fixers
let g:ale_fixers = {
      \   'javascript': [ 'eslint' ],
      \}

" startify list of files
let g:startify_lists = [
      \ { 'type': 'dir',       'header': ['   MRU '. getcwd()] },
      \ ]
let g:startify_change_to_dir = 0
let g:startify_change_to_vcs_root = 1

let g:CSApprox_loaded = 1

" IndentLine
let g:indentLine_enabled = 1
let g:indentLine_concealcursor = 0
let g:indentLine_char = '┆'
let g:indentLine_faster = 1

let Grep_Default_Options = '-IR'
let Grep_Skip_Files = '*.log *.db'
let Grep_Skip_Dirs = '.git node_modules'

" makes ranger show hidden files by default
let g:neoranger_opts='--cmd="set show_hidden true"'

packadd minpac

call minpac#init()

" minpac must have {'type': 'opt'} so that it can be loaded with `packadd`.
call minpac#add('k-takata/minpac', {'type': 'opt'})

" Add other plugins here.
" call minpac#add('whatyouhide/vim-lengthmatters')
call minpac#add('HerringtonDarkholme/yats.vim')
call minpac#add('Lokaltog/neoranger')
call minpac#add('Raimondi/delimitMate')
call minpac#add('Shougo/vimproc.vim', {'do': g:make})
call minpac#add('SirVer/ultisnips')
call minpac#add('Yggdroot/indentLine')
call minpac#add('adelarsq/vim-matchit')
call minpac#add('airblade/vim-gitgutter')
call minpac#add('andrewstuart/vim-kubernetes')
call minpac#add('ap/vim-css-color')
call minpac#add('ekalinin/Dockerfile.vim')
call minpac#add('fatih/vim-go', {'do': ':GoInstallBinaries'})
call minpac#add('honza/vim-snippets')
call minpac#add('pangloss/vim-javascript')
call minpac#add('leafOfTree/vim-vue-plugin')
call minpac#add('leafgarland/typescript-vim')
call minpac#add('mhinz/vim-startify')
" call minpac#add('morhetz/gruvbox')
call minpac#add('arcticicestudio/nord-vim')
" call minpac#add('Lokaltog/vim-monotone')
" call minpac#add('jacoborus/tender.vim')
call minpac#add('neoclide/coc.nvim', {'branch': 'release'})
call minpac#add('posva/vim-vue')
call minpac#add('racer-rust/vim-racer')
call minpac#add('rust-lang/rust.vim')
call minpac#add('sheerun/vim-polyglot')
call minpac#add('takac/vim-hardtime')
call minpac#add('tpope/vim-commentary')
call minpac#add('tpope/vim-fugitive')
call minpac#add('tpope/vim-repeat')
call minpac#add('tpope/vim-rhubarb')
call minpac#add('tpope/vim-surround')
call minpac#add('vim-airline/vim-airline')
call minpac#add('vim-airline/vim-airline-themes')
call minpac#add('vim-scripts/CSApprox')
call minpac#add('vim-scripts/grep.vim')
call minpac#add('vim-scripts/vis')
call minpac#add('w0rp/ale')
call minpac#add('xolox/vim-misc')
call minpac#add('xolox/vim-session')
call minpac#add('mattn/gist-vim')
call minpac#add('mattn/webapi-vim')
call minpac#add('danro/rename.vim')
call minpac#add('christoomey/vim-tmux-navigator')
call minpac#add('junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --bin' })
call minpac#add('junegunn/fzf.vim')
call minpac#add('rhysd/conflict-marker.vim')

command! Pu call minpac#update()
command! Pc call minpac#clean()

" Load the plugins right now. (optional)
packloadall

"" ADDITIONAL CONFIGURATION

" Remap Escape
inoremap jk <ESC>

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

  function! FloatingFZF(width, height, border_highlight)
    function! s:create_float(hl, opts)
      let buf = nvim_create_buf(v:false, v:true)
      let opts = extend({'relative': 'editor', 'style': 'minimal'}, a:opts)
      let win = nvim_open_win(buf, v:true, opts)
      call setwinvar(win, '&winhighlight', 'NormalFloat:'.a:hl)
      call setwinvar(win, '&colorcolumn', '')
      return buf
    endfunction

    " Size and position
    let width = float2nr(&columns * a:width)
    let height = float2nr(&lines * a:height)
    let row = float2nr((&lines - height) / 2)
    let col = float2nr((&columns - width) / 2)

    " Border
    let top = '╭' . repeat('─', width - 2) . '╮'
    let mid = '│' . repeat(' ', width - 2) . '│'
    let bot = '╰' . repeat('─', width - 2) . '╯'
    let border = [top] + repeat([mid], height - 2) + [bot]

    " Draw frame
    let s:frame = s:create_float(a:border_highlight, {'row': row, 'col': col, 'width': width, 'height': height})
    call nvim_buf_set_lines(s:frame, 0, -1, v:true, border)

    " Draw viewport
    call s:create_float('Normal', {'row': row + 1, 'col': col + 2, 'width': width - 4, 'height': height - 2})
    autocmd BufWipeout <buffer> execute 'bwipeout' s:frame
  endfunction

  let g:fzf_layout = { 'window': 'call FloatingFZF(0.9, 0.6, "Comment")' }
endif

" morhetz/gruvbox
" let g:gruvbox_italic=1
" colorscheme gruvbox

" Nord theme
let g:nord_cursor_line_number_background = 1
let g:nord_italic = 1
let g:nord_italic_comments = 1
augroup nord-theme-overrides
  autocmd!
  autocmd ColorScheme nord highlight Normal guibg=black
  autocmd ColorScheme nord highlight LineNr guibg=black
  autocmd ColorScheme nord highlight CursorLine guibg=#2e3440
augroup END
colorscheme nord

" monotone theme
" colorscheme monotone

" Open ranger at current file with "-"
nnoremap <silent> - :RangerCurrentFile<CR>

" Open ranger in current working directory
nnoremap <silent> <Leader>r :Ranger<CR>

" whatyouhide/vim-lengthmatters
" highlight color for character past 80 column
" call lengthmatters#highlight_link_to('DiffDelete')

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

if exists("*fugitive#statusline")
  set statusline+=%{fugitive#statusline()}
endif

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
" terminal emulation
" nnoremap <silent> <leader>sh :terminal<CR>


"*****************************************************************************
"" Commands
"*****************************************************************************
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

" ale
let g:ale_linters = {}

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

" go
" vim-go
" run :GoBuild or :GoTestCompile based on the go file
function! s:build_go_files()
  let l:file = expand('%')
  if l:file =~# '^\f\+_test\.go$'
    call go#test#Test(0, 1)
  elseif l:file =~# '^\f\+\.go$'
    call go#cmd#Build(0)
  endif
endfunction

let g:go_list_type = "quickfix"
let g:go_fmt_command = "goimports"
let g:go_fmt_fail_silently = 1

let g:go_highlight_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_operators = 1
let g:go_highlight_build_constraints = 1
let g:go_highlight_structs = 1
let g:go_highlight_generate_tags = 1
let g:go_highlight_space_tab_error = 0
let g:go_highlight_array_whitespace_error = 0
let g:go_highlight_trailing_whitespace_error = 0
let g:go_highlight_extra_types = 1

autocmd BufNewFile,BufRead *.go setlocal noexpandtab tabstop=4 shiftwidth=4 softtabstop=4
autocmd BufNewFile,BufRead *.js,*.jsx,*.vue setlocal expandtab tabstop=2 shiftwidth=2 softtabstop=2

augroup completion_preview_close
  autocmd!
  if v:version > 703 || v:version == 703 && has('patch598')
    autocmd CompleteDone * if !&previewwindow && &completeopt =~ 'preview' | silent! pclose | endif
  endif
augroup END

augroup go
  au!
  au Filetype go command! -bang A call go#alternate#Switch(<bang>0, 'edit')
  au Filetype go command! -bang AV call go#alternate#Switch(<bang>0, 'vsplit')
  au Filetype go command! -bang AS call go#alternate#Switch(<bang>0, 'split')
  au Filetype go command! -bang AT call go#alternate#Switch(<bang>0, 'tabe')

  au FileType go nmap <Leader>dd <Plug>(go-def-vertical)
  au FileType go nmap <Leader>dv <Plug>(go-doc-vertical)
  au FileType go nmap <Leader>db <Plug>(go-doc-browser)

  au FileType go nmap <leader>r  <Plug>(go-run)
  au FileType go nmap <leader>t  <Plug>(go-test)
  au FileType go nmap <Leader>gt <Plug>(go-coverage-toggle)
  au FileType go nmap <Leader>i <Plug>(go-info)
  au FileType go nmap <silent> <Leader>l <Plug>(go-metalinter)
  au FileType go nmap <C-g> :GoDecls<cr>
  au FileType go nmap <leader>dr :GoDeclsDir<cr>
  au FileType go imap <C-g> <esc>:<C-u>GoDecls<cr>
  au FileType go imap <leader>dr <esc>:<C-u>GoDeclsDir<cr>
  au FileType go nmap <leader>rb :<C-u>call <SID>build_go_files()<CR>
augroup END

" ale
:call extend(g:ale_linters, {
      \"go": ['golint', 'go vet'], })

" javascript
let g:javascript_enable_domhtmlcss = 1

" typescript
let g:yats_host_keyword = 1

" vuejs
" vim vue
let g:vue_disable_pre_processors=1
" vim vue plugin
let g:vim_vue_plugin_load_full_syntax = 1

"*****************************************************************************
"" Convenience variables
"*****************************************************************************

" vim-airline
if !exists('g:airline_symbols')
  let g:airline_symbols = {}
endif
let g:airline_powerline_fonts = 1

" powerline symbols
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

" vim-airline/vim-airline-themes
let g:airline_theme = 'nord'


" Creates a floating window with a most recent buffer to be used
function! CreateCenteredFloatingWindow()
  let width = float2nr(&columns * 0.6)
  let height = float2nr(&lines * 0.6)
  let top = ((&lines - height) / 2) - 1
  let left = (&columns - width) / 2
  let opts = {'relative': 'editor', 'row': top, 'col': left, 'width': width, 'height': height, 'style': 'minimal'}

  let top = "╭" . repeat("─", width - 2) . "╮"
  let mid = "│" . repeat(" ", width - 2) . "│"
  let bot = "╰" . repeat("─", width - 2) . "╯"
  let lines = [top] + repeat([mid], height - 2) + [bot]
  let s:buf = nvim_create_buf(v:false, v:true)
  call nvim_buf_set_lines(s:buf, 0, -1, v:true, lines)
  call nvim_open_win(s:buf, v:true, opts)
  set winhl=Normal:Floating
  let opts.row += 1
  let opts.height -= 2
  let opts.col += 2
  let opts.width -= 4
  call nvim_open_win(nvim_create_buf(v:false, v:true), v:true, opts)
  au BufWipeout <buffer> exe 'bw '.s:buf
endfunction

" Term handling

" When term starts, auto go into insert mode
autocmd TermOpen * startinsert

" Turn off line numbers etc
autocmd TermOpen * setlocal listchars= nonumber norelativenumber

function! OpenTerm(cmd)
  call CreateCenteredFloatingWindow()
  call termopen(a:cmd, { 'on_exit': function('OnTermExit') })
endfunction

let s:scratch_open = 0
function! ToggleScratchTerm()
  call OpenTerm('zsh')
  " if s:scratch_open
  "   bd!
  "   let s:scratch_open = 0
  " else
  "   call OpenTerm('zsh')
  "   let s:scratch_open = 1
  " endif
endfunction

let s:lazygit_open = 0
function! ToggleLazyGit()
  call OpenTerm('lazygit')
  " if s:lazygit_open
  "   " bd!
  "   let s:lazygit_open = 0
  " else
  "   call OpenTerm('lazygit')
  "   let s:lazygit_open = 1
  " endif
endfunction

function! OnTermExit(job_id, code, event) dict
  if a:code == 0
    bd!
  endif
endfunction

" Open scratch term
nnoremap <silent> <Leader>[ :call ToggleScratchTerm()<CR>

" Open lazygit
nnoremap <silent> <Leader>] :call ToggleLazyGit()<CR>

" highlight Normal ctermfg=lightgray ctermbg=black guifg=lightgray guibg=black
