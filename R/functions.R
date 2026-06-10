######   MODEL   #########

##` Super Simple Ecosystem Model
##` @param X        [leaf carbon, wood carbon, soil organic carbon] (units=Mg/ha)
##` @param params   model parameters
##` @param inputs   model drivers (air temperature, PAR)
##` @param verbose  provide a counter on elapsed time
SSEM.orig <- function(X, params, inputs, verbose=FALSE){ 
  timestep <- as.numeric(median(diff(as.numeric(inputs$date)), na.rm = TRUE)) ## seconds
  nt = nrow(inputs)                         ## number of time steps
  ne = nrow(X)                              ## number of ensemble members
  output = array(0.0, c(nt, ne, 12))        ## output storage [time step,ensembles,variables]
  
  ##Unit Converstion: umol/m2/sec to Mg/ha/timestep
  k = 1e-6 * 12 * 1e-6 * 10000 * timestep #mol/umol*gC/mol*Mg/g*m2/ha*sec/timestep
  
  for(t in 1:nt){
    
    ## photosynthesis
    LAI = X[, 1] * params$SLA * 0.1  #0.1 is conversion from Mg/ha to kg/m2
    GPP = pmax(0, params$alpha * (1 - exp(-0.5 * LAI)) * inputs$PAR[t])
    GPP[inputs$PAR[t] < 1e-20] = 0 ## night
    
    ## respiration & allocation
    alloc = GPP *   params[,c("falloc.1","falloc.2","falloc.3")] ## Ra, NPPwood, NPPleaf
    Rh = pmax(params$Rbasal * X[, 3] * params$Q10 ^ (inputs$temp[t] / 10), 0) ## pmax ensures SOM never goes negative
    
    ## turnover
    litterfall = X[, 1] * params$litterfall
    mortality = X[, 2] * params$mortality
    
    ## update states
    X1 = pmax(X[, 1] + alloc[, 3] * k - litterfall, 0)
    X2 = pmax(X[, 2] + alloc[, 2] * k - mortality, 0)
    X3 = pmax( X[, 3] + litterfall + mortality - Rh * k, 0)
    
    output[t,,] = cbind(X1 = X1, X2 = X2, X3 = X3,
                        LAI = X1 * params$SLA * 0.1, 
                        GPP = GPP,
                        NEP = GPP - alloc[, 1] - Rh,
                        Ra = alloc[, 1], NPPw = alloc[, 2], NPPl = alloc[, 3],
                        Rh = Rh, litterfall = litterfall, mortality = mortality)
    X = matrix(output[t, ,1:3],ncol = 3) ## current state variables become the next initial conditions
    if((t %% 1440) == 0 && verbose) print(t)             ## counter: elapsed time (30*48 = approx 1 month)
  }
  output[is.nan(output)] = 0
  output[is.infinite(output)] = 0
  return(output)
}
SSEM <- compiler::cmpfun(SSEM.orig)  ## byte compile the function to make it faster


######  SENSITIVITY ANALYSIS ####

##` @params ns    number of steps along each dimension in the sensitivity analysis
nee.sensitivity = function(ns){
  ne = ns
  sa.summary = array(NA,c(ncol(params),ns,5)) 
  
  ## calculate the median parameter vector and range
  theta_ci = apply(params, 2, quantile, c(0,0.5,1)) 
  Xbar     = matrix(apply(X.orig,2,mean),nrow=ns,ncol=3,byrow=TRUE)
  
  for(i in seq_len(ncol(params))){
    print(i)
    sa.stats = as.data.frame(matrix(NA,nrow=ns,ncol=5))
    colnames(sa.stats) =c("param","mean","RMSE","Bias","cor")
    theta_sa = as.data.frame(matrix(theta_ci[2,],nrow=ns,ncol=ncol(theta_ci),byrow = TRUE)) ## matrix of defaults
    colnames(theta_sa) = colnames(params)
    theta_sa[,i] = quantile(params[,i],seq(0,1,length=ns))                   ## Vary one parameter
    sa.ensemble = SSEM(X = Xbar,
                       params = theta_sa,
                       inputs = inputs) 
    sa.nee = sa.ensemble[,,6]
    sa.stats[,"param"] = theta_sa[,i]
    sa.stats[,"mean"] = apply(sa.nee,2,mean)
    sa.stats[,"RMSE"] = apply(sa.nee[qaqc,],2,function(E){sqrt(mean((E-O)^2))})
    sa.stats[,"Bias"] = apply(sa.nee[qaqc,],2,function(E){mean(E-O)})
    sa.stats[,"cor"] = apply(sa.nee[qaqc,],2,function(E){cor(E,O)})
    sa.summary[i,,] = as.matrix(sa.stats)
  }
  return(sa.summary)
}

