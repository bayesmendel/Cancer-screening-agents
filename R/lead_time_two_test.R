#' lead_time_two_test
#'
#' Lead time under two screening schedules
#'
#' Simulate true-positive and false-positive screening results under a monotonic
#' two-test natural-history model and calculate an index-preserving lead-time
#' vector.
#'
#' Test 1 uses its sensitivity from entry into \code{Sp1} until clinical
#' symptoms. Test 2 uses one minus its specificity during \code{Sp1}; under the
#' model, a positive result in \code{Sp1} is classified as a true-positive
#' "lucky" detection because cancer is already present. From entry into
#' \code{Sp2}, Test 2 uses its sensitivity. Repeated outcomes are modeled as
#' conditionally independent Bernoulli draws.
#'
#' @param natural_history List containing equal-length numeric vectors
#'   \code{age1}, \code{age2_1}, and \code{age2_2}, representing ages at entry
#'   into \code{Sp1}, \code{Sp2}, and \code{Sc}, respectively. \code{age1}
#'   must be nonmissing for every history; later transition ages may be
#'   administratively censored and recorded as \code{NA}.
#' @param sensitivity1,sensitivity2 Numeric scalars in \code{[0, 1]}.
#'   Sensitivities of Tests 1 and 2 during their detectable preclinical states.
#' @param specificity1,specificity2 Numeric scalars in \code{[0, 1]}.
#'   Both specificities determine false-positive results in \code{S0}, before
#'   entry into \code{Sp1}. In addition, one minus \code{specificity2} is the
#'   probability of a true-positive Test 2 "lucky" detection during \code{Sp1}.
#'   Genuine false positives are counted but do not interrupt screening.
#' @param age_min1,age_min2 Numeric scalars. Starting ages for the Test 1 and
#'   Test 2 screening schedules.
#' @param age_max1,age_max2 Numeric scalars. Ending ages for the Test 1 and
#'   Test 2 screening schedules.
#' @param Delta_t1,Delta_t2 Positive numeric scalars. Fixed screening intervals
#'   in years for Tests 1 and 2.
#' @param seed Integer scalar or \code{NULL}. Optional random seed.
#' @param verbose Logical scalar. If \code{TRUE}, print the numbers of simulated
#'   histories, histories with a known clinical age, true screening detections,
#'   and interval cases; false-positive totals; and summaries of lead time,
#'   administrations before detection, and per-history false-positive counts.
#'
#' @return A list containing per-history vectors that preserve the ordering and
#'   length of the input histories, together with aggregate counts, screening
#'   schedules, retained inputs, and metadata:
#' \describe{
#'   \item{cancer, gene, sex, race, tmax}{Metadata copied from
#'     \code{natural_history}.}
#'   \item{first_true_positive1, first_true_positive2}{First successful screen
#'     for each test at the overall detection age; otherwise \code{NA}.}
#'   \item{first_true_positive}{Earliest true-positive screening age across the
#'     two tests; \code{NA} for interval cases and histories with unknown
#'     clinical age.}
#'   \item{n_test1_before_true_positive, n_test2_before_true_positive}{Number
#'     of Test 1 and Test 2 administrations strictly before the overall
#'     true-positive screening age. The detecting-age screening event is not
#'     counted. Values are \code{NA} for interval cases and histories with
#'     unknown clinical age.}
#'   \item{n_test1_false_positives, n_test2_false_positives}{Per-history numbers
#'     of false-positive Test 1 and Test 2 results. A positive result is false
#'     positive for either test only when it occurs in \code{S0}, before entry
#'     into \code{Sp1}. These counts are returned for every simulated history,
#'     including histories with an unknown clinical age.}
#'   \item{n_false_positives}{Per-history sum of the Test 1 and Test 2
#'     false-positive results.}
#'   \item{total_test1_false_positives, total_test2_false_positives,
#'     total_false_positives}{Aggregate numbers of false-positive test results
#'     across all simulated histories. These count test results, not
#'     individuals.}
#'   \item{age_at_detection}{Screening detection age for screen-detected cases,
#'     clinical age for interval cases, and \code{NA} when \code{age2_2} is
#'     \code{NA}.}
#'   \item{detected_by}{\code{"test1"}, \code{"test2"}, \code{"both"}, or
#'     \code{NA}.}
#'   \item{screen_detected, interval_case}{Logical vectors; entries are
#'     \code{NA} when \code{age2_2} is \code{NA}.}
#'   \item{lead_time}{\code{age2_2 - age_at_detection}; zero for interval cases
#'     and \code{NA} wherever \code{age2_2} is \code{NA}.}
#'   \item{n_true_detections, n_interval_cases}{Aggregate numbers of
#'     screen-detected and interval-case histories among histories with a known
#'     clinical age.}
#'   \item{schedule1, schedule2}{Numeric vectors containing the scheduled
#'     screening ages for Tests 1 and 2.}
#'   \item{sensitivity1, specificity1, sensitivity2, specificity2}{Test-
#'     performance inputs retained for traceability.}
#'   \item{age_min1, age_max1, Delta_t1, age_min2, age_max2, Delta_t2}{Screening-
#'     schedule inputs retained for traceability.}
#'   \item{specificity_note}{Character scalar recording how specificity is used
#'     for false positives in \code{S0} and Test 2 detection in \code{Sp1}.}
#' }
#'
#' @details
#' Screening schedules include the starting age and include the ending age only
#' when it lies on the corresponding fixed-interval schedule. A screen at a
#' preclinical-state entrance age is eligible for detection; a screen at the
#' clinical-symptom age is not an early detection. When both tests are scheduled
#' at the same age, both outcomes are generated before screening stops; if both
#' are positive, \code{detected_by} is \code{"both"}. Coincident preclinical
#' transition ages are permitted to support histories recorded on a discrete
#' time grid.
#'
#' Both tests are administered according to their schedules. In \code{S0}, a
#' positive result occurs with probability one minus the corresponding
#' specificity and is counted as a false positive.
#' During \code{Sp1}, Test 1 uses \code{sensitivity1}, whereas Test 2
#' uses one minus \code{specificity2}. Because cancer is present, a positive Test
#' 2 result in \code{Sp1} is classified as a true-positive "lucky" detection and
#' stops screening. 
#' During \code{Sp2}, both tests use their sensitivities.
#' 
#' Once the first true positive is identified, subsequent screening outcomes are
#' not simulated because they cannot change the first-detection age. This is an
#' endpoint convention and does not imply that the individual receives no
#' subsequent screening or clinical follow-up.
#'
#' For histories with an unknown clinical age, false-positive outcomes are
#' simulated at every scheduled screening age strictly before entry into
#' \code{Sp1}. No later positive can be a false positive under this model, so
#' \code{age2_1} and \code{age2_2} are not needed for these counts.
#'
#' @export
lead_time_two_test <- function(
    natural_history,
    sensitivity1,
    specificity1,
    age_min1,
    age_max1,
    Delta_t1,
    sensitivity2,
    specificity2,
    age_min2,
    age_max2,
    Delta_t2,
    seed = NULL,
    verbose = TRUE
) {
  validate_probability <- function(x, name) {
    if (!is.numeric(x) || length(x) != 1L || !is.finite(x) || x < 0 || x > 1) {
      stop(name, " must be a single finite number in [0, 1].")
    }
  }

  validate_finite_scalar <- function(x, name) {
    if (!is.numeric(x) || length(x) != 1L || !is.finite(x)) {
      stop(name, " must be a single finite number.")
    }
  }

  make_schedule <- function(age_min, age_max, Delta_t) {
    seq(age_min, age_max, by = Delta_t)
  }

  make_screening_events <- function(schedule1, schedule2, tolerance) {
    event_age <- c(schedule1, schedule2)
    event_test <- c(
      rep.int(1L, length(schedule1)),
      rep.int(2L, length(schedule2))
    )
    event_order <- order(event_age, event_test)
    event_age <- event_age[event_order]
    event_test <- event_test[event_order]
    event_group <- cumsum(c(TRUE, diff(event_age) > tolerance))
    ages_by_group <- split(event_age, event_group)
    tests_by_group <- split(event_test, event_group)

    data.frame(
      age = vapply(ages_by_group, min, numeric(1)),
      test1 = vapply(tests_by_group, function(x) any(x == 1L), logical(1)),
      test2 = vapply(tests_by_group, function(x) any(x == 2L), logical(1)),
      row.names = NULL
    )
  }

  draw_positive <- function(sensitivity) {
    if (sensitivity == 0) return(FALSE)
    if (sensitivity == 1) return(TRUE)
    stats::runif(1L) < sensitivity
  }

  draw_false_positive <- function(specificity) {
    draw_positive(1 - specificity)
  }

  if (!is.list(natural_history)) {
    stop("natural_history must be a list.")
  }
  required_ages <- c("age1", "age2_1", "age2_2")
  missing_ages <- required_ages[!vapply(
    required_ages,
    function(name) !is.null(natural_history[[name]]),
    logical(1)
  )]
  if (length(missing_ages) > 0L) {
    stop(
      "natural_history is missing required transition vector(s): ",
      paste(missing_ages, collapse = ", "),
      "."
    )
  }

  transition_ages <- natural_history[required_ages]
  if (any(!vapply(transition_ages, is.numeric, logical(1)))) {
    stop("age1, age2_1, and age2_2 must be numeric vectors.")
  }
  vector_lengths <- vapply(transition_ages, length, integer(1))
  if (length(unique(vector_lengths)) != 1L || vector_lengths[[1]] == 0L) {
    stop("age1, age2_1, and age2_2 must be nonempty vectors of equal length.")
  }
  if (any(vapply(
    transition_ages,
    function(x) any(!is.na(x) & !is.finite(x)),
    logical(1)
  ))) {
    stop("Transition ages must be finite or NA.")
  }

  validate_probability(sensitivity1, "sensitivity1")
  validate_probability(specificity1, "specificity1")
  validate_probability(sensitivity2, "sensitivity2")
  validate_probability(specificity2, "specificity2")

  validate_finite_scalar(age_min1, "age_min1")
  validate_finite_scalar(age_max1, "age_max1")
  validate_finite_scalar(Delta_t1, "Delta_t1")
  validate_finite_scalar(age_min2, "age_min2")
  validate_finite_scalar(age_max2, "age_max2")
  validate_finite_scalar(Delta_t2, "Delta_t2")
  if (age_min1 > age_max1 || age_min2 > age_max2) {
    stop("Each screening start age must be less than or equal to its end age.")
  }
  if (Delta_t1 <= 0 || Delta_t2 <= 0) {
    stop("Delta_t1 and Delta_t2 must be positive.")
  }
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("verbose must be TRUE or FALSE.")
  }
  if (!is.null(seed)) {
    if (!is.numeric(seed) || length(seed) != 1L || !is.finite(seed) ||
        seed < 0 || seed > .Machine$integer.max || seed != floor(seed)) {
      stop("seed must be NULL or one non-negative integer-valued number.")
    }
    set.seed(as.integer(seed))
  }

  age1 <- natural_history$age1
  age2_1 <- natural_history$age2_1
  age2_2 <- natural_history$age2_2
  nsamples <- length(age1)
  known_clinical_age <- !is.na(age2_2)

  if (anyNA(age1)) {
    stop("age1 must be nonmissing for every history.")
  }
  if (any(known_clinical_age & (is.na(age1) | is.na(age2_1)))) {
    stop("Every nonmissing age2_2 requires nonmissing age1 and age2_1.")
  }
  ordering_tolerance <- 1e-10
  invalid_order <- known_clinical_age & (
    age1 > age2_1 + ordering_tolerance |
      age2_1 > age2_2 + ordering_tolerance
  )
  if (any(invalid_order)) {
    stop("Transition ages must satisfy age1 <= age2_1 <= age2_2.")
  }

  schedule1 <- make_schedule(age_min1, age_max1, Delta_t1)
  schedule2 <- make_schedule(age_min2, age_max2, Delta_t2)
  screening_events <- make_screening_events(
    schedule1,
    schedule2,
    ordering_tolerance
  )

  first_true_positive1 <- rep(NA_real_, nsamples)
  first_true_positive2 <- rep(NA_real_, nsamples)
  first_true_positive <- rep(NA_real_, nsamples)
  n_test1_before_true_positive <- rep(NA_integer_, nsamples)
  n_test2_before_true_positive <- rep(NA_integer_, nsamples)
  n_test1_false_positives <- rep(NA_integer_, nsamples)
  n_test2_false_positives <- rep(NA_integer_, nsamples)
  detected_by <- rep(NA_character_, nsamples)

  for (i in which(known_clinical_age)) {
    n_test1_so_far <- 0L
    n_test2_so_far <- 0L
    n_test1_false_positives[i] <- 0L
    n_test2_false_positives[i] <- 0L

    for (event_index in seq_len(nrow(screening_events))) {
      screening_age <- screening_events$age[event_index]
      # age2_2 is the clinical diagnosis age, not a screening opportunity.
      if (screening_age >= age2_2[i] - ordering_tolerance) {
        break
      }

      positive1 <- FALSE
      positive2 <- FALSE

      if (screening_age < age1[i] - ordering_tolerance) {
        # S0: positive results are false positives and do not stop screening.
        if (screening_events$test1[event_index] &&
            draw_false_positive(specificity1)) {
          n_test1_false_positives[i] <-
            n_test1_false_positives[i] + 1L
        }
        if (screening_events$test2[event_index] &&
            draw_false_positive(specificity2)) {
          n_test2_false_positives[i] <-
            n_test2_false_positives[i] + 1L
        }
      } else if (screening_age < age2_1[i] - ordering_tolerance) {
        # Sp1: Test 1 uses sensitivity; a Test 2 positive is a lucky detection.
        positive1 <- screening_events$test1[event_index] &&
          draw_positive(sensitivity1)
        positive2 <- screening_events$test2[event_index] &&
          draw_positive(1 - specificity2)
      } else {
        # Sp2: both tests use their sensitivities.
        positive1 <- screening_events$test1[event_index] &&
          draw_positive(sensitivity1)
        positive2 <- screening_events$test2[event_index] &&
          draw_positive(sensitivity2)
      }

      if (positive1 || positive2) {
        if (positive1) {
          first_true_positive1[i] <- screening_age
        }
        if (positive2) {
          first_true_positive2[i] <- screening_age
        }
        
        first_true_positive[i] <- screening_age
        n_test1_before_true_positive[i] <- n_test1_so_far
        n_test2_before_true_positive[i] <- n_test2_so_far
        
        detected_by[i] <- if (positive1 && positive2) {
          "both"
        } else if (positive1) {
          "test1"
        } else {
          "test2"
        }
        break
      }

      n_test1_so_far <- n_test1_so_far +
        as.integer(screening_events$test1[event_index])
      n_test2_so_far <- n_test2_so_far +
        as.integer(screening_events$test2[event_index])
    }
  }

  # Clinical age is not required to count false positives. Complete these
  # counts for censored histories after the main loop so that the random draws,
  # and therefore all existing results, remain unchanged for histories with a
  # known clinical age.
  for (i in which(!known_clinical_age)) {
    n_test1_false_positives[i] <- 0L
    n_test2_false_positives[i] <- 0L

    for (event_index in seq_len(nrow(screening_events))) {
      screening_age <- screening_events$age[event_index]

      # At and after entry into Sp1, a positive result is not a false positive.
      if (screening_age >= age1[i] - ordering_tolerance) {
        break
      }

      if (screening_events$test1[event_index] &&
          draw_false_positive(specificity1)) {
        n_test1_false_positives[i] <-
          n_test1_false_positives[i] + 1L
      }
      if (screening_events$test2[event_index] &&
          draw_false_positive(specificity2)) {
        n_test2_false_positives[i] <-
          n_test2_false_positives[i] + 1L
      }
    }
  }

  n_false_positives <-
    n_test1_false_positives + n_test2_false_positives
  total_test1_false_positives <-
    sum(n_test1_false_positives, na.rm = TRUE)
  total_test2_false_positives <-
    sum(n_test2_false_positives, na.rm = TRUE)
  total_false_positives <- sum(n_false_positives, na.rm = TRUE)

  screen_detected <- rep(NA, nsamples)
  screen_detected[known_clinical_age] <-
    !is.na(first_true_positive[known_clinical_age])
  interval_case <- rep(NA, nsamples)
  interval_case[known_clinical_age] <- !screen_detected[known_clinical_age]

  age_at_detection <- rep(NA_real_, nsamples)
  age_at_detection[known_clinical_age] <- age2_2[known_clinical_age]
  age_at_detection[known_clinical_age & screen_detected] <-
    first_true_positive[known_clinical_age & screen_detected]

  lead_time <- rep(NA_real_, nsamples)
  lead_time[known_clinical_age] <-
    age2_2[known_clinical_age] - age_at_detection[known_clinical_age]

  n_true_detections <- sum(screen_detected, na.rm = TRUE)
  n_interval_cases <- sum(interval_case, na.rm = TRUE)

  if (verbose) {
    message("Number of samples: ", nsamples)
    message("Number with known clinical age: ", sum(known_clinical_age))
    message("Number of true screening detections: ", n_true_detections)
    message("Number of interval cases: ", n_interval_cases)
    message(
      "Number of Test 1 false-positive results: ",
      total_test1_false_positives
    )
    message(
      "Number of Test 2 false-positive results: ",
      total_test2_false_positives
    )
    message("Total number of false-positive results: ", total_false_positives)
    message("Lead time among true screening detections:")
    print(summary(lead_time[screen_detected %in% TRUE]))
    message("Lead time among all histories with known clinical age:")
    print(summary(lead_time[known_clinical_age]))
    message("Number of Test 1 administrations before true-positive detection:")
    print(summary(n_test1_before_true_positive[screen_detected %in% TRUE]))
    message("Number of Test 2 administrations before true-positive detection:")
    print(summary(n_test2_before_true_positive[screen_detected %in% TRUE]))
    message("Number of Test 1 false positives across all samples:")
    print(summary(n_test1_false_positives))
    message("Number of Test 2 false positives across all samples:")
    print(summary(n_test2_false_positives))
  }

  list(
    cancer = natural_history$cancer,
    gene = natural_history$gene,
    sex = natural_history$sex,
    race = natural_history$race,
    tmax = natural_history$tmax,
    first_true_positive1 = first_true_positive1,
    first_true_positive2 = first_true_positive2,
    first_true_positive = first_true_positive,
    n_test1_before_true_positive = n_test1_before_true_positive,
    n_test2_before_true_positive = n_test2_before_true_positive,
    n_test1_false_positives = n_test1_false_positives,
    n_test2_false_positives = n_test2_false_positives,
    n_false_positives = n_false_positives,
    total_test1_false_positives = total_test1_false_positives,
    total_test2_false_positives = total_test2_false_positives,
    total_false_positives = total_false_positives,
    age_at_detection = age_at_detection,
    detected_by = detected_by,
    screen_detected = screen_detected,
    interval_case = interval_case,
    lead_time = lead_time,
    n_true_detections = n_true_detections,
    n_interval_cases = n_interval_cases,
    schedule1 = schedule1,
    schedule2 = schedule2,
    sensitivity1 = sensitivity1,
    specificity1 = specificity1,
    sensitivity2 = sensitivity2,
    specificity2 = specificity2,
    age_min1 = age_min1,
    age_max1 = age_max1,
    Delta_t1 = Delta_t1,
    age_min2 = age_min2,
    age_max2 = age_max2,
    Delta_t2 = Delta_t2,
    specificity_note = paste(
      "Both specificities generate false-positive results in S0. During Sp1,",
      "one minus specificity2 is also the probability of a true-positive Test 2",
      "lucky detection. Genuine false positives do not interrupt screening."
    )
  )
}
