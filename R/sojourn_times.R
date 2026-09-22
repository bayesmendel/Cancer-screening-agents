#' Density of the time \code{t} of clinical detection given onset at \code{u},
#' assuming a piecewise exponential sojourn time distribution where the mean
#' sojourn time depends on \code{u} via \code{MSTime}.
#' Returns 0 for \code{t < u}.
#' 
#' @param t Numeric. Clinical detection time(s).
#' @param u Numeric. Onset time.
#' @param MSTime Either (i) a single numeric mean sojourn time, or (ii) a
#'   data frame with columns \code{age_band} and \code{value} (e.g. output of
#'   \code{parse_param_value()}) specifying age-band-specific mean sojourn times.
#'   Age bands should be strings like \code{"45–54"}, \code{"55-64"} or \code{"80+"}.
#'   Ages below the minimum band use the youngest band's MST; ages above the
#'   maximum band use the oldest band's MST.
#' @return Numeric vector. Probability density value(s).
q_exp_generic <- function(t, u, MSTime) {
  
  if (is.numeric(MSTime) && length(MSTime) == 1){
    MST <- MSTime
  } else {
    parse_lower_age <- function(band) {
      band <- trimws(as.character(band))
      band <- gsub("—", "–", band, fixed = TRUE)
      band <- gsub("-", "–", band, fixed = TRUE)
      m <- regexpr("[0-9]+", band)
      if (m[1] == -1) return(NA_real_)
      as.numeric(regmatches(band, m))
    }
    
    
    age_init <- vapply(MSTime$age_band, parse_lower_age, numeric(1))
    mst_values <- suppressWarnings(as.numeric(MSTime$value))
    
    
    keep <- is.finite(age_init) & !is.na(mst_values)
    if (!any(keep)) {
      stop(
        "Invalid MSTime: could not parse any usable age bands / MST values. ",
        "Expected age_band like '45–54', '80+', or '≥80' with numeric values."
      )
    }
    age_init <- age_init[keep]
    mst_values <- mst_values[keep]
    ord <- order(age_init)
    age_init <- age_init[ord]
    mst_values <- mst_values[ord]
    
    
    i <- findInterval(u, age_init)
    # if u < min(age_init) consider the MST for the youngest band
    i <- pmax(1, i)
    MST <- mst_values[i]
  }
  
  x <- t - u
  q <- (1 / MST) * exp(-(1 / MST) * x)
  q <- ifelse(t < u, 0, q)
  return(q)
}


#' Density of the sojourn time \code{s} in the preclinical state, given onset
#' at time \code{u}, assuming a piecewise exponential sojourn time distribution
#' with age-dependent mean sojourn times provided in \code{MSTime}.
#' Internally converts \code{s} to clinical detection time
#' \code{t = u + s} and evaluates the density via \code{q_exp_generic()}.
#'
#' @param s Numeric. Sojourn time(s) in the preclinical state.
#' @param u Numeric. Onset time.
#' @param MSTime Either (i) a single numeric mean sojourn time, or (ii) a
#'   data frame with columns \code{age_band} and \code{value} (e.g. output of
#'   \code{parse_param_value()}) specifying age-band-specific mean sojourn times.
#'   Age bands should be strings like \code{"45–54"}, \code{"55-64"} or \code{"80+"}.
#'   Ages below the minimum band use the youngest band's MST; ages above the
#'   maximum band use the oldest band's MST.
#'
#' @return Numeric vector. Probability density value.
q_density <- function(s, u, MSTime) {
  t <- u + s
  q_exp_generic(t, u, MSTime)
}
