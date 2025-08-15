import Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
import Downloads
import Inflate
import Tar
import SHA

url_julia_repo = "https://github.com/fatteneder/julia/tarball/43e596c119f7e32ee22b5531b793af6a1a7f03b4"

mktempdir() do dir
    filename = joinpath(dir, "julia.tgz")
    Downloads.download(url_julia_repo, filename)
    sha256 = bytes2hex(open(SHA.sha256, filename))
    gittreesha1 = Tar.tree_hash(IOBuffer(Inflate.inflate_gzip(filename)))
    open(joinpath(@__DIR__, "..", "Artifacts.toml"), write=true) do f
        println(f, """
[julia_repo]
git-tree-sha1 = "$gittreesha1"

    [[julia_repo.download]]
    url = "$url_julia_repo"
    sha256 = "$sha256"
""")
    end
end
