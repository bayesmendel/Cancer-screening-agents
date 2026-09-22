source(file.path("R", "parse_params.R"))
source(file.path("R", "sojourn_times.R"))
source(file.path("R", "w.R"))
source(file.path("R", "natural_history_simulation_two_test.R"))
source(file.path("R", "lead_time_two_test.R"))

library(Fam3PRO)

cancer <- "Colorectal"
sex <- "Female"
gene <- "SEER"
nsamples <- 1000000

input_dir <- file.path("data", "paper_case_study", "agent_generated_inputs")

# New simulation results are written to results/paper_case_study by default.
# To use another location, set CANCER_SCREENING_OUTPUT_DIR before running this
# script. The default results directory is excluded from version control.
output_dir <- Sys.getenv("CANCER_SCREENING_OUTPUT_DIR")
if (!nzchar(output_dir)) {
  output_dir <- file.path("results", "paper_case_study")
}
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

screening_strategy <- read.csv(
  file.path(input_dir, "parameters_20260819_154630.csv")
)
test1_parameters <- read.csv(
  file.path(input_dir, "parameters_20260814_195949.csv")
)
test2_parameters <- read.csv(
  file.path(input_dir, "parameters_20260814_190648.csv")
)

test1_name <- screening_strategy$Value[3]
age_min1 <- as.numeric(screening_strategy$Value[4])
age_max1 <- as.numeric(screening_strategy$Value[5])
Delta_t1 <- as.numeric(screening_strategy$Value[6])

test2_name <- screening_strategy$Value[7]
age_min2 <- as.numeric(screening_strategy$Value[8])
age_max2 <- as.numeric(screening_strategy$Value[9])
Delta_t2 <- as.numeric(screening_strategy$Value[10])

if (!is.na(test1_parameters$Value[4])) {
  MST1 <- parse_param_value(test1_parameters$Value[4])
} else {
  MST1 <- suppressWarnings(as.numeric(test1_parameters$Value[5]))
}
sensitivity1 <- as.numeric(test1_parameters$Value[6])
specificity1 <- as.numeric(test1_parameters$Value[7])

if (!is.na(test2_parameters$Value[4])) {
  MST2 <- parse_param_value(test2_parameters$Value[4])
} else {
  MST2 <- suppressWarnings(as.numeric(test2_parameters$Value[5]))
}
sensitivity2 <- as.numeric(test2_parameters$Value[6])
specificity2 <- as.numeric(test2_parameters$Value[7])

set.seed(2782005)
natural_history_object <- natural_history_simulation_two_test(
  cancer = cancer,
  gene = gene,
  sex = sex,
  MST1 = MST1,
  MST2 = MST2,
  nsamples = nsamples,
  verbose = TRUE
)

lead_time_object <- lead_time_two_test(
  natural_history = natural_history_object,
  sensitivity1 = sensitivity1,
  specificity1 = specificity1,
  age_min1 = age_min1,
  age_max1 = age_max1,
  Delta_t1 = Delta_t1,
  sensitivity2 = sensitivity2,
  specificity2 = specificity2,
  age_min2 = age_min2,
  age_max2 = age_max2,
  Delta_t2 = Delta_t2,
  seed = 2782006,
  verbose = TRUE
)

saveRDS(natural_history_object, file.path(output_dir, "natural_history.rds"))
saveRDS(lead_time_object, file.path(output_dir, "lead_time.rds"))
