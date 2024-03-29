### Time Course Heatmap ###


library(stringr)
library(edgeR)
library(ConsensusClusterPlus)
library(ComplexHeatmap)
library(circlize)
library(RColorBrewer)


## Setup ##

# "time_course_heatmap" folder contains 4 subfolders, "cluster", "cluster_profile", "heatmap", and "sig_zscore".
# "counts" folder contains count files of all replicates across the time course.
# Count files were generated from featureCounts and selecting 1st and 7th column of the output (Gene id and counts).
# Each count file should be named as such: "experiment_condition_timepoint". For example, "exp176_infected_24hpi".
# "diffex" folder contains diffexgenes_full files generated by edgeR analysis, for each timepoint.

path <- "/path/to/time_course_heatmap/"
counts_path <- "/path/to/counts/"
diffex_path <- "/path/to/diffex/"


# gtf file for gene name conversion from ensembl id to gene symbols (HBEC only) #
# This gtf file needs to be gene-only and have the same number of genes as the count files;
# this can be achieved by only selecting rows which have "gene" as the third field (instead of "exon" or anything else);
# the genes in this gtf also need to be in the same order as the genes in count files.
gtf_path <- "/path/to/gene_only_gtf_file"


outputname <- "outputname_of_choice" # ex. HBEC_rseq_TCHeatmap

# number of replicates #
numrep <- 4 # 4 for HBEC, 3 for Vero



## Reading Counts Data ##
filelist <- dir(path = counts_path, pattern = "16.+") # <<< change accordingly
filelist <- str_sort(filelist, numeric = T)

data <- read.delim(file.path(counts_path, filelist[1]), header = F)
rownames(data) <- data[, 1]
data <- data[, -c(1, 2)]

for (file in filelist) {
  counts <- read.delim(file.path(counts_path, file), header = F)
  data <- cbind(data, counts[, 2])
}

colnames(data) <- filelist


# function that saves the time points of the mock samples #
saveMock <- function(cond, time) {
  if (cond == 'mock') return(cond) # saves as "mock"
  else return(time)
}

experiment <- sapply(strsplit(filelist, '_'), function(x) x[1])
condition <- sapply(strsplit(filelist,'_'), function(x) x[2])
timepoints <- sapply(strsplit(filelist,'_'), function(x) x[3])
timepoints <- unname(mapply(saveMock, condition, timepoints))

design <- data.frame(experiment, condition, timepoints) # design matrix
row.names(design) <- filelist



## DGE object, Filtering, CPM of a combined count table ##
dge <- DGEList(counts = data, samples = design, group = timepoints)
colnames(dge) <- paste0(experiment, "_", timepoints)
print(paste0("combined table before filtering: ", nrow(dge$counts)), quote = F)


# Converting human ensembl gene IDs to gene names using gene-only gtf file (HBEC only)
if (grepl(pattern = "ENSG", rownames(dge$counts)[1])) {
  gtf <- read.table(gtf_path, sep = " ")
  gene_names <- as.character(gtf[, 6])
  gene_names <- substr(gene_names, start = 1, stop = nchar(gene_names) - 1) # getting rid of the ";" at the end
  rownames(dge) <- gene_names
}


# Filtering
keep <- rowSums(cpm(dge) > 1) >= numrep
dge <- dge[keep, ,keep.lib.sizes = F]
print(paste0("combined table after filtering: ", nrow(dge$counts)), quote = F)

# Deduplicating
duplicate_genes <- row.names(dge)[duplicated(row.names(dge))]
dge <- dge[!(row.names(dge) %in% duplicate_genes), ,keep.lib.sizes = F]
print(paste0(length(duplicate_genes) + length(unique(duplicate_genes)),
             " duplicated genes removed."), quote = F)

dge <- calcNormFactors(dge)

# Combined CPM table
cpm <- cpm(dge, log = T, prior.count = 1)

write.table(cpm, file = file.path(path, "sig_zscore", paste0(outputname, "_cpm")), quote = F, sep = "\t")



## Selecting Significant DE Genes from edgeR Results and Taking Union ##
# Please note that only significant DE genes are shown in the time course heatmap.
union_genes <- NULL

for (file in dir(path = diffex_path, pattern = "*full")) { # <<< change pattern accordingly
  diffex <- read.delim(file.path(diffex_path, file))
  sig <- rownames(diffex[abs(diffex[, "logFC"]) > 1 & diffex[, "FDR"] < 0.05, ]) # significant DE gene selection
  union_genes <- union(union_genes, sig)
}

print(paste0("union genes count: ", length(union_genes)), quote = F)



