set nu rnu hls tabstop=2 shiftwidth=2 expandtab autoindent smartindent cindent
let mapleader = ","
set mouse=
set clipboard=unnamedplus
syntax on
"call plug#begin('~/.vim/plugged')
"Plug 'junegunn/fzf', { 'do': './install --all' } | Plug 'junegunn/fzf.vim'
"Plug 'preservim/nerdtree'
"Plug 'morhetz/gruvbox'
"Plug 'tpope/vim-commentary'
"call plug#end()
"let NERDTreeShowHidden=1
nnoremap <leader>h :noh<CR>
"nnoremap <C-t> :NERDTreeToggle<CR>
"nnoremap <C-p> :Files<CR>
"nnoremap <leader>y :%yank | call system('echo "'.@*.'" | xclip -selection clipboard')
"nnoremap <leader>p :r !xclip -o -selection clipboard<CR>
"set clipboard=unnamedplus
"vnoremap <leader>c :<C-u>call system("xclip -selection clipboard", @")<CR>
"vnoremap <leader>x :<C-u>call system("xclip -selection clipboard", @") \| normal! gv d<CR>
"nnoremap <leader>v :r!xclip -selection clipboard -o<CR>
map <F3> <ESC>:exec &mouse!=""? "set mouse=" : "set mouse=a"<CR>
cmap w!! %!sudo tee > /dev/null %
inoremap <C-[> <Esc>
"set background=dark
"colorscheme gruvbox
