" matlab.vim - A script to highlight MatLab code in Vim based on the output from
" Matlab's in built mlint function.
"
" Place in your after/ftplugin directory.
"
" Last Change: 2011 Oct 21
" Maintainer: Thomas Ibbotson <thomas.ibbotson@gmail.com>
" License: Copyright 2008-2009, 2011 Thomas Ibbotson
"    This program is free software: you can redistribute it and/or modify
"    it under the terms of the GNU General Public License as published by
"    the Free Software Foundation, either version 3 of the License, or
"    (at your option) any later version.
"
"    This program is distributed in the hope that it will be useful,
"    but WITHOUT ANY WARRANTY; without even the implied warranty of
"    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
"    GNU General Public License for more details.
"
"    You should have received a copy of the GNU General Public License
"    along with this program.  If not, see <http://www.gnu.org/licenses/>.
"
" Version: 0.6.1
"
" The following variables affect this plugin:
"
"   g:mlint_rmdir_cmd: set this variable to the command on your system that will
"                      delete a directory. Defaults to the same command used by
"                      netrw, if you have it. If not, defaults to "rmdir"
"
"   g:mlint_path_to_mlint: set this variable to the full path to the mlint
"                          executable, if it is not found in your system path.
"
"   g:mlint_hover: set this variable to prevent mlint from automatically
"                  updating on CursorHold events. This may be especially useful
"                  if you do not have Vim 7.2.25 or later, since a bug exists in
"                  earlier versions of Vim that causes CursorHold to continually
"                  fire for this plugin.
"

if exists("b:did_mlint_plugin")
    finish
endif
" This variable can be anything as long as it exists.
" We may as well set it to something useful (like the version number)
let b:did_mlint_plugin = 6

" This plugin uses line continuation...save cpo to restore it later
let s:cpo_sav = &cpo
set cpo-=C

if !hasmapto('<Plug>mlintRunLint')
    map <buffer> <unique> <LocalLeader>l <Plug>mlintRunLint
endif

if !hasmapto('<Plug>mlintGetLintMessage')
    map <buffer> <unique> <LocalLeader>m <Plug>mlintGetLintMessage
endif

if !hasmapto('<Plug>mlintOutline')
    map <buffer> <unique> <LocalLeader>o <Plug>mlintOutline
endif

if !hasmapto('<SID>RunLint')
    noremap <unique> <script> <Plug>mlintRunLint <SID>RunLint
    noremap <SID>RunLint :call <SID>RunLint()<CR>
endif

if !hasmapto('<SID>GetLintMessage')
    noremap <unique> <script> <Plug>mlintGetLintMessage <SID>GetLintMessage
    noremap <SID>GetLintMessage :call <SID>GetLintMessage()<CR>
end

if !hasmapto('<SID>Outline')
    noremap <unique> <script> <Plug>mlintOutline <SID>Outline
    noremap <SID>Outline :call <SID>Outline()<CR>
end

au BufWinLeave <buffer> call s:ClearLint()
au BufEnter <buffer> call s:RunLint()
au InsertLeave <buffer> call s:RunLint()
au BufUnload <buffer> call s:Cleanup(expand("<afile>:t"), getbufvar(expand("<afile>"), "mlintTempDir"))

if !exists("mlint_hover")
    au CursorHold <buffer> if s:BufChanged() | call s:RunLint() | endif
    au CursorHold <buffer> call s:GetLintMessage()
    au CursorHoldI <buffer> if s:BufChanged() | call s:RunLint() | endif
endif

if !exists('*s:SID')
    function s:SID()
        return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
    endfun
endif

if exists('b:undo_ftplugin')
    let b:undo_ftplugin = b:undo_ftplugin.' | '
else
    let b:undo_ftplugin = ""
endif
let b:undo_ftplugin = b:undo_ftplugin.'call <SNR>'.s:SID().'_Cleanup('.
            \ '"'.expand("<afile>:t").'", "'.
            \ getbufvar(expand("<afile>"), "mlintTempDir").'")'

