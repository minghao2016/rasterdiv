mpaRaoP <- function(x,alpha,w,dist_m,na.tolerance,rescale,lambda,diag,debugging,isfloat,mfactor,np) {
    # Some initial housekeeping
    message("\n\nProcessing alpha: ",alpha, " Moving Window: ", 2*w+1)
    mfactor <- ifelse(isfloat,mfactor,1) 
    window = 2*w+1
    diagonal <- ifelse(diag==TRUE,0,NA)
    rasterm <- x[[1]]
    # Set a progress bar
    pb <- txtProgressBar(title = "Iterative training", min = w, max = dim(rasterm)[2]+w, style = 3)
    # Check if there are NAs in the matrices
    if ( is(x[[1]],"RasterLayer") ){
        if(any(sapply(lapply(unlist(x),length),is.na)==TRUE))
            message("\n Warning: One or more RasterLayers contain NA's which will be treated as 0")
    } else if ( is(x[[1]],"matrix") ){
        if(any(sapply(x, is.na)==TRUE) ) {
            message("\n Warning: One or more matrices contain NA's which will be treated as 0")
        }
    }
    # Check whether the chosen distance metric is valid or not
    if( dist_m=="euclidean" | dist_m=="manhattan" | dist_m=="canberra" | dist_m=="minkowski" | dist_m=="mahalanobis" ) {
        ## Decide what function to use
        if( dist_m=="euclidean" ) {
            distancef <- get("multieuclidean")
        } else if( dist_m=="manhattan" ) {
            distancef <- get("multimanhattan")
        } else if( dist_m=="canberra" ) {
            distancef <- get("multicanberra")
        } else if( dist_m=="minkowski" ) {
            if( lambda==0 ) {
                stop("The Minkowski distance for lambda = 0 is infinity; please choose another value for lambda.")
            } else {
                distancef <- get("multiminkowski") 
            }
        } else if( dist_m=="mahalanobis" ) {
            distancef <- get("multimahalanobis")
            warning("Multimahalanobis distance is not fully supported...")
        }
    } else {
        stop("Distance function not defined for multidimensional Rao's Q; please choose among euclidean, manhattan, canberra, minkowski, mahalanobis...")
    }
    if(debugging) {
        message("#check: After distance calculation in multimenional clause.")
        print(distancef)
    }
    # Rescale and add additional columns and rows for moving w
    hor <-matrix(NA,ncol=dim(x[[1]])[2],nrow=w)
    ver <- matrix(NA,ncol=w,nrow=dim(x[[1]])[1]+w*2)
    if(rescale) {
        trastersm <- lapply(x, function(x) {
            t1 <- raster::scale(raster(cbind(ver,rbind(hor,x,hor),ver)))
            t2 <- raster::as.matrix(t1)
            return(t2)
        })
    } else {
        trastersm <- lapply(x, function(x) {
            cbind(ver,rbind(hor,x,hor),ver)
        })
    }
    if(debugging) {
        message("#check: After rescaling in multimensional clause.")
        print(distancef)
    }
    # Loop over all the pixels in the matrices
    if( (ncol(x[[1]])*nrow(x[[1]]))>10000 ) {
        message("\n Warning: ",ncol(x[[1]])*nrow(x[[1]])*length(x), " cells to be processed, it may take some time... \n")
    }
    # Parallelised parametric multidimensional Rao
    out <- foreach(cl=(1+w):(dim(rasterm)[2]+w),.verbose = F) %dopar% {
        # Update progress bar
        setTxtProgressBar(pb, cl)
        # Row loop
        mpaRaoOP <- sapply((1+w):(dim(rasterm)[1]+w), function(rw) {
            if( length(!which(!trastersm[[1]][c(rw-w):c(rw+w),c(cl-w):c(cl+w)]%in%NA)) <= (window^2-((window^2)*na.tolerance)) ) {
                raoqe <- NA
                return(raoqe)
            } else {
                tw <- lapply(trastersm, function(x) { 
                    x[(rw-w):(rw+w),(cl-w):(cl+w)]
                })
                # Vectorize the matrices in the list and calculate between matrices pairwase distances
                lv <- lapply(tw, function(x) {as.vector(t(x))})
                vcomb <- combn(length(lv[[1]]),2)
                vout <- sapply(1:ncol(vcomb), function(p) {
                    lpair <- lapply(lv, function(chi) {
                        c(chi[vcomb[1,p]],chi[vcomb[2,p]])
                    })
                    return(distancef(lpair)/mfactor)
                })
                vv <- (sum(rep(vout^alpha,2) * (1/(window)^4),na.rm=TRUE) ^ (1/alpha)) 
                return(vv)
            }
        })
        return(mpaRaoOP)
    }
    return(do.call(cbind,out))
}

# Supporting distance function
# euclidean
multieuclidean <- function(x) {
    tmp <- lapply(x, function(y) {
        (y[[1]]-y[[2]])^2
    })
    return(sqrt(Reduce(`+`,tmp)))
}
# manhattan
multimanhattan <- function(x) {
    tmp <- lapply(x, function(y) {
        abs(y[[1]]-y[[2]])
    })
    return(Reduce(`+`,tmp))
}
# canberra
multicanberra <- function(x) {
    tmp <- lapply(x, function(y) {
        abs(y[[1]] - y[[2]]) / (abs(y[[1]]) + abs(y[[2]]))
    })
    return(Reduce(`+`,tmp))
}
# minkowski
multiminkowski <- function(x) {
    tmp <- lapply(x, function(y) {
        abs((y[[1]]-y[[2]])^lambda)
    })
    return(Reduce(`+`,tmp)^(1/lambda))
}
# mahalanobis
multimahalanobis <- function(x){
    tmp <- matrix(unlist(lapply(x,function(y) as.vector(y))),ncol=2)
    tmp <- tmp[!is.na(tmp[,1]),] 
    if( length(tmp)==0 | is.null(dim(tmp)) ) {
        return(NA)
    } else if(rcond(cov(tmp)) <= 0.001) {
        return(NA)
    } else {
                # return the inverse of the covariance matrix of tmp; aka the precision matrix
        inverse<-solve(cov(tmp)) 
        if(debugging){
            print(inverse)
        }
        tmp<-scale(tmp,center=T,scale=F)
        tmp<-as.numeric(t(tmp[1,])%*%inverse%*%tmp[1,])
        return(sqrt(tmp))
    }
}