#' lead_time_one_test
#'
#' Simulate true-positive and false-positive screening results and compute lead
#' time under a fixed-interval screening schedule for a cohort with simulated
#' natural history.
#'
#' For each individual with a clinical diagnosis age \code{age2} (non-missing),
#' the function simulates screening exams at ages
#' \code{age_min, age_min + Delta_t, ..., age_max}. If a screening occurs during
#' the preclinical window \code{[age1, age2)}, a true positive occurs with
#' probability \code{sensitivity}. The earliest screening time that yields a
#' true positive is recorded as \code{first_true_positive}. Lead time is then
#' computed as \code{age2 - first_true_positive}. If no true positive occurs
#' before \code{age2}, the individual is classified as an interval case and
#' lead time is set to 0.
#'
#' At screening ages before \code{age1}, a positive result occurs with
#' probability one minus \code{specificity} and is counted as a false positive.
#' False-positive results do not interrupt screening. Repeated outcomes are
#' modeled as conditionally independent Bernoulli draws.
#'
#' Individuals whose \code{age2} is \code{NA} (i.e., no clinical cancer within
#' the penetrance age limit used to generate the natural history) have
#' \code{lead_time = NA} and \code{first_true_positive = NA}. Their false-positive
#' outcomes are nevertheless simulated at screening ages strictly before
#' \code{age1}.
#'
#' @param natural_history List. Output of
#'   \code{natural_history_simulation_one_test()}.
#'   Must contain numeric vectors \code{age1} (preclinical onset; nonmissing for
#'   every history) and \code{age2} (clinical diagnosis), and metadata fields
#'   \code{cancer}, \code{gene}, \code{sex}, \code{race}, and \code{tmax}.
#' @param Delta_t Numeric. Screening interval (in years). For example,
#'   \code{Delta_t = 1} corresponds to annual screening.
#' @param sensitivity Numeric in [0,1]. Probability a screening exam returns
#'   positive for an individual who is in the preclinical state at the time of
#'   screening.
#' @param specificity Numeric in [0,1]. Probability a screening exam returns
#'   negative before entry into the preclinical state. Genuine false positives
#'   are counted but do not interrupt screening.
#' @param age_min Numeric. Minimum screening age (in years).
#' @param age_max Numeric. Maximum screening age (in years).
#' @param seed Integer or NULL. Random seed for reproducibility. Default is \code{NULL}.
#' @param verbose Logical scalar. If \code{TRUE}, print the numbers of simulated
#'   histories, histories with a known clinical age, true screening detections,
#'   and interval cases; the false-positive total; and summaries of lead time,
#'   administrations before detection, and per-history false-positive counts.
#'   Default is \code{TRUE}.
#'
#' @return A list containing per-history vectors that preserve the ordering and
#'   length of the input histories, together with aggregate counts, the screening
#'   schedule, retained inputs, and metadata:
#' \describe{
#'   \item{cancer, gene, sex, race, tmax}{Metadata copied from
#'     \code{natural_history}.}
#'   \item{first_true_positive}{Numeric vector (length \code{nsamples}) giving the
#'     age at the first true-positive screening exam; \code{NA} for interval cases
#'     and histories without a known clinical age.}
#'   \item{n_test_before_true_positive}{Number of test administrations strictly
#'     before the true-positive screening age. The detecting-age screening event
#'     is not counted. Values are \code{NA} for interval cases and histories
#'     without a known clinical age.}
#'   \item{n_false_positives}{Per-history numbers of false-positive results. A
#'     positive result is a false positive only when it occurs before \code{age1}.
#'     These counts are returned for every simulated history, including histories
#'     with an unknown clinical age.}
#'   \item{total_false_positives}{Aggregate number of false-positive test results
#'     across all simulated histories. This counts test results, not individuals.}
#'   \item{age_at_detection}{Screening detection age for screen-detected cases,
#'     clinical age for interval cases, and \code{NA} when \code{age2} is
#'     \code{NA}.}
#'   \item{screen_detected, interval_case}{Logical vectors; entries are
#'     \code{NA} when \code{age2} is \code{NA}.}
#'   \item{lead_time}{Numeric vector (length \code{nsamples}). For clinical cases,
#'     lead time is \code{age2 - age_at_detection}; it is zero for interval cases
#'     and \code{NA} for histories without a known clinical age.}
#'   \item{n_true_detections, n_interval_cases}{Aggregate numbers of
#'     screen-detected and interval-case histories among histories with a known
#'     clinical age.}
#'   \item{schedule}{Numeric vector containing the scheduled screening ages.}
#'   \item{sensitivity, specificity}{Test-performance inputs retained for
#'     traceability.}
#'   \item{age_min, age_max, Delta_t}{Screening-schedule inputs retained for
#'     traceability.}
#' }
#'
#' @details
#' This function implements a minimal lead-time simulation:
#' \itemize{
#'   \item Screening is performed at fixed ages determined by \code{Delta_t}.
#'   \item True positives can only occur during the preclinical window
#'     \code{[age1, age2)}.
#'   \item False positives can only occur before \code{age1}; they are counted
#'     but do not alter the screening schedule or the lead-time endpoint.
#' }
#'
#' For histories with an unknown clinical age, false-positive outcomes are
#' simulated at every scheduled screening age strictly before \code{age1}. No
#' later positive can be a false positive under this model, so \code{age2} is not
#' needed for these counts.
#'
#' @examples
#' \dontrun{
#' nh <- natural_history_simulation_one_test(cancer = "Colorectal", gene = "SEER",
#'                                 sex = "Male", MST = 5, nsamples = 5000)
#' lt <- lead_time_one_test(natural_history = nh, Delta_t = 1,
#'                 sensitivity = 0.75, specificity = 0.90,
#'                 age_min = 40, age_max = 70)
#' summary(lt$lead_time)
#' }
#' 
#' @export
lead_time_one_test <- function(natural_history, Delta_t, sensitivity, specificity,
                               age_min, age_max, seed = NULL, verbose = TRUE) {
  
  if (!is.null(seed)) {
    set.seed(seed)
  }
  
  if (!is.numeric(Delta_t) || length(Delta_t) != 1 || is.na(Delta_t) || Delta_t <= 0) {
    stop("Delta_t must be a single positive number")
  }
  if (!is.numeric(sensitivity) || length(sensitivity) != 1 ||
      !is.finite(sensitivity) || sensitivity < 0 || sensitivity > 1) {
    stop("Sensitivity must be a single number in [0,1]")
  }
  if (!is.numeric(specificity) || length(specificity) != 1 ||
      !is.finite(specificity) || specificity < 0 || specificity > 1) {
    stop("Specificity must be a single number in [0,1]")
  }
  if (age_min > age_max) {
    stop("Age_min must be less than or equal to age_max")
  }

  draw_positive <- function(probability) {
    if (probability == 0) return(FALSE)
    if (probability == 1) return(TRUE)
    stats::runif(1L) < probability
  }

  draw_false_positive <- function(specificity) {
    draw_positive(1 - specificity)
  }
  
  nsamples <- length(natural_history$age1)
  first_true_positive <- rep(NA_real_, nsamples)
  n_test_before_true_positive <- rep(NA_integer_, nsamples)
  n_false_positives <- rep(NA_integer_, nsamples)
  
  # Scheduled screenings
  screenings <- seq(age_min, age_max, by = Delta_t)

  # Maximum age inferred from natural history
  tmax <- natural_history$tmax

  age1 <- natural_history$age1
  age2 <- natural_history$age2
  if (anyNA(age1)) {
    stop("age1 must be nonmissing for every history.")
  }
  known_clinical_age <- !is.na(age2)
  ordering_tolerance <- 1e-10

  for (i in which(known_clinical_age)) {
    # Transition ages for individual i
    age1_i <- age1[i]
    age2_i <- age2[i]

    n_test_so_far <- 0L
    n_false_positives[i] <- 0L

    for (j in seq_along(screenings)) {
      t <- screenings[j]

      # age2 is the clinical diagnosis age, not a screening opportunity.
      if (t >= age2_i - ordering_tolerance) {
        break
      }

      if (t < age1_i - ordering_tolerance) {
        # Before preclinical onset, positive results are false positives and do
        # not stop screening.
        if (draw_false_positive(specificity)) {
          n_false_positives[i] <- n_false_positives[i] + 1L
        }
      } else { # Preclinical state, early detection possible
        if (draw_positive(sensitivity)) {
          first_true_positive[i] <- t
          n_test_before_true_positive[i] <- n_test_so_far
          break
        }
      }

      n_test_so_far <- n_test_so_far + 1L
    }
  }

  # Clinical age is not required to count false positives. Complete these
  # counts after the main loop so that draws for histories with a known
  # clinical age occur first, matching the two-test implementation.
  for (i in which(!known_clinical_age)) {
    n_false_positives[i] <- 0L

    for (t in screenings) {
      # At and after preclinical onset, a positive result is not a false positive.
      if (t >= age1[i] - ordering_tolerance) {
        break
      }

      if (draw_false_positive(specificity)) {
        n_false_positives[i] <- n_false_positives[i] + 1L
      }
    }
  }

  total_false_positives <- sum(n_false_positives, na.rm = TRUE)

  screen_detected <- rep(NA, nsamples)
  screen_detected[known_clinical_age] <-
    !is.na(first_true_positive[known_clinical_age])
  interval_case <- rep(NA, nsamples)
  interval_case[known_clinical_age] <- !screen_detected[known_clinical_age]

  age_at_detection <- rep(NA_real_, nsamples)
  age_at_detection[known_clinical_age] <-
    natural_history$age2[known_clinical_age]
  age_at_detection[known_clinical_age & screen_detected] <-
    first_true_positive[known_clinical_age & screen_detected]

  lead_time <- rep(NA_real_, nsamples)
  lead_time[known_clinical_age] <-
    natural_history$age2[known_clinical_age] -
      age_at_detection[known_clinical_age]

  n_true_detections <- sum(screen_detected, na.rm = TRUE)
  n_interval_cases <- sum(interval_case, na.rm = TRUE)
  
  if (verbose) {
    message("Number of samples: ", nsamples)
    message("Number with known clinical age: ", sum(known_clinical_age))
    message("Number of true screening detections: ", n_true_detections)
    message("Number of interval cases: ", n_interval_cases)
    message("Total number of false-positive results: ", total_false_positives)
    message("Lead time among true screening detections:")
    print(summary(lead_time[screen_detected %in% TRUE]))
    message("Lead time among all histories with known clinical age:")
    print(summary(lead_time[known_clinical_age]))
    message("Number of test administrations before true-positive detection:")
    print(summary(n_test_before_true_positive[screen_detected %in% TRUE]))
    message("Number of false positives across all samples:")
    print(summary(n_false_positives))
  }

  list(
    cancer = natural_history$cancer,
    gene = natural_history$gene,
    sex = natural_history$sex,
    race = natural_history$race,
    tmax = tmax,
    first_true_positive = first_true_positive,
    n_test_before_true_positive = n_test_before_true_positive,
    n_false_positives = n_false_positives,
    total_false_positives = total_false_positives,
    age_at_detection = age_at_detection,
    screen_detected = screen_detected,
    interval_case = interval_case,
    lead_time = lead_time,
    n_true_detections = n_true_detections,
    n_interval_cases = n_interval_cases,
    schedule = screenings,
    sensitivity = sensitivity,
    specificity = specificity,
    age_min = age_min,
    age_max = age_max,
    Delta_t = Delta_t
  )
}
