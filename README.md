# LaTeX Tools

`latex-tools` prepares a self-contained LaTeX source by removing comments and
recursively inlining `\input{...}` and `\include{...}` files. It can also remove
uncited entries from a BibTeX file.

## Usage

```sh
julia --project=. bin/latex-tools thesis.tex -o thesis-single.tex \
  --bib references.bib --bib-output references-used.bib
```

Use `--output-folder` to write the generated TeX and bibliography files there;
all figures referenced with `\includegraphics` are copied into the same folder
and their paths are updated in the generated TeX.

Use `--autobuild BUILD_DIR` to compile the supplied document with `pdflatex`
and watch the document and all recursively included TeX/BibTeX files. Changes
trigger a rebuild; documents with bibliography files also run `bibtex`.
Build output and errors are printed with color-coded diagnostics. Stop
watching with Ctrl-C.

The input file is never modified. Included files are resolved relative to the
file that references them, and missing or cyclic includes are reported as
errors. Citation keys from common `\cite`-style commands are used when
cleaning the bibliography.

Run tests with:

```sh
julia --project=. test/runtests.jl
```
