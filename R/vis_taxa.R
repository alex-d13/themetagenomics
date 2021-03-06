#' @rdname vis
#'
#' @param taxa_bar_n Number of taxa to show in the frequency bar plot.
#'   Defaults to 30.
#' @param top_n Number of taxonomic groups to colorize in the frequency
#'   bar plot. Defaults to 7.
#' @param method Method for estimating topic correlations links.
#'   Defaults to huge.
#' @param corr_thresh Threshold to set correlations to 0 when method
#'   is set to simple. Defaults to .01.
#' @param lambda_step Value designating the lambda stepsize for calculating
#' taxa relevance. Recommended to be between .01 and .1. Defaults to .1.
#'
#' @export
vis.taxa <- function(object,taxa_bar_n=30,top_n=7,method=c('huge','simple'),corr_thresh=.01,lambda_step=.01,...){

  topics <- object$topics
  topic_effects <- object$topic_effects
  tax_table <- object$topics$tax_table

  method <- match.arg(method)

  fit <- topics$fit
  K <- fit$settings$dim$K
  vocab <- fit$vocab
  taxa <- tax_table[vocab,]
  taxon <- paste0(pretty_taxa_names(taxa),' (',vocab,')')
  taxa <- rename_taxa_to_other(topics$docs,taxa,top_n=top_n,type='docs',as_factor=TRUE)
  rownames(taxa) <- taxon

  corr <- stm::topicCorr(fit,method=method,cutoff=corr_thresh)

  colors_order <- sort(as.character(c(-1,0,1)))
  colors <- c('gray','indianred3','dodgerblue3','indianred4','dodgerblue4','gray15')
  names(colors) <- c('0','1','-1','2','-2','00')

  covariates <- lapply(names(topic_effects),identity)
  names(covariates) <- tolower(names(topic_effects))
  est_range <- range(c(sapply(topic_effects, function(x) unlist(x$est))))

  doc_lengths <- sapply(topics$docs,function(x) sum(x[2,]))

  theta <- fit$theta
  rownames(theta) <- names(topics$docs)
  colnames(theta) <- paste0('T',1:K)
  if (min(theta) == 0){
    min_theta <- min(theta[theta > 0])
    theta <- theta + min_theta
    theta <- theta/rowSums(theta)
  }

  beta <- exp(fit$beta$logbeta[[1]])
  colnames(beta) <- taxon
  rownames(beta) <- paste0('T',1:K)
  if (min(beta) == 0){
    min_beta <- min(beta[beta > 0])
    beta <- beta + min_beta
    beta <- beta/rowSums(beta)
  }

  topic_freq <- colSums(theta*doc_lengths)
  topic_marg <- topic_freq/sum(topic_freq)
  term_topic_freq <- beta*topic_freq

  # compute term frequencies as column sums of term.topic.frequency
  # we actually won't use the user-supplied term.frequency vector.
  # the term frequencies won't match the user-supplied frequencies exactly
  # this is a work-around to solve the bug described in Issue #32 on github:
  # https://github.com/cpsievert/LDAvis/issues/32
  term_freq <- colSums(term_topic_freq) # topic_freq <- colSums(theta*doc_lengths)

  # marginal distribution over terms (width of blue bars)
  term_marg <- term_freq/sum(term_freq)

  beta <- t(beta)

  # compute the distinctiveness and saliency of the terms:
  # this determines the R terms that are displayed when no topic is selected
  topic_g_term <- beta/rowSums(beta)  # (W x K)
  kernel <- topic_g_term*log(t(t(topic_g_term)/topic_marg))
  distinctiveness <- rowSums(kernel)
  saliency <- term_marg*distinctiveness

  # Order the terms for the "default" view by decreasing saliency:
  default_terms <- taxon[order(saliency,decreasing=TRUE)][1:taxa_bar_n]
  counts <- as.integer(term_freq[match(default_terms,taxon)])
  taxa_n_rev <- rev(seq_len(taxa_bar_n))

  default <- data.frame(Term=default_terms,
                        logprob=taxa_n_rev,
                        loglift=taxa_n_rev,
                        Freq=counts,
                        Total=counts,
                        Category='Default',
                        stringsAsFactors=FALSE)
  default$Taxon <- taxa[default$Term,'Phylum']
  default$Term <- factor(default$Term,levels=rev(default$Term),ordered=TRUE)

  topic_seq <- rep(seq_len(K),each=taxa_bar_n)
  category <- paste0('T',topic_seq)
  lift <- beta/term_marg

  # Collect taxa_bar_n most relevant terms for each topic/lambda combination
  # Note that relevance is re-computed in the browser, so we only need
  # to send each possible term/topic combination to the browser
  find_relevance <- function(i){
    relevance <- i*log(beta) + (1 - i)*log(lift)
    idx <- apply(relevance,2,function(x) order(x,decreasing=TRUE)[seq_len(taxa_bar_n)])
    indices <- cbind(c(idx),topic_seq)
    data.frame(Term=taxon[idx],
               Category=category,
               logprob=round(log(beta[indices]),4),
               loglift=round(log(lift[indices]),4),
               stringsAsFactors=FALSE)
  }

  lambda_seq <- seq(0,1,by=lambda_step) # 0.01
  tinfo <- lapply(as.list(lambda_seq),find_relevance)
  tinfo <- unique(do.call('rbind', tinfo))
  tinfo$Total <- term_freq[match(tinfo$Term,taxon)]
  rownames(term_topic_freq) <- paste0('T',seq_len(K))
  colnames(term_topic_freq) <- taxon
  tinfo$Freq <- term_topic_freq[as.matrix(tinfo[c('Category','Term')])]
  tinfo <- rbind(default[,-7],tinfo)

  new_order <- default

  shinyApp(

    ui <- fluidPage(

      tags$head(tags$style(type='text/css','.side{font-size: 10px;} .side{color: gray;} .side{font-weight: bold;}')),
      tags$head(tags$style(type='text/css','.below{font-size: 10px;} .below{color: gray;} .below{font-weight: bold;}')),
      tags$head(tags$style(type='text/css','.capt{font-size: 9px;} .capt{color: gray;} .capt{font-weight: bold;} .capt{margin-top: -20px;}')),

      titlePanel('Taxa Features'),

      fixedRow(
        column(1,''),
        column(10,htmlOutput('text1')),
        column(1,'')
      ),

      br(),

      fixedRow(
        column(2,selectInput('choose', label='Covariate',
                             choices=covariates,selected=covariates[[1]]),
               fixedRow(column(1,''),
                        column(11,tags$div(paste0('Choosing a covariate determines which weight estimates will shown',
                                                    ' The order of the topics will be adjusted accordingly. By clicking',
                                                    ' an estimate, all figures below will rerender.'),class='side')))),
        column(10,plotlyOutput('est',height='200px'))
      ),

      br(),

      fixedRow(
        column(1,radioButtons('dim',label=strong('Dim'),
                              choices=list('2D'='2d','3D'='3d'),
                              selected='2d')),
        column(3,selectInput('dist',label=strong('Method'),
                              choices=list('Bray Curtis'='bray','Jaccard'='jaccard','Euclidean'='euclidean',
                                           'Hellinger'='hellinger','Chi Squared'='chi2','Jensen Shannon'='jsd',
                                           't-SNE'='tsne'),
                              selected='jsd')),
        column(1,style='padding: 25px 0px;',actionButton('reset','Reset')),
        column(2,numericInput('k_in',label=strong('Topic Number'),value=0,min=0,max=K,step=1)),
        column(3,sliderInput('lambda',label=strong('Lambda'),min=0,max=1,value=1,step=lambda_step)),
        column(2,selectInput('taxon',label=strong('Taxon'),
                             choices=list('Phylum'='Phylum','Class'='Class','Order'='Order',
                                          'Family'='Family','Genus'='Genus')))
      ),

      fixedRow(
        column(1,tags$div('Number of components to plot.',class='capt')),
        column(3,tags$div('Type of distance and method for ordination.',class='capt')),
        column(1,tags$div('Reset topic selection.',class='capt')),
        column(2,tags$div('Current selected topic.',class='capt')),
        column(3,tags$div(paste0('Relative weighting that influences taxa shown in barplot.',
                                 ' If equal to 1, p(taxa|topic)l if 0, p(taxa|topic)/p(taxa).'),class='capt')),
        column(2,tags$div('Taxonomic group to dictate bar plot shading',class='capt'))
      ),

      fixedRow(
        column(6,offset=0,height='600px',plotlyOutput('ord')),
        column(6,offset=0,height='600px',plotOutput('bar'))
      ),

      fixedRow(
        column(6,tags$div(paste0('Ordination of the samples over topics distribution theta, colored according to',
                                 ' the weights shown in the scatter plot above. The radius of a given point',
                                 ' represents the marginal topic frequency. The amount of variation explained is',
                                 ' annotated on each axis.'),class='below')),
        column(6,tags$div(paste0('Bar plot representing the taxa frequencies. When no topic is selected, the overall',
                                 ' taxa frequencies are shown, colored based on the selected taxonomy and ordered in',
                                 ' in terms of saliency. When a topic is chosen, the red bars show the margina taxa',
                                 ' frequency within the selected topic, ordered in terms of relevency, which in turn',
                                 ' can be reweighted by adjusting the lambda slider.'),class='below'))
      ),

      br(),

      fixedRow(
        column(1,''),
        column(10,htmlOutput('text2')),
        column(1,'')
      ),

      networkD3::forceNetworkOutput('corr')

    ),


    server = function(input,output,session){

      REL <- reactive({

        if (show_topic$k != 0){

          current_k <- paste0('T',show_topic$k)

          l <- input$lambda

          tinfo_k <- tinfo[tinfo$Category == current_k,]  #subset(tinfo,Category == current_k)
          rel_k <- l*tinfo_k$logprob + (1-l)*tinfo_k$loglift
          new_order <- tinfo_k[order(rel_k,decreasing=TRUE)[1:taxa_bar_n],]
          new_order$Term <- as.character.factor(new_order$Term)
          new_order$Taxon <- taxa[new_order$Term,input$taxon]
          new_order$Term <- factor(new_order$Term,levels=rev(new_order$Term),ordered=TRUE)

        }else{

          new_order <- default
          new_order$Taxon <- taxa[as.character.factor(new_order$Term),input$taxon]

        }

        new_order

      })


      EST <- reactive({
        suppressWarnings({

          covariate <- input$choose

          est_mat <- topic_effects[[covariate]]$est

          df0 <- data.frame(topic=paste0('T',1:K),
                           est=est_mat[,1],
                           lower=est_mat[,2],
                           upper=est_mat[,3],
                           sig=ifelse(1:K %in% topic_effects[[covariate]]$sig,'1','0'))
          df0$sig <- factor(as.character(sign(df0$est) * as.numeric(as.character.factor(df0$sig))),levels=c('0','1','-1'),ordered=TRUE)
          df <- df0[order(topic_effects[[covariate]][['rank']]),]
          df$topic <- factor(df$topic,levels=df$topic,ordered=TRUE)

          p_est <- ggplot(df,aes_(~topic,y=~est,ymin=~lower,ymax=~upper,color=~sig)) +
            geom_hline(yintercept=0,linetype=3)
          p_est <- p_est +
            geom_pointrange(size=2) +
            theme_minimal() +
            labs(x='',y='Estimate') +
            scale_color_manual(values=c('gray','indianred3','dodgerblue3'),drop=FALSE) +
            scale_fill_brewer(type='qual',palette=6,direction=-1) +
            theme(legend.position='none',
                  axis.text.x=element_text(angle=-90,hjust=0,vjust=.5))

          list(p_est=p_est,k_levels=levels(df$topic),covariate=covariate,df0=df0)

        })
      })

      output$est <- renderPlotly({

        ggplotly(EST()$p_est,source='est_hover',tooltip=c('topic','est','lower','upper'))

      })

     output$text1 <- renderUI({

       ui_interval <- paste0(100-2*as.numeric(gsub('%','',colnames(topic_effects[[EST()$covariate]][['est']])[2])),'%')

       HTML(sprintf("Below are the results of a %s topic STM. THe scatter plot shows the posterior estimates and %s uncertainty
                    intervals for the chosen covariate, %s. In all figures, red and blue implies positive and negative weights with
                    intervals that do not enclose 0, respectively.
                    Different covariates can be chosen via the selection box (upper-left).
                    The next row shows the ordination of the topics over taxa distribution (left) and the frequencies of
                    the top %s taxa (in terms of saliency) across all topics. By selecting a topic, the relative
                    frequencies of the taxa within that topic are shown in red. The ordination figure can be shown in
                    either 2D or 3D and the ordination method can be adjusted. Lambda adjusts the relevance calculation.
                    Choosing the taxon adjusts the group coloring for the bar plot. Clicking Reset resets the topic selection.",
                    K,ui_interval,tolower(EST()$covariate),taxa_bar_n))
     })

     output$text2 <- renderUI({
       HTML(paste0('Below shows topic-to-topic correlations from the samples over topics distribution. The edges represent positive',
                   ' correlation between two topics, with the size of the edge reflecting to the magnitude of the correlation.',
                   ' The size and color of the nodes are slightly different than the ordination figure. Here, in addition to the color',
                   ' reflecting the direction of the covariate weight estimate, the size indicates the magnitude of the estimate and',
                   ' not the marginal topic frequencies like that which is shown in the ordination figure.'))
     })

     output$ord <- renderPlotly({

       beta <- t(beta)

       if (input$dist == 'hellinger'){

         d <- cmdscale(vegan::vegdist(vegan::decostand(beta,'norm'),method='euclidean'),3,eig=TRUE)

       }else if (input$dist == 'chi2'){

         d <- cmdscale(vegan::vegdist(vegan::decostand(beta,'chi.square'),method='euclidean'),3,eig=TRUE)

       }else if (input$dist == 'jsd'){

         d <- cmdscale(proxy::dist(beta,jsd),3,eig=TRUE)

       }else if (input$dist == 'tsne'){

         p <- 30
         d <- try(Rtsne::Rtsne(beta,3,theta=.5,perplexity=p),silent=TRUE)
         while(class(d)[1] == 'try-error'){
           p <- p-1
           d <- try(Rtsne::Rtsne(beta,3,theta=.5,perplexity=p),silent=TRUE)
         }
         if (p < 30) cat(sprintf('Performed t-SNE with perplexity = %s.\n',p))
         d$points <- d$Y
         d$eig <- NULL

       }else{

         d <- cmdscale(vegan::vegdist(beta,method=input$dist),3,eig=TRUE)

       }

       eig <- d$eig[1:3]/sum(d$eig)
       colnames(d$points) <- c('Axis1','Axis2','Axis3')
       df <- data.frame(d$points,EST()$df0)
       df$marg <- topic_marg

       df$colors <- colors[as.character(df$sig)]

       if (input$dim == '2d'){

         p1 <- plot_ly(df,source='ord_click')
         p1 <- add_trace(p1,
                 x=~Axis1,y=~Axis2,size=~marg,
                 type='scatter',mode='markers',sizes=c(5,125),
                 color=I(df$colors),opacity=.5,
                 marker=list(symbol='circle',sizemode='diameter',line=list(width=3,color='#FFFFFF')),
                 text=~paste('<br>Topic:',topic),hoverinfo='text')
         p1 <- layout(p1,
                      showlegend=FALSE,
                      xaxis=list(title=sprintf('Axis 1 [%.02f%%]',eig[1]*100),
                                 showgrid=FALSE),
                      yaxis=list(title=sprintf('Axis 2 [%.02f%%]',eig[2]*100),
                                 showgrid=FALSE),
                      paper_bgcolor='rgb(243, 243, 243)',
                      plot_bgcolor='rgb(243, 243, 243)')
         p1 <- add_annotations(p1,x=df$Axis1,y=df$Axis2,text=df$topic,showarrow=FALSE,
                               font=list(size=10))

         h <- event_data('plotly_hover',source='est_hover')

         if (!is.null(h)){
           k <- EST()$k_levels[h[['x']]]

           if (length(k) > 0){
             df_update <- df[df$topic == k,]


             if (df_update$sig == '1') df_update$sig <- '2' else if(df_update$sig== '-1') df_update$sig <- '-2' else df_update$sig<- '00'
             df_update$colors <- colors[df_update$sig]

             p1 <- add_markers(p1,
                               x=df_update$Axis1,y=df_update$Axis2,opacity=.8,color=I(df_update$color),
                               marker=list(size=150,symbol='circle',sizemode='diameter',line=list(width=3,color='#000000')))
           }

           p1

         }
       }

       if (input$dim == '3d'){

         p1 <- plot_ly(df,source='ord_click',
                 x=~Axis1,y=~Axis2,z=~Axis3,size=~marg,
                 type='scatter3d',mode='markers',sizes=c(5,125),
                 color=I(df$colors),opacity=.5,
                 marker=list(symbol='circle',sizemode='diameter'),
                 text=~paste('<br>Topic:',topic),hoverinfo='text')

         p1 <- layout(p1,
                      showlegend=FALSE,
                      scene=list(
                        xaxis=list(title=sprintf('Axis 1 [%.02f%%]',eig[1]*100),
                                   showgrid=FALSE),
                        yaxis=list(title=sprintf('Axis 2 [%.02f%%]',eig[2]*100),
                                   showgrid=FALSE),
                        zaxis=list(title=sprintf('Axis 3 [%.02f%%]',eig[3]*100),
                                   showgrid=FALSE)),
                      paper_bgcolor='rgb(243, 243, 243)',
                      plot_bgcolor='rgb(243, 243, 243)')

       }

       p1

     })

     show_topic <- reactiveValues(k=0)

     observeEvent(event_data('plotly_click',source='ord_click'),{

       s <- event_data('plotly_click',source='ord_click')

       if (is.null(s)){

         show_topic$k <- 0
         updateNumericInput(session,'k_in',value=0)

       }else{

         t_idx <- s$pointNumber + 1
         updateNumericInput(session,'k_in',value=t_idx)
         show_topic$k <- t_idx

       }

     })

     observeEvent(input$k_in,{

       show_topic$k <- input$k_in

     })

     observeEvent(input$reset,{

       show_topic$k <- 0
       updateNumericInput(session,'k_in',value=0)

     })

     output$bar <- renderPlot({

       if (show_topic$k != 0){

         p_bar <- ggplot(data=REL()) +
           geom_bar(aes_(~Term,~Total,fill=~Taxon),stat='identity',color='white',alpha=.6) +
           geom_bar(aes_(~Term,~Freq),stat='identity',fill='darkred',color='white')

       }else{

         p_bar <- ggplot(data=REL()) +
           geom_bar(aes_(~Term,~Total,fill=~Taxon),stat='identity',color='white',alpha=1)

       }

       p_bar +
         coord_flip() +
         labs(x='',y='Frequency',fill='') +
         theme(axis.text.x=element_text(angle=-90,hjust=0,vjust=.5),
               legend.position='bottom') +
         viridis::scale_fill_viridis(discrete=TRUE,drop=FALSE) +
         guides(fill=guide_legend(nrow=2))

     })

     output$corr <- networkD3::renderForceNetwork({

       effects_sig <- topic_effects[[EST()$covariate]][['sig']]

       K <- nrow(corr$posadj)

       suppressWarnings({suppressMessages({
       g <- igraph::graph.adjacency(corr$posadj,mode='undirected',
                                    weighted=TRUE,diag=FALSE)

       wc <- igraph::cluster_walktrap(g)
       members <- igraph::membership(wc)

       g_d3 <- networkD3::igraph_to_networkD3(g,group=members)

       g_d3$links$edge_width <- 10*(.1+sapply(seq_len(nrow(g_d3$links)),function(r) corr$poscor[g_d3$links$source[r]+1,g_d3$links$target[r]+1]))
       g_d3$nodes$color <- 25*ifelse(1:K %in% effects_sig,1,0)*sign(topic_effects[[EST()$covariate]]$est[,1])
       g_d3$nodes$node_size <- 10*(.5+norm10(c(0,abs(topic_effects[[EST()$covariate]]$est[,1])))[-1])
       g_d3$nodes$name <- paste0('T',g_d3$nodes$name)

       networkD3::forceNetwork(Links=g_d3$links,Nodes=g_d3$nodes,
                               Source='source',Target='target',
                               charge=-25,
                               opacity=.7,
                               fontSize=12,
                               zoom=TRUE,
                               bounded=TRUE,
                               NodeID='name',
                               fontFamily='sans-serif',
                               opacityNoHover=.7,
                               Group='color',
                               Value='edge_width',
                               Nodesize='node_size',
                               linkColour='#000000',
                               linkWidth=networkD3::JS('function(d) {return d.value;}'),
                               radiusCalculation=networkD3::JS('d.nodesize'),
                               colourScale=networkD3::JS("color=d3.scaleLinear()\n.domain([-1,0,1])\n.range(['blue','gray','red']);"))

       })})

     })

 }

 )

}

