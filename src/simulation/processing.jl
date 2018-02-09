"""
$(SIGNATURES)

Given the raw data from [`Simulation.sequencing`](@ref) returns two DataFrames

1. `guide_data`: This DataFrame contains the per-guide level data including the
    log2 fold change in the normalized frequencies of each guide between the two
    bins.

2. `gene_data`: This DataFrame contains the same information but grouped by
    gene. The log2 fold change data from the first DataFrame is used to calculate
    the average log2 fold change per gene and a pvalue computed using a
    [Mann-Whitney U-test](https://en.wikipedia.org/wiki/Mann-Whitney_U_test) as
    measure of how consistently shifted the guides are of this gene versus the
    population of negative control guides. (see below for more info)

A typical `guide_data` DataFrame contains the following columns:

- `gene`: the gene ID of that this guide targets

- `knockdown`: activity of the guide on 0 to 1 scale, where 1 is complete knockout

- `barcodeid`: the ID of this specific guide

- `theo_phenotype`: expected phenotype of this guide, generally a -1 to 1 scale

- `behavior`: whether the target gene displays a linear or sigmoidal response to knockdown

- `class`: whether the target gene has a positive, negative, or no phenotype during screening

- `initial_freq`: frequency of guide post-transfection (see [`Simulation.transfect`](@ref))

- `counts_bin1`: the raw number of reads for each guide in the first bin

- `freqs_bin1`: the number of reads for each guide divided by the total number of reads in this bin

- `rel_freqs_bin1`: the frequency of each guide divided by the median frequency of negative control guides

- `counts_bin2`: the raw number of reads for each guide in the second bin

- `freqs_bin2`: the number of reads for each guide divided by the total number of reads in this bin

- `rel_freqs_bin2`: the frequency of each guide divided by the median frequency of negative control guides for this bin

- `log2fc_bin2`: the log2 fold change in relative guide frequencies between the two bins

A typical `gene_data` DataFrame contains the following data:

- `gene`: this gene's ID

- `behavior`: whether this gene displays a linear or sigmoidal response to knockdown

- `class`: whether this gene has a positive, negative, or no phenotype during screening

- `mean`: the mean log 2 fold change in relative frequencies between the two bins
    for all the guides targeting this gene.

- `pvalue`: the -log10 pvalue of the log2 fold changes of all guides targeting
    this gene as computed by the non-parametric Mann-Whitney U-test. A measure
    of the consistency of the log 2 fold changes[^1]

- `absmean`: absolute value of `mean` per-gene

- `pvalmeanprod`: `mean` multiplied with the `pvalue` per-gene

# Further reading

[^1]: Kampmann M, Bassik MC, Weissman JS. Integrated platform for genome-wide screening
    and construction of high-density genetic interaction maps in mammalian cells.
    *Proc Natl Acad Sci U S A*. 2013;110:E2317–26.

"""
function differences_between_bins(raw_data::Associative{Symbol, DataFrame};
                                  first_bin=:bin1,
                                  last_bin=maximum(keys(raw_data)))

    for (bin, seq_data) in raw_data
        sort!(seq_data, cols=[:barcodeid])
        # add a pseudocount of 0.5 to every value to prevent -Inf's when
        # taking the log
        seq_data[:counts] += 0.5
        seq_data[:freqs] = seq_data[:counts]./sum(seq_data[:counts])
        # normalize to median of negative controls, fixes #19
        # TODO: consider normalizing the std dev
        negcontrol_freqs = seq_data[seq_data[:class] .== :negcontrol, :freqs]
        (length(negcontrol_freqs) == 0) && error("No negative control guides found. Try increasing "*
            "the frequency of negative controls or increase the number of genes.")
        med = median(negcontrol_freqs)
        seq_data[:rel_freqs] = seq_data[:freqs] ./ med
    end

    combined = copy(raw_data[first_bin])
    rename!(combined, Dict(:freqs => Symbol("freqs_", first_bin),
                           :counts => Symbol("counts_", first_bin),
                           :rel_freqs => Symbol("rel_freqs_", first_bin)))

    for (bin, seq_data) in raw_data
        (bin == first_bin) && continue

        combined[Symbol("freqs_", bin)] = seq_data[:freqs]
        combined[Symbol("counts_", bin)] = seq_data[:counts]
        combined[Symbol("rel_freqs_", bin)] = seq_data[:rel_freqs]
        combined[Symbol("log2fc_", bin)] =
        log2(combined[Symbol("rel_freqs_", bin)]./combined[Symbol("rel_freqs_", first_bin)])
    end

    nonnegs = combined[combined[:class] .!= :negcontrol, :]
    negcontrols = combined[combined[:class] .== :negcontrol, Symbol("log2fc_", last_bin)]

    genes = by(nonnegs, [:gene, :behavior, :class]) do barcodes
        log2fcs = barcodes[Symbol("log2fc_", last_bin)]
        result = MannWhitneyUTest(log2fcs, negcontrols)
        DataFrame(pvalue = -log10(pvalue(result)), mean= mean(log2fcs))
    end
    genes[:absmean] = abs(genes[:mean])
    genes[:pvalmeanprod] = genes[:mean] .* genes[:pvalue]

    combined, genes
end