#' Cache and retrieve an \code{src_sqlite} of the Lahman baseball database.
#'
#' This creates an interesting database using data from the Lahman baseball
#' data source, provided by Sean Lahman at
#' \url{http://www.seanlahman.com/baseball-archive/statistics/}, and
#' made easily available in R through the \pkg{Lahman} package by
#' Michael Friendly, Dennis Murphy and Martin Monkman. See the documentation
#' for that package for documentation of the inidividual tables.
#'
#' @param path location to look for and cache SQLite database. If \code{NULL},
#'   the default, will first try storing in the installed package directory, and
#'   if that isn't writeable, a temporary directory.
#' @param dbname,... Arguments passed to \code{src} on first
#'   load. For mysql and postgresql, the defaults assume you have a local
#'   server with \code{lahman} database already created.
#' @examples
#' lahman_sqlite()
#' batting <- tbl(lahman_sqlite(), "Batting")
#' batting
#'
#' # Connect to a local postgres database with lahman database, if available
#' if (has_lahman("postgres")) {
#'   lahman_postgres()
#'   batting <- tbl(lahman_postgres(), "Batting")
#' }
#' @name lahman
NULL

#' @export
#' @rdname lahman
lahman_sqlite <- function(path = NULL) {
  if (!is.null(cache$lahman_sqlite)) return(cache$lahman_sqlite)
  
  path <- db_location(path, "lahman.sqlite")
  
  if (!file.exists(path)) {
    message("Caching Lahman db at ", path)
    src <- src_sqlite(path, create = TRUE)
    cache_lahman(src, quiet = FALSE)
  } else {
    src <- src_sqlite(path)
  }
  
  cache$lahman_sqlite <- src
  src
}

#' @export
#' @rdname lahman
lahman_postgres <- function(dbname = "lahman", ...) {
  if (!is.null(cache$lahman_postgres)) return(cache$lahman_postgres)
  
  src <- src_postgres(dbname, ...)
  
  missing <- setdiff(lahman_tables(), src_tbls(src))
  if (length(missing) > 0) {
    cache_lahman(src, quiet = FALSE)
  }
  
  cache$lahman_postgres <- src
  src
}

#' @export
#' @rdname lahman
lahman_mysql <- function(dbname = "lahman", ...) {
  if (!is.null(cache$lahman_mysql)) return(cache$lahman_mysql)
  
  src <- src_mysql(dbname, ...)
  
  missing <- setdiff(lahman_tables(), src_tbls(src))
  if (length(missing) > 0) {
    cache_lahman(src, quiet = FALSE)
  }
  
  cache$lahman_mysql <- src
  src
}

#' @export
#' @rdname lahman
lahman_bigquery <- function(project = "hadbilling", ..., quiet = FALSE) {
  if (!is.null(cache$lahman_bigquery)) return(cache$lahman_bigquery)
  
  src <- src_bigquery(project, dataset = "lahman", ...)
  
  missing <- setdiff(lahman_tables(), src_tbls(src))
  jobs <- vector("list", length(missing))
  names(jobs) <- missing
  for(table in missing) {
    df <- get(table, "package:Lahman")
    
    if (!quiet) message("Creating table ", table)
    jobs[[table]] <- insert_upload_job(src$con$project, src$con$dataset, table, 
      df, billing = src$con$billing)
  }
  
  for (table in names(jobs)) {
    message("Waiting for ", table)
    try(wait_for(jobs[[table]]))
  }
  
  
  cache$lahman_bigquery <- src
  src
}


#' @rdname lahman
#' @export
has_lahman <- function(src) {
  switch(src,
    sqlite = file.exists(db_location(NULL, "lahman.sqlite")),
    mysql = succeeds(src_mysql("lahman")),
    postgres = succeeds(src_postgres("lahman")),
    stop("Unknown src ", src, call. = FALSE)
  )
}
succeeds <- function(x) {
  ok <- FALSE
  try({
    force(x)
    ok <- TRUE
  }, silent = TRUE)
  
  ok 
}


cache_lahman <- function(src, index = TRUE, quiet = FALSE) {
  if (!require("Lahman")) {
    stop("Please install the Lahman package", call. = FALSE)
  }

  tables <- setdiff(lahman_tables(), src_tbls(src))
  for(table in tables) {
    df <- get(table, "package:Lahman")
    if (!quiet) message("Creating table ", table)
    
    ids <- as.list(names(df)[grepl("ID$", names(df))])
    copy_to(src, df, table, indexes = if (index) ids, temporary = FALSE)
  }
  
  invisible(TRUE)
}

# Get list of all non-label data frames in package
lahman_tables <- function() {
  tables <- data(package = "Lahman")$results[, 3]
  tables[!grepl("Labels", tables)]
}
