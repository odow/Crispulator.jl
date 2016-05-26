print("Loading simulation framework...")

packages = [:DataFrames,
            :Distributions,
            :HypothesisTests,
            :StatsBase,
            :Iterators]
all_workers = packages[1:4]
for package in packages
    !(isdir(Pkg.dir(string(package)))) && Pkg.add(string(package))
    eval(:(using $package))
    if package in all_workers
        eval(:(@everywhere using $package))
    end
end

# Load all simulations files on all workers
@everywhere function include_all()
    filenames = ["common.jl", "utils.jl", "library.jl", "transfection.jl",
                 "selection.jl", "sequencing.jl", "processing.jl",
                 "designs.jl"]
    for filename in filenames
        include(filename)
    end
end
@everywhere include_all()

include("experiments.jl")

println("Done.")
