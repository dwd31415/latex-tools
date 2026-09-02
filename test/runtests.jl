using Test
using LaTeXTools

@testset "LaTeXTools" begin
    @test remove_comments("a % comment\nb \\% kept") == "a \nb \\% kept"

    mktempdir() do directory
        write(joinpath(directory, "part.tex"), "Part % removed\n\\cite{used}")
        main = joinpath(directory, "main.tex")
        output = joinpath(directory, "out.tex")
        write(main, "\\documentclass{article}\n\\input{part}\n")
        process_document(main; output)
        @test read(output, String) == "\\documentclass{article}\nPart \n\\cite{used}\n"

        bib = "@article{used,\n  title = {Used}\n}\n@article{unused,\n  title = {Unused}\n}\n"
        @test occursin("@article{used", clean_bibliography(bib, Set(["used"])))
        @test !occursin("@article{unused", clean_bibliography(bib, Set(["used"])))
    end
end
