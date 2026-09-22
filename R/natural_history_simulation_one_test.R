#' natural_history_simulation_one_test
#'
#' Simulate ages at entry into the preclinical state (Sp) and ages at clinical
#' detection (Sc) for a cohort, using either (i) Fam3PRO penetrances or (ii) a
#' user-supplied penetrance vector, and an exponential sojourn time with mean
#' \code{MST}.
#'
#' The model is S0 -> Sp -> Sc:
#' \itemize{
#'   \item S0: healthy state,
#'   \item Sp: preclinical, screen-detectable state,
#'   \item Sc: clinical, symptomatic state.
#' }
#'
#'
#' @param cancer Character. Cancer site name used in \code{Fam3PRODatabase}.
#' @param gene Character. Gene name (or \code{"SEER"}) used in \code{Fam3PRODatabase}
#' @param sex Character. Sex (e.g., \code{"Female"} or \code{"Male"}).
#' @param MST Numeric or object. Mean sojourn time for the preclinical state Sp (in
#' years). Must be compatible with \code{q_exp_generic()} and \code{q_density()}.
#' @param nsamples Integer. Number of individuals to simulate. Default is 100000.
#' @param verbose Logical. If \code{TRUE}, print summary statistics of the 
#' simulated transition ages. Default is \code{TRUE}.
#' @param penetrance NULL or numeric vector. If provided, this per-age penetrance
#'   vector (indexed by age in years, starting at 1) is used instead of
#'   \code{Fam3PRODatabase}. Values are interpreted as age-specific probabilities
#'   of reaching the clinical state at each age (not cumulative risk).
#' @param race Character. Race label used to index \code{Fam3PRODatabase} when
#'   \code{penetrance} is \code{NULL}. Default is \code{"All_Races"}.
#'
#' @return A list with components:
#' \describe{
#'   \item{cancer, gene, sex, race}{Input labels retained for traceability}
#'   \item{tmin, tmax}{Minimum and maximum ages (in years) implied by the
#'         penetrance vector.}
#'   \item{age1}{Numeric vector of ages at entry into Sp (preclinical state).}
#'   \item{age2}{Numeric vector of ages at clinical detection Sc; values
#'         beyond \code{tmax} are set to \code{NA}.}
#' }
#' 
#' @details
#' Ages at clinical detection beyond \code{tmax} (the maximum age in the
#' penetrance table) are set to \code{NA}. Ages at preclinical onset
#' (\code{age1}) are still returned for these individuals.
#' 
#' @export
natural_history_simulation_one_test <- function(cancer, gene, sex, MST,
                                       nsamples = 100000, verbose = TRUE,
                                       penetrance = NULL, race = "All_Races") {
  if (!is.null(penetrance)) {
    if (!is.numeric(penetrance) || length(penetrance) < 2 || any(!is.finite(penetrance))) {
      stop("'penetrance' must be a finite numeric vector of length >= 2.")
    }
    if (any(penetrance < 0)) {
      stop("'penetrance' must be non-negative.")
    }
    if (any(penetrance > 1)) {
      warning(
        "Some 'penetrance' values exceed 1. Expected per-age probabilities in [0,1]. ",
        "Continuing anyway."
      )
    }
    p <- penetrance
  } else {
    if (!exists("Fam3PRODatabase", inherits = TRUE)) {
      stop(
        "Fam3PRODatabase not found. Either load the Fam3PRO data into the session, ",
        "or supply a user penetrance vector via 'penetrance = ...'."
      )
    }
    p <- Fam3PRODatabase$Penetrance[cancer, gene, race, sex, , "Net"]
  }

  tmin <- 1
  tmax <- length(p)

  # Sojourn time distribution
  qs <- function(t, u) q_exp_generic(t, u, MST)

  # Age at onset distribution implied by penetrance + sojourn model
  wdist <- compute_w(tmin, tmax, qs, p)
  ages <- wdist$ages
  w <- wdist$w

  # Sojourn times (years), discretized monthly up to 40 years
  stimes <- seq(1/12, 40, 1/12)

  # Transition S0 -> Sp
  t0 <- sample(ages, nsamples, prob = w, replace = TRUE)
  
  # Transition Sp -> Sc
  t1 <- numeric(nsamples)
  for (i in 1:nsamples) {
    t1[i] <- sample(stimes, 1, prob = q_density(stimes, u = t0[i], MST), replace = TRUE)
  }
  
  age1 <- t0
  age2 <- t0 + t1
  age2[age2 > tmax] <- NA
  
  if (verbose) {
    print('#########################')
    print('Transition to Sp summary')
    print(summary(age1))
    
    print('#########################')
    print('Transition to Sc summary')
    print(summary(age2))
  }
  
  return(list(
    cancer = cancer,
    gene = gene,
    sex = sex,
    race = race,
    tmin = tmin,
    tmax = tmax,
    age1 = age1, 
    age2 = age2
  ))
}