" determine 'rmdir' command to use (use 'g:mlint_rmdir_cmd' if it exists or
" default to the one used by netrw if it exists, or just 'rmdir' if it doesn't)
if !exists('g:mlint_rmdir_cmd')
  if exists('g:netrw_local_rmdir')
      let g:mlint_rmdir_cmd=g:netrw_local_rmdir
  else
      let g:mlint_rmdir_cmd='rmdir'
  endif
endif

" default the mlint path to assume mlint is in the path or use supplied value
if !exists('g:mlint_path_to_mlint')
    let g:mlint_path_to_mlint="mlint"
endif

"Create a temporary directory
let b:mlintTempDir = tempname() . "/"

if !exists("*s:BufChanged")
    function s:BufChanged()
        if !exists("b:mlint_oldchangedtick")
            let b:mlint_oldchangedtick = b:changedtick
            return 1
        else
            let l:oct = b:mlint_oldchangedtick
            let b:mlint_oldchangedtick = b:changedtick
            return l:oct != b:changedtick
        endif
    endfunction
endif

if !exists("*s:RunLint")
    function s:RunLint()
        " update tracking of changedtick to not trigger an automatic re-run
        " until necessary
        let b:mlint_oldchangedtick = b:changedtick

        "Clear previous matches
        if exists("b:cleared")
            if b:cleared == 0
                silent call s:ClearLint()
                let b:cleared = 1
            endif
        else
            let b:cleared = 1
        endif
        "If the temporary directory doesn't exist then create it
        if !isdirectory(b:mlintTempDir)
            call mkdir(b:mlintTempDir)
        endif
        "Get the filename
        let s:filename = expand("%:t")
        exe "silent write! " . fnameescape(b:mlintTempDir . s:filename)

        " Windows defaults for shellxquote are bad curretly.
        " See http://groups.google.com/group/vim_dev/browse_thread/thread/3d1cc6cb0c0d27b3
        if has('win32') || has('win16') || has('win64')
            let shxq_sav=&shellxquote
            let shcf_sav=&shellcmdflag
            let shsl_sav=&shellslash
            if &shell =~ 'cmd.exe'
                set noshellslash
                set shellxquote=\"
                set shellcmdflag=/s\ /c
            endif
        endif

        let s:mlintCommand = shellescape(g:mlint_path_to_mlint). " " . shellescape(b:mlintTempDir . s:filename)
        let s:lint = system(s:mlintCommand)

        if has('win32') || has('win16') || has('win64')
            let &shellxquote=shxq_sav
            let &shellcmdflag=shcf_sav
            let &shellslash=shsl_sav
        endif

        "Split the output from mlint and loop over each message
        let s:lint_lines = split(s:lint, '\n')
        highlight MLint term=underline gui=undercurl guisp=Orange
        let b:matched = []
        for s:line in s:lint_lines
            let s:matchDict = {}
            let s:lineNum = matchstr(s:line, 'L \zs[0-9]\+')
            let s:colStart = matchstr(s:line, 'C \zs[0-9]\+')
            let s:colEnd = matchstr(s:line, 'C [0-9]\+-\zs[0-9]\+')
            let s:message = matchstr(s:line, ': \zs.*')
            if s:lineNum > line("$")
                let s:mID = matchadd('MLint', '\%'.line("$").'l', '\%>1c')
                let s:lineNum = s:lineNum - 1
            elseif s:lineNum == 0
            " If mlint gave a message about line 0 display it immediately.
                echohl WarningMsg
                echo s:message
                echohl None
                let s:mID = 0
            elseif s:colStart > 0
                if s:colEnd > 0
                    let s:colStart = s:colStart -1
                    let s:colEnd = s:colEnd + 1
                    let s:mID = matchadd('MLint', '\%'.s:lineNum.'l'.'\%>'.
                                \ s:colStart.'c'.'\%<'.s:colEnd.'c')
                else
                    let s:colEnd = s:colStart + 1
                    let s:colStart = s:colStart - 1
                    let s:mID = matchadd('MLint', '\%'.s:lineNum.'l'.'\%>'.
                                \ s:colStart.'c'.'\%<'.s:colEnd.'c')
                endif
            else
                let s:mID = matchadd('MLint', '\%'.s:lineNum.'l','\%>1c')
            endif
            " Define the current buffer number for the quickfix list
            let s:matchDict['bufnr'] = bufnr('')
            let s:matchDict['mID'] = s:mID
            let s:matchDict['lnum'] = s:lineNum
            " Column number for quickfix list
            let s:matchDict['col'] = s:colStart
            let s:matchDict['colStart'] = s:colStart
            let s:matchDict['colEnd'] = s:colEnd
            let s:matchDict['text'] = s:message
            call add(b:matched, s:matchDict)
        endfor
        let b:cleared = 0
    endfunction