sens_plot = function(var,line=TRUE){
  par(mfrow=c(3,3))
  sens = rep(NA,9)
  for(i in seq_len(nrow(sa.summary))){
    plot(sa.summary[i,,1],sa.summary[i,,var],
         main=colnames(params)[i],ylab=vname[var],
         type="b")
    if(line){
      m = lm(sa.summary[i,,var]~sa.summary[i,,1])
      abline(m,col=2)
      sens[i]=coef(m)[2]*mean(params[,i])/mean(E) ## elasticity = (dy/ybar) / (dx/xbar)
    }
  }
  names(sens)=colnames(params)
  return(sens)
}

######   VISUALIZATION  #########

##' Density plot of model param
plot_params <- function(params, hist.params = NULL){
  par(mfrow=c(5,3))                ## 5 x 3 grid of plots
  par(mar=c(2,2,4,0.7))            ## make plot margins smaller
  for(i in 1:ncol(params)){      ## loop over parameters
    new = density(params[,i])                 ## parameter density at end of PF
    if(is.null(hist.params)){
      ylim=range(new$y)
      plot(new,main=names(params)[i],xlab=" ",
           ylim=ylim)
      text(max(new$x),ylim[2]*0.9,
           paste(format(mean(params[[i]]),digits=3), ## write the mean and SD onto the figure
                 format(sd(params[[i]]),digits=3)),
           pos=2,col=2)
      
    } else {
      orig = density(hist.params[,i])      ## parameter density at start of PF
      ylim=range(c(range(new$y),range(orig$y)))
      plot(orig,main=names(params)[i],xlab=" ",
           ylim=ylim)
      lines(new,col=2,lwd=2)
      text(max(orig$x),ylim[2],
           paste("Prior",format(mean(hist.params[,i]),digits=3), ## write the mean and SD onto the figure
                 format(sd(hist.params[,i]),digits=3)),
           pos=2)
      text(max(orig$x),ylim[2]*0.9,
           paste("Final timestep:",format(mean(params[[i]]),digits=3), ## write the mean and SD onto the figure
                 format(sd(params[[i]]),digits=3)),
           pos=2,col=2)
    }
  }
}

average_timesteps <- function(arr, n_steps) {
  # Get original dimensions (1: Time, 2: Ensemble, 3: Variable)
  dims <- dim(arr)
  time_dim <- dims[1]
  
  # Group indices into numerical blocks (e.g., 1, 1, 1, 2, 2, 2...)
  groups <- rep(1:ceiling(time_dim / n_steps), each = n_steps, length.out = time_dim)
  
  # FIX: Split a plain vector so 'idx' inside lapply is a pure numeric vector
  time_list <- split(seq_len(time_dim), groups)
  
  # Calculate means per group (returns a 3D array with Time moved to the 3rd dimension)
  result_array <- sapply(time_list, function(idx) {
    apply(arr[idx, , , drop = FALSE], c(2, 3), mean, na.rm = TRUE)
  }, simplify = "array")
  
  # result_array currently has dimensions: [Ensemble, Variable, Time]
  # Bring Time back to the 1st position to match your original structure: [Time, Ensemble, Variable]
  corrected_array <- aperm(result_array, c(3, 1, 2))
  
  return(corrected_array)
}
## Basic time-series visualizations
varnames <- c("Bleaf","Bwood","BSOM","LAI","GPP","NEP","Ra",
              "NPPw","NPPl","Rh","litterfall","mortality")
