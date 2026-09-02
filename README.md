# LaTeX Tools

`latex-tools` prepares a self-contained LaTeX source by removing comments and
recursively inlining `\input{...}` and `\include{...}` files. It can also remove
uncited entries from a BibTeX file.

## Usage

```sh
julia --project=. bin/latex-tools thesis.tex -o thesis-single.tex \
  --bib references.bib --bib-output references-used.bib
```

The input file is never modified. Included files are resolved relative to the
file that references them, and missing or cyclic includes are reported as
errors. Citation keys from common `\cite`-style commands are used when
cleaning the bibliography.

Run tests with:

```sh
julia --project=. test/runtests.jl
```
