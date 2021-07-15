
paper.pdf: paper.tex ref.bib header.tex
	latexmk -bibtex -pdf paper.tex

header.tex: paper.yml
	ruby prep.rb

