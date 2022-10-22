" Plugins will be downloaded under the specified directory.
call plug#begin(has('nvim') ? stdpath('data') . '/plugged' : '~/.vim/plugged')

" Declare the list of plugins.
Plug 'tpope/vim-sensible'
Plug 'tpope/vim-commentary'
Plug 'tpope/vim-eunuch'
Plug 'tpope/vim-fugitive'
Plug 'tpope/vim-repeat'
Plug 'tpope/vim-surround'
Plug 'junegunn/fzf'
Plug 'junegunn/fzf.vim'
Plug 'ConradIrwin/vim-bracketed-paste'
Plug 'adelarsq/vim-matchit'
Plug 'ekalinin/Dockerfile.vim'
Plug 'mattn/gist-vim'
Plug 'mattn/webapi-vim'
Plug 'vim-scripts/grep.vim'
Plug 'jiangmiao/auto-pairs'
Plug 'mhinz/vim-startify'
Plug 'vifm/vifm.vim'

Plug 'neovim/nvim-lspconfig'
Plug 'hrsh7th/cmp-nvim-lsp'
Plug 'hrsh7th/cmp-buffer'
Plug 'hrsh7th/cmp-path'
Plug 'hrsh7th/cmp-cmdline'
Plug 'hrsh7th/nvim-cmp'
Plug 'hrsh7th/cmp-vsnip'
Plug 'hrsh7th/vim-vsnip'

Plug '~/.config/nvim/dracula_pro'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'

" List ends here. Plugins become visible to Vim after this call.
call plug#end()

set nomodeline
set relativenumber
set cursorline
set hidden
set noshowmode
set scrolloff=3
set completeopt=menu,menuone,noselect

let g:dracula_colorterm = 0
colorscheme dracula_pro_van_helsing

" remove trailing whitespaces
command! FixWhitespace :%s/\s\+$//e

"" Copy/Paste/Cut
if has('unnamedplus')
  set clipboard=unnamed,unnamedplus
endif

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
let g:airline_theme='papercolor'

" Search mappings: These will make it so that going to the next one in a
" search will center on the line it's found in.
nnoremap n nzzzv
nnoremap N Nzzzv

noremap j gj
noremap k gk

" terminal
nnoremap <leader>t :split +terminal<CR>
augroup terminal
  autocmd!
  autocmd TermOpen * startinsert
  autocmd TermOpen * setlocal bufhidden=delete
augroup END
noremap <c-k> <c-\><c-n>
cnoremap <c-k> <c-\><c-n>
inoremap <c-k> <c-\><c-n>
tnoremap <c-k> <c-\><c-n>

" session management
let g:session_directory = "~/.config/nvim/session"
let g:session_autoload = "no"
let g:session_autosave = "no"
let g:session_command_aliases = 1

" Switching windows
noremap <C-j> <C-w>j
noremap <C-k> <C-w>k
noremap <C-l> <C-w>l
noremap <C-h> <C-w>h

" Vmap for maintain Visual Mode after shifting > and <
vmap < <gv
vmap > >gv

" Move visual block
vnoremap J :m '>+1<CR>gv=gv
vnoremap K :m '<-2<CR>gv=gv

" Split
noremap <Leader>h :split<CR>
noremap <Leader>v :vsplit<CR>

" fzf.vim
set wildmode=list:longest,list:full
set wildignore+=*.o,*.obj,.git,*.rbc,*.pyc,__pycache__
let $FZF_DEFAULT_COMMAND =  "find * -path '*/\.*' -prune -o -path 'node_modules/**' -prune -o -path 'target/**' -prune -o -path 'dist/**' -prune -o  -type f -print -o -type l -print 2> /dev/null"

" The Silver Searcher
if executable('ag')
  let $FZF_DEFAULT_COMMAND = 'ag --hidden --ignore .git -g ""'
  set grepprg=ag\ --nogroup\ --nocolor
endif

" yaml
augroup vimrc-yaml
  autocmd!
  autocmd FileType yaml setlocal tabstop=2 softtabstop=2 expandtab shiftwidth=2
augroup END

" The PC is fast enough, do syntax highlight syncing from start unless 200 lines
augroup vimrc-sync-fromstart
  autocmd!
  autocmd BufEnter * :syntax sync maxlines=200
augroup END

" Remember cursor position
augroup vimrc-remember-cursor-position
  autocmd!
  autocmd BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
augroup END

" javascript
augroup javascript-space
  autocmd!
  autocmd BufRead,BufNewFile *.js setlocal tabstop=2 shiftwidth=2 softtabstop=2 expandtab
augroup END

" startify list of files
let g:startify_lists = [{ 'type': 'dir', 'header': ['MRU'. getcwd()] }]
let g:startify_change_to_dir = 0
let g:startify_change_to_vcs_root = 1

" Vifm mapping
nnoremap <silent> - :Vifm<CR>
nnoremap <silent> <leader>b :Buffers<CR>
nnoremap <silent> <leader>e :GFiles<CR>

lua <<EOF
  -- Set up nvim-cmp.
  local cmp = require'cmp'

  cmp.setup({
    snippet = {
      -- REQUIRED - you must specify a snippet engine
      expand = function(args)
        vim.fn["vsnip#anonymous"](args.body) -- For `vsnip` users.
      end,
    },
    window = {
      -- completion = cmp.config.window.bordered(),
      -- documentation = cmp.config.window.bordered(),
    },
    mapping = cmp.mapping.preset.insert({
      ['<C-b>'] = cmp.mapping.scroll_docs(-4),
      ['<C-f>'] = cmp.mapping.scroll_docs(4),
      ['<C-Space>'] = cmp.mapping.complete(),
      ['<C-e>'] = cmp.mapping.abort(),
      ['<CR>'] = cmp.mapping.confirm({ select = true }), -- Accept currently selected item. Set `select` to `false` to only confirm explicitly selected items.
    }),
    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'vsnip' }, -- For vsnip users.
    }, {
      { name = 'buffer' },
    })
  })

  -- Set configuration for specific filetype.
  cmp.setup.filetype('gitcommit', {
    sources = cmp.config.sources({
      { name = 'cmp_git' }, -- You can specify the `cmp_git` source if you were installed it.
    }, {
      { name = 'buffer' },
    })
  })

  -- Use buffer source for `/` and `?` (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline({ '/', '?' }, {
    mapping = cmp.mapping.preset.cmdline(),
    sources = {
      { name = 'buffer' }
    }
  })

  -- Use cmdline & path source for ':' (if you enabled `native_menu`, this won't work anymore).
  cmp.setup.cmdline(':', {
    mapping = cmp.mapping.preset.cmdline(),
    sources = cmp.config.sources({
      { name = 'path' }
    }, {
      { name = 'cmdline' }
    })
  })

  -- Set up lspconfig.
  local capabilities = require('cmp_nvim_lsp').default_capabilities()
  require('lspconfig')['yamlls'].setup {
    capabilities = capabilities
  }
  require('lspconfig')['tsserver'].setup {
    capabilities = capabilities
  }
  require('lspconfig')['jsonls'].setup {
    capabilities = capabilities
  }
EOF
