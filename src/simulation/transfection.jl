function build_cells(::CRISPRi,
                     guides::Vector{Barcode},
                     guide_freq_dist::Categorical,
                     n::Int64,
                     setup::GrowthScreen
                    )
    cells = rand(guide_freq_dist, n)
    phenotypes = Array(Float64, n)
    noise_dist = Normal(0, setup.noise)
    @inbounds @fastmath for i in 1:n
        phenotypes[i] = guides[cells[i]].theo_phenotype + rand(noise_dist)
    end
    cells, phenotypes
end

function build_cells(::CRISPRi,
                     guides::Vector{Barcode},
                     guide_freq_dist::Categorical,
                     n::Int64,
                     ::FacsScreen
                    )
    cells = rand(guide_freq_dist, n)
    phenotypes = Array(Float64, n)
    @inbounds @fastmath for i in 1:n
        phenotypes[i] = guides[cells[i]].theo_phenotype
    end
    cells, phenotypes
end

function build_cells(behav::CRISPRKO,
                     guides::Vector{Barcode},
                     guide_freq_dist::Categorical,
                     n::Int64,
                     setup::GrowthScreen
                    )

    phenotypes = Array(Float64, n);
    cells = rand(guide_freq_dist, n)
    ko_dist = behav.knockout_dist
    dist = rand(ko_dist, n)
    noise_dist = Normal(0, setup.noise)
    @inbounds @fastmath for i in 1:n
        phenotypes[i] = guides[cells[i]].theo_phenotype*(dist[i] - 1)/2 + rand(noise_dist)
    end
    cells, phenotypes
end

function build_cells(behav::CRISPRKO,
                     guides::Vector{Barcode},
                     guide_freq_dist::Categorical,
                     n::Int64,
                     ::FacsScreen
                    )

    phenotypes = Array(Float64, n);
    cells = rand(guide_freq_dist, n)
    ko_dist = behav.knockout_dist
    dist = rand(ko_dist, n)
    @inbounds @fastmath for i in 1:n
        phenotypes[i] = guides[cells[i]].theo_phenotype*(dist[i] - 1)/2
    end
    cells, phenotypes
end

function transfect(setup::FacsScreen,
                   lib::Library,
                   guides::Vector{Barcode},
                   guide_freqs_dist::Categorical)

    moi = setup.moi
    num_guides = length(guides)
    cell_count = num_guides * setup.representation
    expand_to = setup.bottleneck_representation * length(guides)

    cells, cell_phenotypes = build_cells(lib.cas9_behavior, guides, guide_freqs_dist,
                                         round(Int64, pdf(Poisson(moi), 1)*cell_count), setup)
    num_cells = length(cells)

    multiples = 1
    if expand_to > num_cells
        multiples = ceil(Int64, expand_to/num_cells)
        expansion_c = Array(Int64, num_cells*multiples)
        expansion_p = Array(Float64, num_cells*multiples)
        for rep in 1:multiples
            rng = (rep-1)*num_cells+1:rep*num_cells
            expansion_c[rng] = cells
            expansion_p[rng] = cell_phenotypes
        end
        cells, cell_phenotypes = expansion_c, expansion_p
    else
        picked = sample(collect(1:num_cells), expand_to, replace=false)
        cells, cell_phenotypes = cells[picked], cell_phenotypes[picked]
    end

    initial_freqs = StatsBase.counts(cells, 1:num_guides) ./ length(cells)

    for i in 1:num_guides
        @inbounds guides[i].initial_freq = initial_freqs[i]
    end
    cells, cell_phenotypes
end

function transfect(setup::GrowthScreen,
                   lib::Library,
                   guides::Vector{Barcode},
                   guide_freqs_dist::Categorical)

    num_guides = length(guides)
    cell_count = num_guides * setup.representation
    initial_cells, cell_phenotypes = build_cells(lib.cas9_behavior, guides, guide_freqs_dist,
                                         round(Int64, pdf(Poisson(setup.moi), 1)*cell_count), setup )
    target = num_guides * setup.bottleneck_representation

    if target < length(initial_cells)
        picked = sample(collect(1:length(initial_cells)), target, replace=false)
        cells, cell_phenotypes = initial_cells[picked], cell_phenotypes[picked]
        num_doublings = -1
    else
        cells, cell_phenotypes = copy(initial_cells), copy(cell_phenotypes)
        num_inserted = length(cells)
        num_doublings = 0
        output_c = Array(Int64, target*4)
        output_p = Array(Float64, target*4)

        while num_inserted < target
            num_inserted = grow!(cells, cell_phenotypes, output_c, output_p)
            cells = copy(sub(output_c, 1:num_inserted))
            cell_phenotypes = copy(sub(output_p, 1:num_inserted))
            num_doublings += 1
        end
    end

    initial_freqs = counts(cells, 1:length(guides)) ./ length(cells)

    for i in 1:length(guides)
        @inbounds guides[i].initial_freq = initial_freqs[i]
    end
    cells, cell_phenotypes
end