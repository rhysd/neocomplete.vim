"=============================================================================
" FILE: buffer.vim
" AUTHOR:  Shougo Matsushita <Shougo.Matsu@gmail.com>
" Last Modified: 06 Aug 2013.
" License: MIT license  {{{
"     Permission is hereby granted, free of charge, to any person obtaining
"     a copy of this software and associated documentation files (the
"     "Software"), to deal in the Software without restriction, including
"     without limitation the rights to use, copy, modify, merge, publish,
"     distribute, sublicense, and/or sell copies of the Software, and to
"     permit persons to whom the Software is furnished to do so, subject to
"     the following conditions:
"
"     The above copyright notice and this permission notice shall be included
"     in all copies or substantial portions of the Software.
"
"     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
"     OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
"     MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
"     IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
"     CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
"     TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
"     SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
" }}}
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim

" Global options definition. "{{{
let g:neocomplete#sources#buffer#cache_limit_size =
      \ get(g:, 'neocomplete#sources#buffer#cache_limit_size', 500000)
let g:neocomplete#sources#buffer#disabled_pattern =
      \ get(g:, 'neocomplete#sources#buffer#disabled_pattern', '')
"}}}

" Important variables.
if !exists('s:buffer_sources')
  let s:buffer_sources = {}
  let s:async_dictionary_list = {}
endif

let s:source = {
      \ 'name' : 'buffer',
      \ 'kind' : 'manual',
      \ 'mark' : '[B]',
      \ 'rank' : 5,
      \ 'min_pattern_length' :
      \     g:neocomplete#auto_completion_start_length,
      \ 'hooks' : {},
      \}

function! s:source.hooks.on_init(context) "{{{
  let s:buffer_sources = {}

  augroup neocomplete "{{{
    " Make cache events
    autocmd BufEnter,BufRead,BufWinEnter *
          \ call s:check_source()
    autocmd CursorHold,CursorHoldI *
          \ call s:check_cache()
    autocmd BufWritePost *
          \ call s:check_recache()
    autocmd InsertEnter,InsertLeave *
          \ call neocomplete#sources#buffer#make_cache_current_line()
  augroup END"}}}

  " Create cache directory.
  call neocomplete#cache#make_directory('buffer_cache')

  " Initialize script variables. "{{{
  let s:buffer_sources = {}
  let s:cache_line_count = 70
  let s:rank_cache_count = 1
  let s:async_dictionary_list = {}
  "}}}

  call s:check_source()
endfunction
"}}}

function! s:source.hooks.on_final(context) "{{{
  silent! delcommand NeoCompleteBufferMakeCache

  let s:buffer_sources = {}
endfunction"}}}

function! s:source.gather_candidates(context) "{{{
  call s:check_source()

  let keyword_list = []
  for [key, source] in s:get_sources_list()
    call neocomplete#cache#check_cache_dictionary('buffer_cache',
          \ source.path, s:async_dictionary_list, source.keyword_cache, 1)

    let keyword_list += keys(source.keyword_cache)
    if key == bufnr('%')
      let source.accessed_time = localtime()
    endif
  endfor

  return keyword_list
endfunction"}}}

function! neocomplete#sources#buffer#define() "{{{
  return s:source
endfunction"}}}

function! neocomplete#sources#buffer#get_frequencies() "{{{
  return get(get(s:buffer_sources, bufnr('%'), {}), 'frequencies', {})
endfunction"}}}
function! neocomplete#sources#buffer#make_cache_current_line() "{{{
  " Make cache from current line.
  return s:make_cache_current_buffer(
        \ max([1, line('.') - 5]), min([line('.') + 5, line('$')]))
endfunction"}}}
function! s:make_cache_current_block() "{{{
  " Make cache from current block.
  return s:make_cache_current_buffer(
          \ max([1, line('.') - 500]), min([line('.') + 500, line('$')]))
endfunction"}}}
function! s:make_cache_current_buffer(start, end) "{{{
  " Make cache from current buffer.
  if !s:exists_current_source()
    call s:make_cache(bufnr('%'))
  endif

  let source = s:buffer_sources[bufnr('%')]
  let keyword_pattern = source.keyword_pattern

  lua << EOF
do
  local keywords = vim.eval('source.keyword_cache')
  local b = vim.buffer()
  local min_length = vim.eval('g:neocomplete#min_keyword_length')
  for linenr = vim.eval('a:start'), vim.eval('a:end') do
    local match = 0
    while match >= 0 do
      match = vim.eval('match(getline(' .. linenr ..
        '), keyword_pattern, ' .. match .. ')')
      if match >= 0 then
        match_end = vim.eval('matchend(getline('..linenr..
          '), keyword_pattern, '..match..')')
        match_str = string.sub(b[linenr], match+1, match_end)
        if string.len(match_str) >= min_length and
          keywords[match_str] == nil then
          keywords[match_str] = ''
        end

        -- Next match.
        match = match_end
      end
    end
  end
end
EOF
endfunction"}}}

function! s:get_sources_list() "{{{
  let sources_list = []

  let filetypes_dict = {}
  for filetype in neocomplete#get_source_filetypes(
        \ neocomplete#get_context_filetype())
    let filetypes_dict[filetype] = 1
  endfor

  for [key, source] in items(s:buffer_sources)
    if has_key(filetypes_dict, source.filetype)
          \ || has_key(filetypes_dict, '_')
          \ || bufnr('%') == key
          \ || (source.name ==# '[Command Line]' && bufnr('#') == key)
      call add(sources_list, [key, source])
    endif
  endfor

  return sources_list
endfunction"}}}

function! s:initialize_source(srcname) "{{{
  let path = fnamemodify(bufname(a:srcname), ':p')
  let filename = fnamemodify(path, ':t')
  if filename == ''
    let filename = '[No Name]'
    let path .= '/[No Name]'
  endif

  let ft = getbufvar(a:srcname, '&filetype')
  if ft == ''
    let ft = 'nothing'
  endif

  let buflines = getbufline(a:srcname, 1, '$')
  let keyword_pattern = neocomplete#get_keyword_pattern(ft)

  let s:buffer_sources[a:srcname] = {
        \ 'keyword_cache' : {},
        \ 'frequencies' : {},
        \ 'name' : filename, 'filetype' : ft,
        \ 'keyword_pattern' : keyword_pattern,
        \ 'end_line' : len(buflines),
        \ 'accessed_time' : 0,
        \ 'cached_time' : 0,
        \ 'path' : path, 'loaded_cache' : 0,
        \ 'cache_name' : neocomplete#cache#encode_name(
        \   'buffer_cache', path),
        \}
endfunction"}}}

function! s:make_cache(srcname) "{{{
  " Initialize source.
  call s:initialize_source(a:srcname)

  let source = s:buffer_sources[a:srcname]

  if !filereadable(source.path)
        \ || getbufvar(a:srcname, '&buftype') =~ 'nofile'
    return
  endif

  let source.cache_name =
        \ neocomplete#cache#async_load_from_file(
        \     'buffer_cache', source.path,
        \     source.keyword_pattern, 'B')
  let source.cached_time = localtime()
  let source.end_line = len(getbufline(a:srcname, 1, '$'))
  let s:async_dictionary_list[source.path] = [{
        \ 'filename' : source.path,
        \ 'cachename' : source.cache_name,
        \ }]
endfunction"}}}

function! s:check_changed_buffer(bufnumber) "{{{
  let source = s:buffer_sources[a:bufnumber]

  let ft = getbufvar(a:bufnumber, '&filetype')
  if ft == ''
    let ft = 'nothing'
  endif

  let filename = fnamemodify(bufname(a:bufnumber), ':t')
  if filename == ''
    let filename = '[No Name]'
  endif

  return s:buffer_sources[a:bufnumber].name != filename
        \ || s:buffer_sources[a:bufnumber].filetype != ft
endfunction"}}}

function! s:check_source() "{{{
  if !s:exists_current_source()
    call s:make_cache_current_block()
    return
  endif

  for bufnumber in filter(range(1, bufnr('$')), 'buflisted(v:val)')
    " Check new buffer.
    if (!has_key(s:buffer_sources, bufnumber)
          \ || (bufwinnr(bufnumber) > 0 && s:check_changed_buffer(bufnumber)))
          \ && (!neocomplete#is_locked(bufnumber) ||
          \    g:neocomplete#disable_auto_complete)
          \ && !getwinvar(bufwinnr(bufnumber), '&previewwindow')
          \ && getfsize(fnamemodify(bufname(bufnumber), ':p')) <
          \      g:neocomplete#sources#buffer#cache_limit_size
      call s:make_cache(bufnumber)
    endif
  endfor
endfunction"}}}
function! s:check_cache() "{{{
  let release_accessd_time =
        \ localtime() - g:neocomplete#release_cache_time

  for [key, source] in items(s:buffer_sources)
    " Check deleted buffer and access time.
    if !bufloaded(str2nr(key))
          \ || (source.accessed_time > 0 &&
          \ source.accessed_time < release_accessd_time)
      " Remove item.
      call remove(s:buffer_sources, key)
    endif
  endfor
endfunction"}}}
function! s:check_recache() "{{{
  if !s:exists_current_source()
    return
  endif

  let release_accessd_time =
        \ localtime() - g:neocomplete#release_cache_time

  let source = s:buffer_sources[bufnr('%')]

  " Check buffer access time.
  if (source.cached_time > 0 && source.cached_time < release_accessd_time)
        \  || (neocomplete#util#has_vimproc() && line('$') != source.end_line)
    " Buffer recache.
    if g:neocomplete#enable_debug
      echomsg 'Make cache from buffer: ' . bufname('%')
    endif

    call s:make_cache_current_block()
  endif
endfunction"}}}

function! s:exists_current_source() "{{{
  return has_key(s:buffer_sources, bufnr('%'))
endfunction"}}}

" Command functions. "{{{
function! neocomplete#sources#buffer#make_cache(name) "{{{
  if a:name == ''
    let number = bufnr('%')
  else
    let number = bufnr(a:name)

    if number < 0
      let bufnr = bufnr('%')

      " No swap warning.
      let save_shm = &shortmess
      set shortmess+=A

      " Open new buffer.
      execute 'silent! edit' fnameescape(a:name)

      let &shortmess = save_shm

      if bufnr('%') != bufnr
        setlocal nobuflisted
        execute 'buffer' bufnr
      endif
    endif

    let number = bufnr(a:name)
  endif

  call s:make_cache(number)
  call s:make_cache_current_buffer(1, line('$'))
endfunction"}}}
"}}}

let &cpo = s:save_cpo
unlet s:save_cpo

" vim: foldmethod=marker