units <- c("Mg/ha","Mg/ha","Mg/ha","m2/m2","umol/m2/sec","umol/m2/sec",
           "umol/m2/sec","umol/m2/sec","umol/m2/sec","umol/m2/sec",
           "Mg/ha/timestep","Mg/ha/timestep")
##' timeseries plot of model outputs
##' 
##' @param out array of model outputs
##' @param sample whether to plot a subsample of ensemble members as lines
##' @param timestep number of timesteps to aggregate, default = 1 (no aggregation)
plot_forecast <- function(out,sample=FALSE,timestep=1){
  if(sample){
    samp = sample.int(dim(out)[2],sample)
  } 
  if(timestep > 1){
    out = average_timesteps(out,timestep)
  }
  for(i in 1:9){  ## loop over variables
    ci = apply(out[, , i], 1, quantile, c(0.025, 0.5, 0.975))   ## calculate CI over ensemble members
    plot(ci[2, ], main = varnames[i], 
         xlab = "time", ylab = units[i], type='l',ylim  =range(ci))
    ciEnvelope(1:ncol(ci), ci[1, ], ci[3, ], col = col.alpha("lightGrey", 0.5)) ## plot interval
    lines(ci[2, ])   ## plot median
    if(sample){
      for(j in seq_len(sample)){
        lines(out[,j,i],lty=2,col=2)
      }
    }
  }
}


######   MISC HELPER FUNCTIONS ######

## reimplimentation of the rdirichlet function from MCMCpack
## to fix bug in how it handles alpha as a matrix
rdirichlet.orig = function (n, alpha) 
{
  l <- length(alpha)
  if(is.matrix(alpha)) l <- ncol(alpha)
  x <- matrix(rgamma(l * n, alpha), ncol = l)
  sm <- x %*% rep(1, l)
  return(x/as.vector(sm))
}

## moment matching beta prior on turnover times
beta.match <- function(mu, var){   ## Beta distribution moment matching
  a = mu * ((mu * (1 - mu) / var) - 1)
  b = a * (1 - mu) / mu
  return(data.frame(a = a, b = b))
}

K2C = function(x){x-273.15} ## Kelvin to Celsius

## Flux uncertainty functions
## Borrowed from https://github.com/PecanProject/pecan/tree/develop/modules/uncertainty/R/flux_uncertainty.R
#--------------------------------------------------------------------------------------------------#

##' Get delta between sequential flux datapoints
##' 
##' @name get.change
##' @title Get delta between sequential flux datapoints
##' @return Difference between consecutive measurements
##' @export
##' @author Mike Dietze, Carl Davidson
get.change <- function(measurement) {
  gaps <- measurement %in% c(-6999, -9999)
  # | quality > 0
  measurement[gaps] <- NA
  even <- seq(measurement)%%2 == 0
  odd <- seq(measurement)%%2 == 1
  return(measurement[even] - measurement[odd])
} # get.change

