" Clear and redefine jjComment to disable spell checking
syntax clear jjComment
syntax region jjComment start="^JJ:" end="$" contains=jjAdded,jjRemoved,jjChanged,@NoSpell

" Clear and redefine the contained groups as well
syntax clear jjAdded
syntax match jjAdded "A .*" contained contains=@NoSpell

syntax clear jjRemoved
syntax match jjRemoved "D .*" contained contains=@NoSpell

syntax clear jjChanged
syntax match jjChanged "M .*" contained contains=@NoSpell

" Define a region for the header (before the first JJ: line)
syntax region jjHeader start=/\%^\_.\{-}\ze^JJ:/ end=/^JJ:/me=e-1 contains=NONE keepend

" Enable spell checking for the header
highlight def link jjHeader Spell

" diff
syntax region jjDiffAdd     start="^JJ:      +" end="$" contains=@NoSpell
syntax region jjDiffRemoved start="^JJ:      -" end="$" contains=@NoSpell
hi def link jjDiffAdd DiffAdd
hi def link jjDiffRemoved DiffRemoved

" Ensure spell checking is enabled for jjHeader only
syntax spell toplevel
