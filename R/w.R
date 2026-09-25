#' compute_w
#'
#' Computes the distribution of the transition to the first preclinical state
#' 
#' @param tmin Integer. Minimum age for developing preclinical cancer.
#' @param tmax Integer. Maximum age for developing preclinical cancer.
#' @param qs Function giving the conditional density of clinical age given age
#'   at entry into the first preclinical state. It must accept absolute clinical
#'   age as its first argument and preclinical-onset age as its second argument.
#' @param p Numerical vector of penetrances.
#' @return A list with components \code{ages} and \code{w}, giving the monthly 
#' age grid and the corresponding probabilities of transition to the first 
#' preclinical state.
compute_w <- function(tmin, tmax, qs, p) {
  ages <- seq(tmin, tmax, by = 1)
  sizew <- tmax - tmin + 1
  H <- convmat(qs, sizew, tmin, tmax)
  
  # Try solve first
  w_yearly <- solve(H, p)
  
  # If any negative values, use nnls instead
  if (any(w_yearly < 0)) {
    if (!requireNamespace("nnls", quietly = TRUE)) {
      stop("Package 'nnls' is required when negative values occur. Please install it.")
    }
    w_yearly <- nnls::nnls(H, p)$x
  }
  
  w <- rep(w_yearly / 12, each = 12)
  return( list(
    w = w,
    ages = rep(ages, each = 12) + sequence(rep(12, tmax)) / 12 - 1
  )
  )
}

#' Computes the convolution matrix for the sojourn time distribution.
#' 
#' @param qs Function giving the conditional density of clinical age given age
#'   at entry into the first preclinical state. It must accept absolute clinical
#'   age as its first argument and preclinical-onset age as its second argument.
#' @param sizew Integer. Size of the convolution matrix.
#' @param tmin Integer. Minimum age for developing preclinical cancer.
#' @param tmax Integer. Maximum age for developing preclinical cancer.
#' 
#' @return Convolution matrix
convmat <- function(qs, sizew, tmin, tmax) {
  mat <- matrix(nrow = 0, ncol = sizew)
  nrows = tmax - tmin + 1
  for (i in 1:nrows) {
    row <- rep(0, sizew)
    currt <- tmin + i - 1
    values <- c()
    for (u in tmin:currt) {
      values <- c(values, qs(currt, u))
    }
    row[1:i] <- values
    mat <- rbind(mat, row)
  }
  return(mat)
}
