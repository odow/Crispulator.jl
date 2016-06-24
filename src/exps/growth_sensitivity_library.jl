# Growth screens seem to be highly susceptible to the distribution of
# genes that promote growth versus that hurt it. This experiment tests
# the behavior of growth screens under several different library setups

function main(filepath; debug=false, quiet=false)

    if !debug

        inc_space = linspace(0.02, 0.1, 5)
        cent_space = linspace(0.1, 0.55, 5)

        libs = Library[]
        for (inc, cent, crisprtype) in Iterators.product(inc_space, cent_space, [CRISPRi(), CRISPRKO()])

            max_phenotype_dists = Dict{Symbol, Tuple{Float64, Sampleable}}(
                :inactive => (1-inc-0.1-0.05, Delta(0.0)),
                :negcontrol => (0.05, Delta(0.0)),
                :increasing => (inc, TruncatedNormal(cent, 0.1, 0.025, 1)),
                :decreasing => (0.1, TruncatedNormal(-0.55, 0.2, -1, -0.1))
            )
            push!(libs, Library(max_phenotype_dists, crisprtype))
        end
    else
        libs = Library[Library(CRISPRi()), Library(CRISPRKO())]
    end

    parameters = Dict{Symbol, Vector}(
            :representation => [100],
            :bottleneck_representation => [100],
            :seq_depth => [100],
            :num_bottlenecks => collect(7:20)
        )
    num_runs = 25

    runs = grouped_param_space(GrowthScreen(), parameters, libs, [:num_bottlenecks], num_runs);

    function compute_auprc(barcodes, genes)
        i = auprc(genes[:pvalmeanprod], genes[:class], Set([:increasing]))[1]
        d = auprc(genes[:pvalmeanprod], genes[:class], Set([:decreasing]), rev=false)[1]
        (i, d)
    end

    before = time()
    results = pmap(args -> run_exp(args[1], args[2], compute_auprc;
                   run_idx=args[3], flatten_func=flatten_both), runs)
    (!quiet) && println("$(time() - before) seconds")

    data = DataFrame(hcat(results...)')
    hierarchy = reshape([:inc; :dec], (2, 1))
    new_names = [[:measure, :score]...; fieldnames(GrowthScreen)...; array_names(Library)...; :run_idx]

    data = construct_hierarchical_label(hierarchy, data, new_names)

    writetable(filepath, data)
end