## Significant CPM Table, Z-score ##
sig_cpm <- cpm[intersect(union_genes, row.names(cpm)), ] # selecting significant DE genes from CPM table
print(paste0("union DE genes present in the filtered combined CPM table: ", nrow(sig_cpm)), quote = F)


# Reordering Columns #

# Please only uncomment and run one of the following two column orders according to the experiment.
# The order of columns needs to be as such:
# rep1_mock, rep2_mock, ..., repn_mock, rep1_24hpi, rep2_24hpi, ..., repn_24hpi, rep1_48hpi, ......, repn_96hpi
# Here, HBEC's 4 replicates are 162-1, 162-2, 163-1, 163-2, and Vero's 3 replicates are 176, rp3, and rp9.

# HBEC only
col_order <- c("162-1_mock", "162-2_mock", "163-1_mock",
               "162-1_24hpi", "162-2_24hpi", "163-1_24hpi", "163-2_24hpi",
               "162-1_48hpi", "162-2_48hpi", "163-1_48hpi", "163-2_48hpi",
               "162-1_72hpi", "162-2_72hpi", "163-1_72hpi", "163-2_72hpi",
               "162-1_96hpi", "162-2_96hpi", "163-1_96hpi", "163-2_96hpi")

# Vero only
# col_order <- c("176_mock", "rp3_mock", "rp9_mock",
#                "176_2hpi", "rp3_2hpi", "rp9_2hpi",
#                "176_6hpi", "rp3_6hpi", "rp9_6hpi",
#                "176_12hpi", "rp3_12hpi", "rp9_12hpi",
#                "176_24hpi", "rp3_24hpi", "rp9_24hpi")

sig_cpm <- sig_cpm[, col_order]
write.table(sig_cpm,
            file = file.path(path, "sig_zscore", paste0(outputname, "_sig_cpm")),
            quote = F,
            sep = "\t")


# for each gene as a unit, calculating the z-score of each sample
sig_zscore <- t(scale(t(as.matrix(sig_cpm)))) # z-score calculation
write.table(sig_zscore,
            file = file.path(path, "sig_zscore", paste0(outputname, "_sig_zscore")),
            quote = F,
            sep = "\t")




## Clustering ##

# The below command was used for consensus clustering.
# IMPORTANT: Please note that each time consensus clustering is run, it generates different clustering results.
# Therefore, if the purpose is to use the original clustering results, please only run the load RData line.
# The original cluster RData files are provided in the Github repository.

cluster <- ConsensusClusterPlus(t(sig_zscore),
                                maxK = 13,
                                reps = 100,
                                pItem = 0.8,
                                pFeature = 1,
                                clusterAlg = "hc",
                                innerLinkage = "complete",
                                finalLinkage = "ward.D2",
                                distance = "pearson",
                                plot = "pdf",
                                title = file.path(path, "cluster", paste0(outputname, "_cluster"))
                                )

save(cluster, file = file.path(path, "cluster", paste0(outputname, "_cluster.RData")))

# Load the original cluster RData files if the purpose is to recreate the published heatmaps #
load(file = file.path(path, "cluster", paste0(outputname, "_cluster.RData")))



# Please note that the following cluster merging and reordering arrangements only apply to the original clustering results.

## Merging and Reordering Clusters ##
# Visually similar clusters are merged, and clusters are reordered according to the time course trend.
# A cluster is removed if no clear time course trend is observed.

sig_zscore_pruned <- sig_zscore

num.clusters <- 12
row.clusters.orig <- cluster[[num.clusters]][["consensusClass"]]
row.clusters <- row.clusters.orig
pos.1 <- which(row.clusters == 1)
pos.2 <- which(row.clusters == 2)
pos.3 <- which(row.clusters == 3)
pos.4 <- which(row.clusters == 4)
pos.5 <- which(row.clusters == 5)
pos.6 <- which(row.clusters == 6)
pos.7 <- which(row.clusters == 7)
pos.8 <- which(row.clusters == 8)
pos.9 <- which(row.clusters == 9)
pos.10 <- which(row.clusters == 10)
pos.11 <- which(row.clusters == 11)
pos.12 <- which(row.clusters == 12)


### The four following sections: only use one section at a time and comment out the other three ###

### START ###

#HBEC rnaseq
row.clusters[pos.1] <- 2
row.clusters[pos.2] <- 2
row.clusters[pos.3] <- 5
row.clusters[pos.4] <- 99
row.clusters[pos.5] <- 2
row.clusters[pos.6] <- 3
row.clusters[pos.7] <- 5
row.clusters[pos.8] <- 4
row.clusters[pos.9] <- 1
row.clusters[pos.10] <- 2
row.clusters[pos.11] <- 5
row.clusters[pos.12] <- 6

