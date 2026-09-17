!start.

+!start
    <- run_job(test).

+status(test, success)
    <- .print("INTEGRATION_BELIEF_RECEIVED status(test, success)");
       .stopMAS.
