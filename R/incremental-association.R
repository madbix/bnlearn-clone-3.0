
incremental.association.optimized = function(x, whitelist, blacklist, test,
  alpha, B, strict, debug = FALSE) {

  nodes = names(x)
  mb2 = mb = list()

  # 1. [Compute Markov Blankets]
  for (node in nodes) {

    backtracking = unlist(sapply(mb, function(x){ node %in% x  }))

    mb[[node]] = ia.markov.blanket(node, data = x, nodes = nodes,
         alpha = alpha, B = B, whitelist = whitelist, blacklist = blacklist,
         backtracking = backtracking, test = test, debug = debug)

  }#FOR

  # check markov blankets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, mb = TRUE, debug = debug)

  # 2. [Compute Graph Structure]
  for (node in nodes) {

    backtracking = unlist(sapply(mb2, function(x){ node %in% x[["nbr"]]  }))

    # save results in a copy of mb;
    mb2[[node]] = neighbour(node, mb = mb, data = x, alpha = alpha,
         B = B, whitelist = whitelist, blacklist = blacklist,
         backtracking = backtracking, test = test, debug = debug)

  }#FOR

  # update mb with the results of neighbour().
  mb = mb2

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#INCREMENTAL.ASSOCIATION.OPTIMIZED

incremental.association.cluster = function(x, cluster, whitelist, blacklist,
  test, alpha, B, strict, debug = FALSE) {

  nodes = names(x)

  # 1. [Compute Markov Blankets]
  mb = parLapply(cluster, as.list(nodes), ia.markov.blanket, data = x,
         nodes = nodes, alpha = alpha, B = B, whitelist = whitelist,
         blacklist = blacklist, test = test, debug = debug)
  names(mb) = nodes

  # check markov blankets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, mb = TRUE, debug = debug)

  # 2. [Compute Graph Structure]
  mb = parLapply(cluster, as.list(nodes), neighbour, mb = mb, data = x,
         alpha = alpha, B = B, whitelist = whitelist, blacklist = blacklist,
         test = test, debug = debug)
  names(mb) = nodes

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#INCREMENTAL.ASSOCIATION.CLUSTER

incremental.association = function(x, whitelist, blacklist, test, alpha,
  B, strict, debug = FALSE) {

  nodes = names(x)

  # 1. [Compute Markov Blankets]
  mb = lapply(as.list(nodes), ia.markov.blanket, data = x, nodes = nodes,
         alpha = alpha, B = B, whitelist = whitelist, blacklist = blacklist,
         test = test, debug = debug)
  names(mb) = nodes

  # check markov blankets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, mb = TRUE, debug = debug)

  # 2. [Compute Graph Structure]
  mb = lapply(as.list(nodes), neighbour, mb = mb, data = x, alpha = alpha,
         B = B, whitelist = whitelist, blacklist = blacklist, test = test,
         debug = debug)
  names(mb) = nodes

  # check neighbourhood sets for consistency.
  mb = bn.recovery(mb, nodes = nodes, strict = strict, debug = debug)

  return(mb)

}#INCREMENTAL.ASSOCIATION

ia.markov.blanket = function(x, data, nodes, alpha, B, whitelist, blacklist,
  start = character(0), backtracking = NULL, test, debug = FALSE) {

  nodes = nodes[nodes != x]
  known.good = known.bad = c()
  whitelisted = nodes[sapply(nodes,
          function(y) { is.whitelisted(whitelist, c(x, y), either = TRUE) })]
  mb = start
  to.add = ""

  # growing phase
  if (debug) {

    cat("----------------------------------------------------------------\n")
    cat("* learning the markov blanket of", x, ".\n")

    if (length(start) > 0)
      cat("* initial set includes '", mb, "'.\n")

  }#THEN

  # whitelisted nodes are included by default (if there's a direct arc
  # between them of course they are in each other's markov blanket).
  # arc direction is irrelevant here.
  mb = unique(c(mb, whitelisted))
  nodes = nodes[!(nodes %in% mb)]
  # blacklist is not checked, not all nodes in a markov blanket must be
  # neighbours.

  # use backtracking for a further screening of the nodes to be checked.
  if (!is.null(backtracking)) {

    # nodes whose markov blanket includes this node are included, because
    # X \in MB(Y) <=> Y \in MB(X)
    known.good = names(backtracking[backtracking])
    mb = unique(c(mb, known.good))

    # and vice versa X \not\in MB(Y) <=> Y \not\in MB(X)
    known.bad = names(backtracking[!backtracking])

    # both are not to be checked for inclusion/exclusion.
    nodes = nodes[!(nodes %in% names(backtracking))]

    if (debug) {

      cat("    * known good (backtracking): '", known.good, "'.\n")
      cat("    * known bad (backtracking): '", known.bad, "'.\n")
      cat("    * nodes still to be tested for inclusion: '", nodes, "'.\n")

    }#THEN

  }#THEN

  # phase I (stepwise forward selection)
  repeat {

    if (debug)
      cat("  * checking nodes for association (growing phase).\n")

    # get an association measure for each of the available nodes.
    association = sapply(nodes, conditional.test, x, sx = mb, test = test,
                    data = data, B = B, alpha = alpha, debug = debug)

    # stop if there are no candidates for inclusion.
    if (all(association > alpha) || length(nodes) == 0 || is.null(nodes)) break
    # get the one which maximizes the association measure.
    to.add = names(which.min(association))

    if (debug)
      cat("  @", to.add, "included in the markov blanket.\n")

    mb = c(mb, to.add)
    nodes = nodes[nodes != to.add]

  }#REPEAT

  # phase II (backward selection)
  del.node = function(y, x, test) {

    a = conditional.test(x, y, mb[mb != y], data = data, test = test, B = B,
          alpha = alpha, debug = debug)

    if (a > alpha) {

      if (debug)
        cat("  @ node", y, "removed from the markov blanket.\n")

      # update the markov blanket.
      assign("mb", mb[mb != y], envir = sys.frame(-3))

      return(NULL)

    }#THEN

  }#DEL.NODE

  # whitelisted nodes are neighbours, they cannot be removed from the
  # markov blanket; the last node added in phase I will never be removed,
  # because the tests for inclusion and removal are identical.
  # known.good nodes from backtracking are not to be removed, either.
  if (length(mb) > 1) {
    
    if (debug)
      cat("  * checking nodes for exclusion (shrinking phase).\n")

    to.check = mb[!(mb %in% c(known.good, to.add, whitelisted))]

    # heuristic : order nodes from the last one added to the first one added
    # this way we are more prone to remove less correlated nodes first
    if (length(to.check) > 0)
      to.check = rev(to.check)

    sapply(to.check, del.node, x = x, test = test)

  }#THEN

  mb

}#IA.MARKOV.BLANKET

