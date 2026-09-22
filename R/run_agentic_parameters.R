#' run_agentic_parameters
#'
#' Run the agentic Python parameter pipeline and import results into R
#'
#' This function calls a Python script that runs the Proposer–Critic–Summarizer
#' workflow. By default, it waits for the script to finish, locates the most
#' recently modified parameter CSV file in \code{logs_dir}, and returns the
#' parameters as an R data frame together with the CSV path.
#'
#' The Python script is expected to:
#' \itemize{
#'   \item use the OpenAI API (or equivalent) to run the agentic
#'         Proposer–Critic–Summarizer pipeline, and
#'   \item write a parameter table to a CSV file named
#'         \code{parameters_YYYYMMDD_HHMMSS.csv} in the output directory
#'         configured by the Python script.
#' }
#' @param problem_text Character scalar or \code{NULL}. User problem text passed
#'   to the agentic system. Default is \code{NULL}.
#' @param template Character scalar or \code{NULL}. Registered template name,
#'   such as \code{"one_test_model"} or \code{"two_test_model"}. Default is
#'   \code{NULL}.
#' @param python_exec Character scalar. Python executable to use. Default is
#'   \code{"python3"}.
#' @param script_path Character. Path to the agentic Python script to run. 
#'   Default is \code{"python/two_agent_system_parameters_csv.py"}.
#' @param logs_dir Character scalar. Directory in which this R wrapper searches
#'   for \code{parameters_*.csv} files. It must match the Python script's output
#'   directory. Default is \code{"logs"}.
#' @param wait Logical. If \code{TRUE} (default), wait for the Python
#'   process to finish before searching \code{logs_dir}. If \code{FALSE}, the
#'   wrapper searches immediately and may therefore select an existing file.
#'   
#' @details
#' The function can be used in two modes:
#' \itemize{
#'   \item \strong{Interactive mode} (the default): if both \code{problem_text} and
#'   \code{template} are \code{NULL}, the Python script is run without
#'   \code{--non_interactive} and prompts the user for the required inputs.
#'   \item \strong{Non-interactive mode}: provide both \code{problem_text} and
#'   \code{template}. The Python script is run with \code{--non_interactive},
#'   making the call suitable for scripts and automated analyses.
#' }
#' If only one of \code{problem_text} or \code{template} is supplied,
#' the Python script may still prompt for the missing input or return an error.
#' Interactive mode is intended for exploratory use in an R console.
#' Non-interactive mode is recommended for automated analyses; a vignette can
#' instead read previously generated CSV files when live API access is undesirable.
#'
#' @return A list with two elements:
#' \describe{
#'   \item{parameters}{A data frame containing the parameter table read
#'         from the latest CSV file in \code{logs_dir}.}
#'   \item{csv_path}{Character scalar with the path to the CSV file used.}
#' }
#' 
#' @export
run_agentic_parameters <- function(
    problem_text = NULL,
    template = NULL,
    python_exec = "python3",
    script_path = "python/two_agent_system_parameters_csv.py",
    logs_dir = "logs",
    wait = TRUE
) {
  args <- character(0)
  
  if (!is.null(problem_text)) {
    args <- c(args, "--problem", shQuote(problem_text))
  }
  
  if (!is.null(template)) {
    args <- c(args, "--template", shQuote(template), "--non_interactive")
  }
    
  has_openai_key <- function() {
    key <- Sys.getenv("OPENAI_API_KEY")
    nzchar(key)
  }
  if (!has_openai_key()) {
    stop(
      "OPENAI_API_KEY is not set.\n",
      "Set it with: export OPENAI_API_KEY='sk-...'\n",
      "Or use the vignette that reads parameters from CSV instead."
    )
  }
  
  message("Running agentic parameter system...")
  exit_code <- system2(python_exec, args = c(script_path, args), wait = wait)

  if (exit_code != 0) stop("Python script failed with exit code: ", exit_code)
  
  csv_files <- list.files(logs_dir, pattern = "^parameters_.*\\.csv$", full.names = TRUE)
  if (length(csv_files) == 0) stop("No parameter CSV files found in ", logs_dir)
  
  latest_csv <- csv_files[which.max(file.info(csv_files)$mtime)]
  message("Using latest parameter file: ", latest_csv)
  
  params_df <- read.csv(latest_csv, stringsAsFactors = FALSE)
  
  list(parameters = params_df, csv_path = latest_csv)
}
