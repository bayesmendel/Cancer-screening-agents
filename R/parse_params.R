#' parse_param_value
#'
#' Parse an agentic parameter value into a usable R object
#'
#' Helper used when reading agentic parameter tables. This function standardizes
#' a single table "Value" cell into one of:
#' \itemize{
#'   \item \code{NA} for missing/empty/"NA" values,
#'   \item a numeric scalar for clean numbers (e.g., \code{"5.25"}),
#'   \item a small data frame for age-band values encoded as
#'         \code{"age:value; age:value; ..."} (e.g., \code{"45–54:2; 55–64:3"}), or
#'   \item a character string for non-numeric categorical values.
#' }
#'
#' This is intended to support automated ingestion of agentic outputs into
#' downstream simulation code.
#'
#' @param x A single value (typically a character string) from the "Value" column
#'   of an agentic parameter table.
#'
#' @return One of: \code{NA}; a numeric scalar; a data frame with columns
#'   \code{age_band}, \code{value}, \code{value_raw}; or a character string.
parse_param_value <- function(x) {
  # Normalize missing
  if (length(x) == 0 || is.na(x)) return(NA)
  x <- trimws(as.character(x))
  if (x == "" || toupper(x) == "NA") return(NA)
  
  # If it's a clean single number, return numeric scalar
  x_num <- suppressWarnings(as.numeric(x))
  if (!is.na(x_num) && grepl("^[-+]?[0-9]*\\.?[0-9]+$", x)) {
    return(x_num)
  }
  
  # If it looks like age-band pairs (has ":"), parse into a data.frame
  if (grepl(":", x, fixed = TRUE)) {
    # split on semicolons
    pairs <- strsplit(x, ";", fixed = TRUE)[[1]]
    pairs <- trimws(pairs)
    pairs <- pairs[nzchar(pairs)]
    
    age_band <- sub(":.*$", "", pairs)
    value_str <- trimws(sub("^.*?:", "", pairs))
    value_num <- suppressWarnings(as.numeric(value_str))
    
    # If any values fail numeric conversion, keep them as character too
    out <- data.frame(
      age_band = age_band,
      value = value_num,
      value_raw = value_str,
      stringsAsFactors = FALSE
    )
    return(out)
  }
  # Otherwise, return the raw string (fallback for categorical params etc.)
  return(x)
}

#' Convert percentages to probabilities
#'
#' Helper used when parsing agentic parameter tables. Converts character
#' percentages (e.g. \code{"80\%"}) to numeric probabilities (e.g. \code{0.8}).
#' Numeric inputs are returned unchanged.
#'
#' @param x A numeric value or a character string representing either a
#'   probability (e.g. \code{"0.8"}) or a percentage (e.g. \code{"80\%"}).
#'
#' @return A numeric probability.
percent_to_prob <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  if (grepl("%$", x)) {
    return(as.numeric(sub("%", "", x)) / 100)
  }
  as.numeric(x)
}
