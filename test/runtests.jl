using Test
using LaTeXTools

@testset "LaTeXTools" begin
    @test remove_comments("a % comment\n% full-line comment\nb \\% kept") ==
          "a % \n% \nb \\% kept"

    mktempdir() do directory
        write(joinpath(directory, "part.tex"), "Part % removed\n\\cite{used}")
        main = joinpath(directory, "main.tex")
        output = joinpath(directory, "out.tex")
        write(main, "\\documentclass{article}\n\\input{part}\n")
        process_document(main; output)
        @test read(output, String) == "\\documentclass{article}\nPart % \n\\cite{used}\n"

        figure = joinpath(directory, "figure.png")
        write(figure, "figure data")
        write(main, "\\includegraphics[width=\\textwidth]{figure}\n")
        output_folder = joinpath(directory, "output")
        result = process_document(main; output=joinpath(directory, "named.tex"),
                                  output_folder)
        @test result.tex == joinpath(output_folder, "named.tex")
        @test read(result.tex, String) == "\\includegraphics[width=\\textwidth]{figure.png}\n"
        @test read(joinpath(output_folder, "figure.png"), String) == "figure data"

        bib = "@article{used,\n  title = {Used}\n}\n@article{unused,\n  title = {Unused}\n}\n"
        @test occursin("@article{used", clean_bibliography(bib, Set(["used"])))
        @test !occursin("@article{unused", clean_bibliography(bib, Set(["used"])))
    end
end
