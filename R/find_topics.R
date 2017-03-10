#' Fit a topic model on an OTU table
#'
#' Given an OTU table, this function converts the OTU counts
#' across samples into a document format and then fits a
#' structural topic model by wrapping the stm command from the
#' STM package, see \code{\link{stm}}.
#'
#' @param K A positive integer indicating the number of topics to
#' be estimated.
#' @param otu_table Phyloseq object or OTU table as a data frame
#' or matrix with OTU IDs as row or column names.
#' @param rows_are_taxa TRUE/FALSE whether OTUs are rows and
#' samples are columns or vice versa.
#' @param formula Formula object with no response variable or a
#' matrix containing topic prevalence covariates.
#' @param sigma_prior scalar between 0 and 1. This sets the strength
#' of regularization towards a diagonalized covariance matrix.
#' Setting the value above 0 can be useful if topics are becoming
#' too highly correlated.
#' @param model Prefit STM model object to restart an existing model.
#' @param iters Maximum number of EM iterations.
#' @param tol Convergence tolerance.
#' @param batches Number of groups for memoized inference.
#' @param seed Seed for the random number generator to reproduce
#' previous results.
#' @param verbose Logical indicating whether information should be
#' printed.
#' @param verbose_n Integer determining the intervals at which labels
#' are printed.
#' @param control List of additional parameters control portions of
#' the optimization. See details.
#' @return A list containing the topic model fit, the documents, and
#' the vocabulary.
#' @export



find_topics <- function(K,otu_table,rows_are_taxa,control=list(),...){

  if (rows_are_taxa == TRUE){

    otu_table <- t(otu_table)

  }

  if (!missing(metadata)){
    if (!identical(rownames(otu_table),rownames(metadata))) {
      stop('Please ensure that the order of sample names in the OTU table and metadata match!\n')
    }
  }

  control <- control[names(control) %in% c('gamma.enet','gamma.ic.k','gamma.ic.k',
                                           'nits','burnin','alpha','eta',
                                           'rp.s','rp.p','rp.d.group.size','SpectralRP','maxV')]

  vocab <- colnames(otu_table)
  docs <- lapply(seq_len(nrow(otu_table)), function(i) reshape_to_docs(otu_table[i,],vocab))
  names(docs) <- rownames(otu_table)

  fit <- stm_wrapper(K=K,docs=docs,vocab=vocab,control=control...)

  return(list(fit=fit,docs=docs,vocab=vocab))

}

stm_wrapper <- function(K,docs,vocab,metadata,formula=NULL,sigma_prior=0,
                        init_type='Spectral',
                        model=NULL,iters=500,tol=1e-05,batches=1,seed=NULL,
                        verbose=FALSE,verbose_n=5,control=control){

  fit <- stm::stm(K=K,documents=docs,vocab=vocab,
                  data=metadata,
                  prevalence=formula,
                  init.type=init_type,
                  sigma.prior=sigma_prior,
                  model=model,
                  max.em.its=iters,emtol=tol,ngroups=batches,
                  seed=seed,verbose=verbose,reportevery=verbose_n,control=control)

  return(fit)

}