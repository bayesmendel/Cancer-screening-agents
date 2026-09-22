#' natural_history_simulation_two_test
#'
#' Simulate ages at entry into two sequential preclinical states and age at
#' clinical detection (Sc) for a cohort under a monotonic detectability
#' natural history model based on two screening tests, using either (i) Fam3PRO 
#' penetrances or (ii) a user-supplied penetrance vector, and exponential
#' duration kernels parameterized by \code{MST1} and \code{MST2}.
#'
#'
#' The model is S0 -> Sp1 -> Sp2 -> Sc:
#' \itemize{
#'   \item S0: healthy state,
#'   \item Sp1: earlier preclinical (cancer detectable by test 1 but not by test 2).
#'   \item Sp2: later preclinical (cancer detectable by both tests).
#'   \item Sc: clinical, symptomatic state.
#' }
#'
#'
#' @param cancer Character. Cancer site name used in \code{Fam3PRODatabase}.
#' @param gene Character. Gene name used in \code{Fam3PRODatabase}.
#' @param sex Character. Sex (e.g., \code{"Female"} or \code{"Male"}).
#' @param MST1 Numeric or object. Mean sojourn time specification for the total
#'   \code{Sp1 -> Sc} duration. Must be compatible with
#'   \code{q_exp_generic()} and \code{q_density()}.
#' @param MST2 Numeric or object. Mean sojourn time specification for the
#'   \code{Sp2 -> Sc} proposal kernel. Must be compatible with
#'   \code{q_exp_generic()} and \code{q_density()}.
#' @param nsamples Integer. Number of individuals to simulate. Default is 100000.
#' @param verbose Logical. If \code{TRUE}, print summary statistics of the
#' simulated transition ages. Default is \code{TRUE}.
#' @param seed Integer scalar or \code{NULL}. Optional random seed.
#' @param penetrance NULL or numeric vector. If provided, this per-age penetrance
#'   vector (indexed by age in years, starting at 1) is used instead of
#'   \code{Fam3PRODatabase}. Values are interpreted as age-specific probabilities
#'   of reaching the clinical state at each age (not cumulative risk).
#' @param race Character. Race label used to index \code{Fam3PRODatabase} when
#'   \code{penetrance} is \code{NULL}. Default is \code{"All_Races"}.
#'
#' @return A list with components:
#' \describe{
#'   \item{cancer, gene, sex, race}{Input labels retained for traceability.}
#'   \item{tmin, tmax}{Minimum and maximum ages (in years) implied by the penetrance vector.}
#'   \item{age1}{Numeric vector of ages at entry into \code{Sp1}.}
#'   \item{age2_1}{Numeric vector of ages at entry into \code{Sp2}.}
#'   \item{age2_2}{Numeric vector of ages at entry into \code{Sc}.}
#' }
#'
#' @details
#' Transition ages that would occur after \code{tmax} are set to \code{NA}
#' (i.e., \code{age2_1} is set to \code{NA} if \code{t0 + t12 > tmax}, and
#' \code{age2_2} is set to \code{NA} if \code{t0 + t12 + t2 > tmax}).
#' This function assumes monotonic progression through the latent states. The
#' total \code{Sp1 -> Sc} duration, \code{T1}, is sampled once from the
#' \code{MST1} kernel on a monthly grid and is held fixed. Candidate
#' \code{Sp2 -> Sc} durations, \code{T2}, are sampled on a half-month grid,
#' restricted to \code{0 < T2 < T1}, and accepted using the age-dependent
#' density ratio evaluated at the implied \code{Sp2} entrance age. The
#' intermediate duration is then \code{T12 = T1 - T2}.
#'
#' Consequently, \code{T12 + T2 = T1} for every latent history, while the
#' monotonicity restriction and age adjustment modify the unconditional
#' \code{MST2} proposal distribution. Administrative censoring is applied only
#' after the complete latent transition ages have been generated.
#' 
#' @export
natural_history_simulation_two_test <- function(cancer, gene, sex, MST1, MST2, 
                                                nsamples = 100000, verbose = TRUE, 
                                                penetrance = NULL, 
                                                race = "All_Races", seed = NULL) {
  if (!is.null(penetrance)) {
    if (!is.numeric(penetrance) || length(penetrance) < 2 || any(!is.finite(penetrance))) {
      stop("'penetrance' must be a finite numeric vector of length >= 2.")
    }
    if (any(penetrance < 0)) {
      stop("'penetrance' must be non-negative.")
    }
    if (any(penetrance > 1)) {
      stop("'penetrance' values must not exceed 1")
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
  if (!is.null(seed)) {
    if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) ||
        seed < 0 || seed > .Machine$integer.max || seed != floor(seed)) {
      stop("seed must be NULL or one non-negative integer-valued number.")
    }
    set.seed(as.integer(seed))
  }
  tmin <- 1
  tmax <- length(p)
  # q_s1 represented on two equivalent scales:
  # qs1 is the conditional density of clinical age, used for deconvolution
  # qs1_density is the conditional density of duration T1, used for sampling
  qs1 <- function(t, u) q_exp_generic(t, u, MST1)
  qs1_density <- function(t, u) q_density(t, u, MST1)
  # MST2-parameterized duration-density kernel. It is evaluated at the
  # Sp1-entry age to generate T2 proposals and at the implied Sp2-entry
  # age in the rejection step. The accepted T2 values, subject to
  # 0 < T2 < T1, induce the simulated q_s2 distribution.
  qs2_density <- function(t, u) q_density(t, u, MST2)
  # Age at onset distribution
  wdist <- compute_w(tmin, tmax, qs1, p)
  ages <- wdist$ages
  w <- wdist$w
  
  # Total Sp1 -> Sc durations are represented on a monthly grid. Candidate
  # Sp2 -> Sc durations use a half-month grid so that even a one-month total
  # duration can be split into two strictly positive transition times.
  stimes1 <- seq_len(40 * 12) / 12
  stimes2 <- seq_len(40 * 24 - 1) / 24
  
  # Transition S0 -> Sp1
  t0 <- sample(ages, nsamples, prob = w, replace = TRUE)
  
  # Latent transition durations
  t1 <- numeric(nsamples)
  t12 <- numeric(nsamples)
  t2 <- numeric(nsamples)

  # Rejection sampling
  # Compute a global upper bound for the age-adjustment ratio. Candidate T2
  # values and the induced Sp1 -> Sp2 durations T12 both lie on the half-month
  # grid. Enumerating possible T12 shifts and reducing them to distinct pairs of
  # starting and shifted means avoids repeatedly evaluating the same age-band
  # combinations.
  onset_ages <- unique(ages)
  mst2_at_onset <- 1 / qs2_density(0, u = onset_ages)
  shifted_ages <- as.vector(outer(onset_ages, stimes2, "+"))
  mst2_at_shifted_age <- 1 / qs2_density(0, u = shifted_ages)

  mst2_pairs <- unique(cbind(
    onset = rep(mst2_at_onset, times = length(stimes2)),
    shifted = mst2_at_shifted_age
  ))
  if (any(!is.finite(mst2_pairs)) || any(mst2_pairs <= 0)) {
    stop("'MST2' must define positive, finite mean sojourn times over the simulated age range.")
  }

  pair_maxima <- apply(mst2_pairs, 1, function(mst_pair) {
    log_ratio <- log(mst_pair[[1]] / mst_pair[[2]]) +
      stimes2 * (1 / mst_pair[[1]] - 1 / mst_pair[[2]])
    exp(max(log_ratio))
  })
  max_ratio <- max(pair_maxima)
  if (!is.finite(max_ratio) || max_ratio <= 0) stop("Invalid max_ratio in rejection sampler.")

  for (i in seq_len(nsamples)) {
    # Draw the total Sp1 -> Sc duration once. Rejected T2 proposals must not
    # alter this draw, because t12 + t2 is required to remain equal to t1.
    t1_index <- sample.int(
      length(stimes1),
      1L,
      prob = qs1_density(stimes1, u = t0[i]),
      replace = TRUE
    )
    t1[i] <- stimes1[t1_index]

    # A monthly t1 occupies an even number of half-month steps, so these are
    # exactly the positive half-month t2 values strictly smaller than t1.
    eligible <- seq_len(2L * t1_index - 1L)
    q2_proposal_weights <- qs2_density(stimes2, u = t0[i])

    repeat {
      eligible_position <- sample.int(
        length(eligible),
        1L,
        prob = q2_proposal_weights[eligible],
        replace = TRUE
      )
      tmp2_index <- eligible[eligible_position]
      tmp2_star <- stimes2[tmp2_index]

      implied_sp2_age <- t0[i] + t1[i] - tmp2_star
      num <- qs2_density(tmp2_star, u = implied_sp2_age)
      denom <- q2_proposal_weights[tmp2_index]
      ratio <- num / denom

      if (!is.finite(ratio) || ratio < 0) {
        stop("Invalid density ratio in rejection sampler.")
      }
      if (ratio > max_ratio * (1 + 1e-12)) {
        stop("The rejection-sampling bound is smaller than an evaluated density ratio.")
      }

      if (runif(1) < min(1, ratio / max_ratio)) {
        t2[i] <- tmp2_star
        t12[i] <- t1[i] - t2[i]
        break
      }
    }
  }

  duration_tolerance <- 1e-12
  if (any(t12 <= 0) || any(t2 <= 0) ||
      any(abs(t12 + t2 - t1) > duration_tolerance)) {
    stop("Internal error: simulated transition durations violate the fixed-T1 ordering constraint.")
  }

  # Generate the complete latent history first, then censor each transition at
  # the penetrance horizon. The clinical age is anchored directly to t1.
  raw_age2_1 <- t0 + t12
  raw_age2_2 <- t0 + t1

  age1 <- t0 # Sp1 starts
  age2_1 <- ifelse(raw_age2_1 <= tmax, raw_age2_1, NA_real_) # Sp2 starts
  age2_2 <- ifelse(raw_age2_2 <= tmax, raw_age2_2, NA_real_) # Sc starts
  
  if (verbose) {
    print('#########################')
    print('Transition to Sp1 summary')
    print(summary(age1))
    
    print('#########################')
    print('Transition to Sp2 summary')
    print(summary(age2_1))
    
    print('#########################')
    print('Transition to Sc summary')
    print(summary(age2_2))
  }
  
  return(list(
    cancer = cancer,
    gene = gene,
    sex = sex,
    race = race,
    tmin = tmin,
    tmax = tmax,
    age1 = age1, 
    age2_1 = age2_1,
    age2_2 = age2_2
  ))
}