#credit to themetagenomics vis_taxa.R
#this function is needed to generate the objects and values used in the namco GUI
#returns list with named values
#input: object = topic_effects_object, which is created with the themetagenomics::est() function

#' @export
prepare_vis2 <- function(object,taxa_bar_n=30,top_n=7,method='huge',corr_thresh=.01,lambda_step=.01,...){
  
  topics <- object$topics
  topic_effects <- object$topic_effects
  tax_table <- object$topics$tax_table
  
  method <- match.arg(method)
  
  fit <- topics$fit
  K <- fit$settings$dim$K
  vocab <- fit$vocab
  taxa <- tax_table[vocab,]
  taxon <- paste0(pretty_taxa_names(taxa),' (',vocab,')')
  taxa <- rename_taxa_to_other(topics$docs,taxa,top_n=top_n,type='docs',as_factor=TRUE)
  rownames(taxa) <- taxon
  
  corr <- stm::topicCorr(fit,method=method,cutoff=corr_thresh)
  
  colors_order <- sort(as.character(c(-1,0,1)))
  colors <- c('gray','indianred3','dodgerblue3','indianred4','dodgerblue4','gray15')
  names(colors) <- c('0','1','-1','2','-2','00')
  
  covariates <- lapply(names(topic_effects),identity)
  names(covariates) <- tolower(names(topic_effects))
  est_range <- range(c(sapply(topic_effects, function(x) unlist(x$est))))
  
  doc_lengths <- sapply(topics$docs,function(x) sum(x[2,]))
  
  theta <- fit$theta
  rownames(theta) <- names(topics$docs)
  colnames(theta) <- paste0('T',1:K)
  if (min(theta) == 0){
    min_theta <- min(theta[theta > 0])
    theta <- theta + min_theta
    theta <- theta/rowSums(theta)
  }
  
  beta <- exp(fit$beta$logbeta[[1]])
  colnames(beta) <- taxon
  rownames(beta) <- paste0('T',1:K)
  if (min(beta) == 0){
    min_beta <- min(beta[beta > 0])
    beta <- beta + min_beta
    beta <- beta/rowSums(beta)
  }
  
  topic_freq <- colSums(theta*doc_lengths)
  topic_marg <- topic_freq/sum(topic_freq)
  term_topic_freq <- beta*topic_freq
  
  # compute term frequencies as column sums of term.topic.frequency
  # we actually won't use the user-supplied term.frequency vector.
  # the term frequencies won't match the user-supplied frequencies exactly
  # this is a work-around to solve the bug described in Issue #32 on github:
  # https://github.com/cpsievert/LDAvis/issues/32
  term_freq <- colSums(term_topic_freq) # topic_freq <- colSums(theta*doc_lengths)
  
  # marginal distribution over terms (width of blue bars)
  term_marg <- term_freq/sum(term_freq)
  
  beta <- t(beta)
  
  # compute the distinctiveness and saliency of the terms:
  # this determines the R terms that are displayed when no topic is selected
  topic_g_term <- beta/rowSums(beta)  # (W x K)
  kernel <- topic_g_term*log(t(t(topic_g_term)/topic_marg))
  distinctiveness <- rowSums(kernel)
  saliency <- term_marg*distinctiveness
  
  # Order the terms for the "default" view by decreasing saliency:
  default_terms <- taxon[order(saliency,decreasing=TRUE)][1:taxa_bar_n]
  counts <- as.integer(term_freq[match(default_terms,taxon)])
  taxa_n_rev <- rev(seq_len(taxa_bar_n))
  
  default <- data.frame(Term=default_terms,
                        logprob=taxa_n_rev,
                        loglift=taxa_n_rev,
                        Freq=counts,
                        Total=counts,
                        Category='Default',
                        stringsAsFactors=FALSE)
  default$Taxon <- taxa[default$Term,'Phylum']
  default$Term <- factor(default$Term,levels=rev(default$Term),ordered=TRUE)
  
  topic_seq <- rep(seq_len(K),each=taxa_bar_n)
  category <- paste0('T',topic_seq)
  lift <- beta/term_marg
  
  # Collect taxa_bar_n most relevant terms for each topic/lambda combination
  # Note that relevance is re-computed in the browser, so we only need
  # to send each possible term/topic combination to the browser
  find_relevance <- function(i){
    relevance <- i*log(beta) + (1 - i)*log(lift)
    idx <- apply(relevance,2,function(x) order(x,decreasing=TRUE)[seq_len(taxa_bar_n)])
    indices <- cbind(c(idx),topic_seq)
    data.frame(Term=taxon[idx],
               Category=category,
               logprob=round(log(beta[indices]),4),
               loglift=round(log(lift[indices]),4),
               stringsAsFactors=FALSE)
  }
  
  lambda_seq <- seq(0,1,by=lambda_step) # 0.01
  tinfo <- lapply(as.list(lambda_seq),find_relevance)
  tinfo <- unique(do.call('rbind', tinfo))
  tinfo$Total <- term_freq[match(tinfo$Term,taxon)]
  rownames(term_topic_freq) <- paste0('T',seq_len(K))
  colnames(term_topic_freq) <- taxon
  tinfo$Freq <- term_topic_freq[as.matrix(tinfo[c('Category','Term')])]
  tinfo <- rbind(default[,-7],tinfo)
  
  new_order <- default
  
  return (out = list(beta = beta, 
                     tinfo = tinfo,
                     taxa_bar_n = taxa_bar_n,
                     taxa = taxa,
                     default = default,
                     topic_marg = topic_marg,
                     corr = corr,
                     lambda_step = lambda_step,
                     covariates = covariates,
                     colors=colors))
}
