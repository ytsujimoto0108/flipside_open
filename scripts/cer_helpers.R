#!/usr/bin/env Rscript

aggregate_cer <- function(event, n) {
  event <- as.numeric(event)
  n <- as.numeric(n)
  keep <- is.finite(event) & is.finite(n) & n > 0 & event >= 0 & event <= n
  event <- event[keep]
  n <- n[keep]

  if (length(n) == 0 || sum(n) <= 0) {
    return(NA_real_)
  }

  sum(event, na.rm = TRUE) / sum(n, na.rm = TRUE)
}

estimate_pooled_cer <- function(event, n) {
  event <- as.numeric(event)
  n <- as.numeric(n)
  keep <- is.finite(event) & is.finite(n) & n > 0 & event >= 0 & event <= n
  event <- event[keep]
  n <- n[keep]

  aggregate <- aggregate_cer(event, n)
  k <- length(event)

  if (k < 2 || is.na(aggregate) || aggregate <= 0 || aggregate >= 1) {
    return(list(
      cer = aggregate,
      method = "aggregate",
      k = k
    ))
  }

  warnings_seen <- character()
  if (!requireNamespace("metafor", quietly = TRUE)) {
    return(list(
      cer = aggregate,
      method = "aggregate",
      k = k
    ))
  }

  fit_expr <- function() {
    withCallingHandlers(
      metafor::rma.glmm(
        xi = event,
        ni = n,
        measure = "PLO",
        method = "ML"
      ),
      warning = function(w) {
        warnings_seen <<- c(warnings_seen, conditionMessage(w))
        invokeRestart("muffleWarning")
      }
    )
  }

  fit <- tryCatch(
    if (requireNamespace("R.utils", quietly = TRUE)) {
      R.utils::withTimeout(
        fit_expr(),
        timeout = getOption("flipsides.cer_glmm_timeout", 5),
        onTimeout = "error"
      )
    } else {
      fit_expr()
    },
    error = function(e) NULL
  )

  convergence_warning <- any(grepl(
    "conver|singular|hessian|failed|failure|non-positive|degenerate|algorithm",
    warnings_seen,
    ignore.case = TRUE
  ))

  logit_cer <- if (!is.null(fit)) as.numeric(stats::coef(fit)[1]) else NA_real_

  if (is.null(fit) || convergence_warning || !is.finite(logit_cer)) {
    return(list(
      cer = aggregate,
      method = "aggregate",
      k = k
    ))
  }

  cer <- stats::plogis(logit_cer)
  if (!is.finite(cer) || cer < 0 || cer > 1) {
    return(list(
      cer = aggregate,
      method = "aggregate",
      k = k
    ))
  }

  list(
    cer = cer,
    method = "GLMM",
    k = k
  )
}