endif

if !exists("*s:GetLintMessage")
    function s:GetLintMessage()
        let s:cursorPos = getpos(".")
        for s:lintMatch in b:matched
        " If we're on a line with a match then show the mlint message
            if s:lintMatch['lnum'] == s:cursorPos[1]
                " The two lines commented below cause a message to be shown
                " only when the cursor is actually over the offending item in
                " the line.
                "\ && s:cursorPos[2] > s:lintMatch['colStart']
                "\ && s:cursorPos[2] < s:lintMatch['colEnd']
                echo s:lintMatch['text']
            elseif s:lintMatch['lnum'] == 0
                echohl WarningMsg
                echo s:lintMatch['text']
                echohl None
            endif
        endfor
    endfunction
endif

if !exists("*s:Outline")
    function s:Outline()
        silent call s:RunLint()
        call setqflist(b:matched)
        cwindow
    endfunction
end

if !exists('*s:ClearLint')
    function s:ClearLint()
        let s:matches = getmatches()
        for s:matchId in s:matches
            if s:matchId['group'] == 'MLint'
                call matchdelete(s:matchId['id'])
            end
        endfor
        let b:matched = []
        let b:cleared = 1
    endfunction
endif

if !exists('*s:Cleanup')
    function s:Cleanup(filename, mlintTempDir)
        " NOTE: ClearLint should already have been called from BufWinLeave

        let l:mlintTempDir = a:mlintTempDir
            
        " for some reason, rmdir doesn't work with '/' characters on mswin,
        " so convert to '\' characters
        if has("win16") || has("win32") || has("win64")
            let l:mlintTempDir = substitute(l:mlintTempDir,'/','\','g')
        endif

        " For some reason, this function sometimes gets called multiple times
        " for one buffer. Check to prevent this.
        if !exists('s:lastMlintCleanup') || s:lastMlintCleanup != l:mlintTempDir.a:filename
            let s:lastMlintCleanup = l:mlintTempDir.a:filename

            "If the buffer is opened but RunLint() doesn't get called, the
            "temp dir is not created, so check for its existence first.
            if isdirectory(l:mlintTempDir)
                if filewritable(l:mlintTempDir.a:filename) == 1
                    if delete(l:mlintTempDir.a:filename) == 0
                        " Vim leaves a filename.m~ file in the temp directory,
                        " so remove it here.
                        " TODO: Rather than deleting it we probably want to
                        " prevent it being created in the first place.
                        call delete(l:mlintTempDir.a:filename.'~')
                        exe "silent! !".g:mlint_rmdir_cmd." ".fnameescape(l:mlintTempDir)
                        if isdirectory(l:mlintTempDir)
                            echohl WarningMsg
                            echomsg "mlint: could not delete temp directory ".
                                        \ fnameescape(l:mlintTempDir).
                                        \ "; directory still exists after deletion"
                            echohl None
                        endif
                    else
                        echohl WarningMsg
                        echomsg "mlint: could not delete temp file ".
                                    \ fnameescape(l:mlintTempDir.a:filename).
                                    \ "; error during file deletion"
                        echohl None
                    endif
                else
                    echohl WarningMsg
                    echomsg "mlint: could not delete temp file ".
                                \ fnameescape(l:mlintTempDir.a:filename).
                                \ "; no write privileges"
                    echohl None
                endif
            endif
        endif
    endfunction
endif

let &cpo = s:cpo_sav

" vim: sw=4 et