row.clusters <- row.clusters[-pos.4] # removing cluster 4
sig_zscore_pruned <- sig_zscore[!(row.names(sig_zscore) %in% names(pos.4)), ] # removing cluster 4 genes from sig_zscore
num.clusters <- 6 # number of clusters after merging and reordering


#HBEC riboseq
# row.clusters[pos.1] <- 3
# row.clusters[pos.2] <- 2
# row.clusters[pos.3] <- 99
# row.clusters[pos.4] <- 5
# row.clusters[pos.5] <- 2
# row.clusters[pos.6] <- 4
# row.clusters[pos.7] <- 2
# row.clusters[pos.8] <- 2
# row.clusters[pos.9] <- 2
# row.clusters[pos.10] <- 5
# row.clusters[pos.11] <- 1
# row.clusters[pos.12] <- 5
#
# row.clusters <- row.clusters[-pos.3] # removing cluster 3
# sig_zscore_pruned <- sig_zscore[!(row.names(sig_zscore) %in% names(pos.3)), ] # removing cluster 3 genes from sig_zscore
# num.clusters <- 5


# Vero rnaseq
# row.clusters[pos.1] <- 3
# row.clusters[pos.2] <- 3
# row.clusters[pos.3] <- 3
# row.clusters[pos.4] <- 1
# row.clusters[pos.5] <- 2
# row.clusters[pos.6] <- 2
# row.clusters[pos.7] <- 4
# row.clusters[pos.8] <- 1
# row.clusters[pos.9] <- 5
# row.clusters[pos.10] <- 5
# row.clusters[pos.11] <- 5
# row.clusters[pos.12] <- 5
#
# num.clusters <- 5


# Vero riboseq
# row.clusters[pos.1] <- 5
# row.clusters[pos.2] <- 2
# row.clusters[pos.3] <- 8
# row.clusters[pos.4] <- 9
# row.clusters[pos.5] <- 3
# row.clusters[pos.6] <- 1
# row.clusters[pos.7] <- 3
# row.clusters[pos.8] <- 1
# row.clusters[pos.9] <- 10
# row.clusters[pos.10] <- 4
# row.clusters[pos.11] <- 7
# row.clusters[pos.12] <- 6
#
# num.clusters <- 10

### END ###



write.table(sig_zscore_pruned,
            file = file.path(path, "sig_zscore", paste0(outputname, "_sig_zscore_pruned")),
            quote = F,
            sep = "\t")



## Saving cpm table of significant genes and their cluster membership info ##
sig_cpm <- data.frame(sig_cpm)
sig_cpm$cluster <- as.integer(row.clusters[match(rownames(sig_cpm), names(row.clusters))])
write.table(sig_cpm,
            file = file.path(path, "sig_zscore", paste0(outputname, "_sig_cpm_cluster")),
            quote = F,
            sep = "\t")


## Generating and saving cluster membership ##

gene_cluster <- data.frame(names(row.clusters), as.integer(row.clusters))
colnames(gene_cluster) <- c("gene_name", "cluster")

gene_cluster_sorted <- gene_cluster[order(gene_cluster$cluster), ]
row.names(gene_cluster_sorted) <- seq(nrow(gene_cluster_sorted))

write.csv(gene_cluster_sorted, file.path(path, paste0(outputname, "_cluster_membership.csv")))





### Plotting Heatmap ###


## ISGs to be labeled in the heatmap ##

# Only pick one from "HBEC" and "Vero" and comment out the other one
# Here, Vero is used as an example, and the HBEC part is commented out.

### START ###
# HBEC
# isg <- c("IFI6", "XAF1", "IFITM1", "IFI44L", "AIM2", "OAS1",
#          "IFI44", "CCL20", "IFIT1", "OAS2", "OAS3", "IFIH1",
#          "IFIT3", "CMPK2", "OASL", "IDO1", "ISG15", "IFNL1",
#          "MX2", "IFIT5", "IL6", "CXCL11", "CXCL12", "CXCL3",
#          "CXCL6", "CXCL9", "CXCL2", "SELL", "CARD17", "NOS2", "TNFAIP6")
# isg_tc <- isg[isg %in% names(row.clusters)] # ISGs present in the heatmap
# isg_ir <- isg[isg %in% names(row.clusters[row.clusters == 2])] # # ISGs present in the immune response cluster
# gene_label_pos <- which(row.names(sig_zscore_pruned) %in% isg_ir)
# gene_label <- row.names(sig_zscore_pruned)[gene_label_pos]