##' Calculate parameters for heteroskedastic flux uncertainty
##' 
##' @name flux.uncertainty
##' @title Calculate parameters for heteroskedastic flux uncertainty
##' @param measurement = flux time-series
##' @param QC = quality control flag time series (0 = best)
##' @param flags = additional flags on flux filtering of PAIRS (length = 1/2 that of the 
##'                time series, TRUE = use).
##' @param bin.num = number of bins (default = 10)
##' @param transform = transformation of magnitude (default = identity)
##' @param minBin = minimum number of points allowed in a bin
##' @return return.list List of parameters from the fitted uncertainty model
##' @export
##' @author Mike Dietze, Carl Davidson
flux.uncertainty <- function(measurement, QC = 0, flags = TRUE, bin.num = 10, 
                             transform = identity, minBin = 5, ...) {
  if(length(QC)==1) QC = rep(QC,length=length(measurement))
  
  ## calcuate paired differences between points
  change <- get.change(measurement)
  
  ## convert gaps to NA
  gaps <- measurement %in% c(-6999, -9999)
  # | quality > 0
  measurement[gaps] <- NA
  
  ## combine all indicators
  even <- seq(measurement) %% 2 == 0
  odd <- seq(measurement) %% 2 == 1
  Q2 <- QC[even] == 0 & QC[odd] == 0 & flags & !is.na(measurement[even]) & !is.na(measurement[odd])
  
  ## calulate error and flux magnitude for each pair of points
  indErr <- abs(change[Q2]) / sqrt(2)
  magnitude <- measurement[even][Q2]
  
  ## calculate bins
  bins <- seq(from = min(magnitude, na.rm = TRUE),
              to = max(magnitude, na.rm = TRUE), 
              length.out = bin.num)
  
  ## calculate binned mean, error, bias, and sample size
  magBin <- c()
  errBin <- c()
  biasBin <- c()
  nBin <- c()
  for (k in 1:(length(bins) - 1)) {
    use <- magnitude >= bins[k] & magnitude < bins[k + 1]
    nBin[k] <- sum(use, na.rm = TRUE)
    magBin[k] <- mean(transform(magnitude[use]), na.rm = TRUE)
    
    if (nBin[k] > minBin) {
      ## && sum(!is.na(change[use])) > 50) {
      errBin[k] <- stats::sd(indErr[use], na.rm = TRUE)
      biasBin[k] <- mean(indErr[use], na.rm = TRUE)
      print(paste(length(magnitude[use]), sum(!is.na(change[use])), 
                  magBin[k], errBin[k]))
    } else {
      if (nBin[k] == 0) {
        magBin[k] <- NA
      }
      errBin[k] <- NA
      biasBin[k] <- NA
      print(paste(length(magnitude[use]), sum(!is.na(change[use]))))
    }
  }
  
  ## separate fluxes into positive, negative, and zero bins
  zero <- diff(sign(bins)) > 0
  pos <- magBin > 0 & !zero
  neg <- magBin < 0 & !zero
  
  ## subtract off zero bin, fit regression to positive and negative components
  ## would be better to fit a two line model with a common intercept, but this
  ## is quicker to implement for the time being
  E2 <- errBin - errBin[zero]
  E2 <- errBin - errBin[zero]
  intercept <- errBin[zero]
  
  return.list <- list(mag = magBin, 
                      err = errBin, 
                      bias = biasBin, 
                      n = nBin,
                      intercept = intercept)
  
  if(!all(is.na(E2[pos]))){
    mp <- stats::lm(E2[pos] ~ magBin[pos] - 1)
    return.list$slopeP <- mp$coefficients[1]
  } 
  if(!all(is.na(E2[neg]))){
    mn <- stats::lm(E2[neg] ~ magBin[neg] - 1)
    return.list$slopeN <- mn$coefficients[1]
  }else{
    return.list$slopeN <- mp$coefficients[1]
  }
  
  return(return.list)
} # flux.uncertainty

predict.flux.uncertainty <- function(magnitude,return.list){
  fu = rep(return.list$intercept,length=length(magnitude))
  pos = which(magnitude > 0)
  neg = which(magnitude < 0)
  fu[pos] = fu[pos] + return.list$slopeP*magnitude[pos]
  fu[neg] = fu[neg] + return.list$slopeN*magnitude[neg]
  return(fu)
}

#--------------------------------------------------------------------------------------------------#
##' Plot fit for heteroskedastic flux uncertainty
##' 
##' @name plot_flux_uncertainty
##' @title Plot fit for heteroskedastic flux uncertainty
##' @param f  output of flux.uncertainty functions
##' @param ...  optional graphical paramters
##' @export
##' @author Mike Dietze, Carl Davidson
plot_flux_uncertainty <- function(f, ...) {
  graphics::plot(f$mag, f$err, ...)
  big <- 10000
  graphics::lines(c(0, big), c(f$intercept, f$slopeP * big))
  graphics::lines(c(0, -big), c(f$intercept, -f$slopeN * big))
  graphics::legend("bottomleft", legend = c("intercept", f$intercept,
                                            "slopeP", f$slopeP, 
                                            "slopeN", f$slopeN))
} # plot_flux_uncertainty

