set nu rnu hls tabstop=2 shiftwidth=2 expandtab autoindent smartindent cindent
let mapleader = ","
set mouse=
set clipboard=unnamedplus
syntax on
#call plug#begin('~/.vim/plugged')
#Plug 'junegunn/fzf', { 'do': './install --all' } | Plug 'junegunn/fzf.vim'
#Plug 'preservim/nerdtree'
#Plug 'morhetz/gruvbox'
#Plug 'tpope/vim-commentary'
#call plug#end()
#let NERDTreeShowHidden=1
nnoremap <leader>h :noh<CR>
#nnoremap <C-t> :NERDTreeToggle<CR>
#nnoremap <C-p> :Files<CR>
nnoremap <leader>y :%yank | call system('echo "'.@*.'" | xclip -selection clipboard')
map <F3> <ESC>:exec &mouse!=""? "set mouse=" : "set mouse=a"<CR>
cmap w!! %!sudo tee > /dev/null %
inoremap <C-[> <Esc>
#set background=dark
#colorscheme gruvbox