# Vero
isg <- c("NR4A3", "OASL", "FOS", "CXCL8", "CXCL11", "NFKBIA",
         "CXCL3", "IFI44", "ISG15", "EGR1", "EGR2", "IFIT1",
         "IFIT2", "IFIT3", "CXCR4", "IL6", "IRF1", "IL11")
isg_tc <- isg[isg %in% names(row.clusters)]

# Vero rnaseq only
isg_ir <- isg[isg %in% names(row.clusters[row.clusters == 1 | row.clusters == 3])] # 1 and 3 are immune response clusters for Vero rnaseq

# Vero riboseq only
isg_ir <- isg[isg %in% names(row.clusters[row.clusters == 1 | row.clusters == 2])] # 1 and 2 are immune response clusters for Vero riboseq

gene_label_pos <- which(row.names(sig_zscore_pruned) %in% isg_ir)
gene_label <- row.names(sig_zscore_pruned)[gene_label_pos]

### END ###




# Column ordering used in Heatmap() function #
# The purpose is to separate donors in the heatmap.
# Different letters represent different donors.

# HBEC only
split_order <- c("a", "a", "b", "a", "a", "b", "b", "a", "a", "b", "b", "a", "a", "b", "b", "a", "a", "b", "b")

# Vero only
split_order <- rep(c("a", "b", "c"), 5)



colPalette <- c("#AEC7E87F", "#98DF8A7F", "#FF98967F",
                "#C49C947F", "#C5B0D57F", "#FFBB787F",
                "paleturquoise", "seagreen1", "orchid1", "wheat3")


# Left color block annotation #
# Only choose one of the four following annotation block labels and comment out the others
block.labels <- c("", "Immune Response Clusters", "", "", "", "") # HBEC rnaseq
block.labels <- c("", "Immune Response Clusters", "", "", "") # HBEC riboseq
block.labels <- c("Immune\nResponse 1", "", "Immune\nResponse 2", "", "") # Vero rnaseq
block.labels <- c("Immune Res.       \nClusters       ", "", "", "", "", "", "", "", "", "") # Vero riboseq

cluster.rowAnnot <- rowAnnotation(block = anno_block(gp = gpar(fill = colPalette,
                                                               col = NA),
                                                     labels = block.labels,
                                                     labels_gp = gpar(fontsize = 8)),
                                  width = unit(4, "mm"))


# Right gene label annotation #
gene.rowAnnot <- rowAnnotation(gene.name = anno_mark(at = gene_label_pos,
                                                     labels = gene_label,
                                                     labels_gp = gpar(fontsize = 7),
                                                     link_gp = gpar(lwd = 0.5),
                                                     link_width = unit(4, "mm"),
                                                     padding = unit(0.5, "mm")))


# Color mapping function #
col_fun <- colorRamp2(breaks = seq(-3, 3, length = 256),
                      colors = rev(colorRampPalette(brewer.pal(10, "RdBu"))(256)))


# Heatmap #
heatmap <- Heatmap(as.matrix(sig_zscore_pruned),
                   # labels
                   column_title = paste0("Differentially Expressed Genes\nn = ", nrow(sig_zscore_pruned)),
                   column_title_gp = gpar(fontsize = 9),
                   show_row_names = F,
                   column_names_gp = gpar(fontsize = 7),
                   name = "z-score",
                   col = col_fun,

                   # legends (are drawn manually)
                   show_heatmap_legend = F,

                   # clustering
                   cluster_columns = F,
                   clustering_distance_rows = "pearson",
                   cluster_row_slices = F,
                   show_row_dend = F,
                   split = row.clusters,

                   # splitting
                   column_split = factor(split_order),
                   cluster_column_slices = F,
                   column_gap = unit(2, units = "mm"),

                   # labels
                   row_title = NULL,

                   # annotation
                   left_annotation = cluster.rowAnnot,
                   right_annotation = gene.rowAnnot,

                   # size
                   width = ncol(sig_zscore_pruned) * 0.3,

                   # disable raster graphics
                   use_raster = F
)


# Custom z-score color legend #
color_legend <- Legend(col_fun = col_fun,
                       title = "z-score",
                       title_gp = gpar(fontsize = 7),
                       title_position = "topcenter",
                       labels_gp = gpar(fontsize = 7),
                       grid_width = unit(2, units = "mm"))



png(file.path(path, "heatmap", paste0(outputname, ".png")), height = 2000, width = 1000, res = 300)
draw(heatmap)
draw(color_legend, x = unit(0.9, "npc"), y = unit(0.3, "npc"))
dev.off()

