#' @include seurat.R
NULL

# Set up dim.reduction class

dim.reduction <- setClass("dim.reduction", slots = list(
  rotation = "matrix", x = "matrix", x.full = "matrix", sdev = "numeric", key = "character", misc = "ANY"
))

#' Dimensional Reduction
#' 
#' Various methods for dimensional reductions
#' 
#' @param object Seurat object
#' @param reduction.type Type of dimensional reduction to run. Options include "pca", "pcafast", 
#' "ica", "icafast" 
#' @param genes.use Genes to use as input for the dimensional reduction technique. Default is 
#' object@@var.genes.
#' @param dims.store Number of dimensions to store
#' @param dims.compute Number of dimensions to compute (for fast approximations)
#' @param use.imputed Whether to run the dimensional reduction on imputed values.
#' @param rev.reduction By default, computes the dimensional reduction on the cell x gene matrix.
#' Setting to true will compute it on the transpose (gene x cell matrix).
#' @param print.results Print the top genes associated with each dimension
#' @param dims.print Number of dimensions to print genes for
#' @param genes.print Number of genes to print for each PC
#' @param ... Additional arguments to be passed to specific reduction technique
#' @return Returns a Seurat object with the dimensional reduction information stored 
#' @export
DimReduction <- function(object, reduction.type = NULL, genes.use = NULL, dims.store = 40, 
                         dims.compute = 40, use.imputed = FALSE, rev.reduction = FALSE, 
                         print.results = TRUE, dims.print = 5, genes.print = 30, ica.fxn=icafast,...){
  
  if (length(object@scale.data) == 0){
    stop("Object@scale.data has not been set. Run ScaleData() and then retry.")
  }
  if (length(object@var.genes) == 0 && is.null(genes.use)) {
    stop("Variable genes haven't been set. Run MeanVarPlot() or provide a vector of genes names in 
         genes.use and retry.")
  }
  
  dims.store=min(dims.store,dims.compute)
  if (use.imputed) {
    data.use <- t(scale(t(object@imputed)))
  }
  else{
    data.use <- object@scale.data
  }
  
  genes.use <- set.ifnull(genes.use, object@var.genes)
  genes.use <- unique(genes.use[genes.use %in% rownames(data.use)])
  genes.var <- apply(data.use[genes.use, ], 1, var)
  genes.use <- genes.use[genes.var > 0]
  genes.use <- genes.use[!is.na(genes.use)]
  
  data.use <- data.use[genes.use, ]
  
  # call reduction technique
  reduction.type <- tolower(reduction.type)
  if(reduction.type == "pca"){
    pcaobj <- RunPCA(data.use = data.use, rev.pca = rev.reduction, pcs.store = dims.store, ...)
    object@dr$pca <- pcaobj
  }
  if(reduction.type == "pcafast") {
    pcafastobj <- RunPCAFast(data.use = data.use, rev.pca = rev.reduction, pcs.store = dims.store, 
                             pcs.compute = dims.compute, ...)
    object@dr$pca <- pcafastobj
  }
  if(reduction.type == "ica") {
    icaobj=RunICA(data.use = data.use, ics.compute=dims.store, rev.ica = rev.reduction, ics.store = dims.store,ica.fxn = ica.fxn,...)
    object@dr$ica=icaobj
  }
  
  #if(reduction.type == "icafast") print("doit")
  
  # print results
  if(print.results){
    results <- eval(parse(text = paste0("object@dr$", reduction.type, "@x")))
    for(i in 1:dims.print) {
      genes.ordered <- results[order(results[, i]), ]
      top.genes <- genes.ordered[1:genes.print, ]
      print(colnames(top.genes)[i])
      print(rownames(top.genes))
      print("")
      
      top.genes <- genes.ordered[(nrow(genes.ordered) - genes.print + 1) : nrow(genes.ordered), ]
      print(rev(rownames(top.genes)))
      print("")
      print("")
    }
  }
  return(object)
  } 

RunPCA <- function(data.use, rev.pca, pcs.store, ...){
  pcs.store <- min(pcs.store, ncol(data.use))
  pca.results <- NULL
  if(rev.pca){
    pca.results <- prcomp(data.use, ...)
    x <- pca.results$x[, 1:pcs.store]
    rotation <- pca.results$rotation[, 1:pcs.store]
  }
  else{
    pca.results = prcomp(t(data.use), ...)
    x <- pca.results$rotation[, 1:pcs.store]
    rotation <- pca.results$x[, 1:pcs.store]
  }
  pca.obj <- new("dim.reduction", x = x, rotation = rotation, sdev = pca.results$sdev, key = "PC")
  return(pca.obj)  
}

RunICA <- function(data.use, ics.compute, rev.ica, ica.fxn=icafast, ics.store,...) {
  ics.store <- min(ics.store, ncol(data.use))
  ica.results <- NULL
  if(rev.ica){
    ica.results <- ica.fxn(data.use, ics.compute,...)
    rotation <- ica.results$M[,1:ics.store]
  }
  else{
    ica.results = ica.fxn(t(data.use),ics.compute,...)
    rotation <- ica.results$S[,1:ics.store]
  }
  
  x=(as.matrix(data.use)%*%as.matrix(rotation))
  colnames(x)=paste("IC",1:ncol(x),sep="")
  colnames(rotation)=paste("IC",1:ncol(x),sep="")
  
  ica.obj <- new("dim.reduction", x = x, rotation = rotation, sdev = sqrt(ica.results$vafs), key = "IC")
  return(ica.obj)  
}

RunPCAFast <- function(data.use, rev.pca, pcs.store, pcs.compute, ...){
  pcs.compute <- min(pcs.compute, ncol(data.use))
  pcs.store <- min(pcs.store, pcs.compute)
  pca.results <- NULL
  if(rev.pca){
    pca.results <- irlba(data.use, nv = pcs.compute, ...)
    x <- pca.results$u[, 1:pcs.store]
    rotation <- pca.results$v[, 1:pcs.store]
  }
  else{
    pca.results <- irlba(t(data.use), nv = pcs.compute, ...)
    x <- pca.results$v[, 1:pcs.store]
    rotation <- pca.results$u[, 1:pcs.store]
    
  }
  rownames(x) <- rownames(data.use)
  colnames(x) <- paste0("PC", 1:pcs.compute)
  rownames(rotation) <- colnames(data.use)
  colnames(rotation) <- colnames(x)
  pca.obj <- new("dim.reduction", x = x, rotation = rotation, sdev = pca.results$d, key = "PC")
  return(pca.obj)
}

#' Convert old Seurat object to accomodate new features
#' 
#' Adds the object@@dr slot to older objects and moves the stored PCA/ICA analyses to new slot
#' 
#' @param object Seurat object
#' @return Returns a Seurat object compatible with latest changes
#' @export
ConvertSeurat <- function(object) {
  object@dr <- list()
  pca.x <- matrix()
  pca.x.full <- matrix()
  pca.rotation <- matrix()
  pca.sdev <- numeric()
  pca.misc <- NULL
  
  if (length(object@pca.x) > 0) pca.x <- as.matrix(object@pca.x)
  if (length(object@pca.x.full) > 0) pca.x.full <- as.matrix(object@pca.x.full)
  if (length(object@pca.rot) > 0) pca.rotation <- as.matrix(object@pca.rot)
  if (length(object@pca.obj) > 0) {
    pca.sdev <- object@pca.obj[[1]]$sdev
    pca.misc <- object@pca.obj[[1]]
  }
  if(length(pca.x) > 1 || length(pca.x.full) > 1 || length(pca.rotation) > 1 || length(pca.sdev) > 0  
     || !is.null(pca.misc)) {
    pca.obj <- new("dim.reduction", x = pca.x, x.full = pca.x.full, rotation = pca.rotation, 
                   sdev = pca.sdev, key = "PC", misc = pca.misc)
    object@dr$pca <- pca.obj
  }

  ica.x <- matrix()
  ica.rotation <- matrix()
  ica.sdev <- numeric()
  ica.misc <- NULL
  if (length(object@ica.x) > 0) ica.x <- as.matrix(object@ica.x)
  if (length(object@ica.rot) > 0) ica.rotation <- as.matrix(object@ica.rot)
  if (length(object@ica.obj) > 0) {
    ica.sdev <- sqrt(object@ica.obj[[1]]$vafs)
    ica.misc <- object@ica.obj[[1]]
  }

  if(length(ica.x) > 1 || length(ica.rotation) > 1 || length(ica.sdev) > 0  || !is.null(ica.misc)) {
    ica.obj <- new("dim.reduction", x = ica.x, rotation = ica.rotation, sdev = ica.sdev, key = "IC", 
                   misc = "ica.misc")
    object@dr$ica <- ica.obj
  }
  
  return(object)
}

DimTopCells <- function(object,dim.use=1,reduction.type="pca",num.cells=NULL,do.balanced=FALSE) {
  #note that we use topGenesForDim, but it still works
  
  #error checking
  if (!(reduction.type%in%names(object@dr))) {
    stop(paste(reduction.type, " dimensional reduction has not been computed"))
  }
  num.cells=set.ifnull(num.cells,length(object@cell.names))
  dim_scores=eval(parse(text=paste("object@dr$",reduction.type,"@rotation",sep="")))
  i=dim.use
  dim.top.cells=unique(unlist(lapply(i,topGenesForDim,dim_scores,do.balanced,num.cells,reduction.type)))
  return(dim.top.cells)
}

DimTopGenes <- function(object,dim.use=1,reduction.type="pca",num.genes=30,use.full=F,do.balanced=FALSE) {
  #note that we use topGenesForDim, but it still works
  #error checking
  if (!(reduction.type%in%names(object@dr))) {
    stop(paste(reduction.type, " dimensional reduction has not been computed"))
  }
  dim_scores=eval(parse(text=paste("object@dr$",reduction.type,"@x",sep="")))
  if (use.full) dim_scores=eval(parse(text=paste("object@dr$",reduction.type,"@x.full",sep="")))
  i=dim.use
  dim.top.genes=unique(unlist(lapply(i,topGenesForDim,dim_scores,do.balanced,num.genes,reduction.type)))
  return(dim.top.genes)
}
