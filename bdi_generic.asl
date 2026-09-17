// Project-specific beliefs are generated from 01_pipeline.yaml and 02_goal.yaml.

// Generic controller runtime state.
run_sequence(0).
workflow_active.


// ======================
// RULES
// ======================

// DEPENDENCIES

holds([]).

holds([Head | Tail]) :-
    phase_result(Head, success)
    & holds(Tail).

// TERMINAL STATE
terminal(Entity) :-
    terminal(Entity, _).

// NEXT NORMAL ENTITY

nextentity(Entity) :-
    workflow_active
    & not workflow_stopped
    & entity(Entity)
    & not recovery_entity(Entity)
    & depends(Entity, Requirements)
    & not running(Entity)
    & not terminal(Entity)
    & not phase_result(Entity, success)
    & holds(Requirements).

// MAINTENANCE

duration_ok(Entity, Time, Max) :-
    max_duration(Entity, Max)
    & duration(Entity, Time)
    & Time <= Max.

duration_violation(Entity, Time, Max) :-
    max_duration(Entity, Max)
    & duration(Entity, Time)
    & Time > Max.

retry_allowed(Entity) :-
    max_retries(Max)
    & attempt_count(Entity, Attempts)
    & Attempts <= Max.

// AVOIDANCE
avoidance_violation(Entity) :-
    avoid_missing(Entity, Required)
    & phase_result(Entity, success)
    & not phase_result(Required, success).


// ======================
// INITIAL GOAL
// ======================

!master_goal.

// MASTER GOAL

+!master_goal
    : achievement(Entity, Desired)
    <- .print("Master goal started.");
       !need_achieve(Entity, Desired);
       !check_avoidance.

// ======================
// ACHIEVEMENT GOALS
// ======================

// WORKFLOW ALREADY STOPPED

+!need_achieve(Entity, Desired)
    : workflow_stopped
    <- .print("Workflow stopped before achievement: ", Entity, " = ", Desired).

// ALREADY ACHIEVED

+!need_achieve(Entity, Desired)
    : phase_result(Entity, Desired)
    <- .print("Achievement satisfied: ", Entity, " = ", Desired).

// ======================
// START WORKFLOW
// ======================

+!need_achieve(Entity, Desired)
    : not phase_result(Entity, Desired)
      & not workflow_started
      & not workflow_stopped
    <- +workflow_started;
       .print("Pursuing achievement: ", Entity, " = ", Desired);
       !run_pipeline.

// WORKFLOW ALREADY RUNNING
+!need_achieve(Entity, Desired)
    : not phase_result(Entity, Desired)
      & workflow_started
      & not workflow_stopped
    <- .print("Achievement pending: ", Entity, " = ", Desired).


// ======================
// RUN PIPELINE
// ======================

// STOPPED
+!run_pipeline
    : workflow_stopped
    <- .print("Pipeline is stopped.").

// COMPLETED
+!run_pipeline
    : final_phase(Final)
      & phase_result(Final, success)
      & not workflow_completed
    <- -workflow_active;
       +workflow_completed;
       .print("Pipeline reached final success.");
       !check_master_goal.

// JOB CURRENTLY RUNNING
+!run_pipeline
    : running(_)
    <- true.

// RUN NEXT ENTITY
+!run_pipeline
    : nextentity(Entity)
    <- !run_entity(Entity).

// NO POSSIBLE PROGRESS
+!run_pipeline
    : not workflow_stopped
      & not workflow_completed
      & not running(_)
      & not nextentity(_)
    <- -workflow_active;
       +workflow_stopped;
       .print("Pipeline cannot make further progress.");
       !check_master_goal.

// ======================
// EXECUTE ENTITY
// ======================

// START COMPLETE YAML JOB

+!run_entity(Entity)
    : entity(Entity)
      & not running(Entity)
      & not terminal(Entity)
    <- ?run_sequence(Old);
       Attempt = Old + 1;
       -run_sequence(Old);
       +run_sequence(Attempt);
       ?attempt_count(Entity, PreviousAttempts);
       CurrentAttempts = PreviousAttempts + 1;
       -attempt_count(Entity, PreviousAttempts);
       +attempt_count(Entity, CurrentAttempts);
       -status(Entity, success);
       -status(Entity, fail);
       -status(Entity, _, _);
       -status(Entity, _);
       -duration(Entity, _);
       -duration(Entity, _, _);
       -success_handling(Entity);
       -phase_result(Entity, _);
       +running(Entity);
       +run_attempt(Entity, Attempt);
       .print("Running entity: ", Entity, ".");
       run_job(Entity).

// ======================
// OBSERVATIONS -> PHASE RESULTS
// ======================

// Generic normalized beliefs are bridged to the attempt-qualified beliefs
// used internally by this BDI program. This is representation adaptation,
// not workflow policy.
+status(Entity, success)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not status(Entity, Attempt, success)
    <- +status(Entity, Attempt, success).

+status(Entity, fail)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not status(Entity, Attempt, failure)
    <- +status(Entity, Attempt, failure).

+duration(Entity, Time)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not duration(Entity, Attempt, Time)
    <- +duration(Entity, Attempt, Time).

// SUCCESS WITHOUT DURATION REQUIREMENT
+status(Entity, Attempt, success)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not max_duration(Entity, _)
      & not success_handling(Entity)
      & not phase_result(Entity, success)
    <- +success_handling(Entity);
       +status(Entity, success);
       -phase_result(Entity, _);
       +phase_result(Entity, success).


// SUCCESS WITH DURATION REQUIREMENT

+status(Entity, Attempt, success)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & max_duration(Entity, _)
      & duration(Entity, _)
      & not success_handling(Entity)
      & not phase_result(Entity, success)
    <- +success_handling(Entity);
       +status(Entity, success);
       -phase_result(Entity, _);
       +phase_result(Entity, success).


// DURATION ARRIVES AFTER SUCCESS STATUS

+duration(Entity, Attempt, Time)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not status(Entity, Attempt, success)
      & not status(Entity, Attempt, failure)
      & status(Entity, fail)
    <- +duration(Entity, Time);
       +status(Entity, Attempt, failure).

+duration(Entity, Attempt, Time)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not status(Entity, Attempt, success)
      & status(Entity, Attempt, failure)
    <- +duration(Entity, Time).


+duration(Entity, Attempt, Time)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & status(Entity, Attempt, success)
      & max_duration(Entity, _)
      & not success_handling(Entity)
      & not phase_result(Entity, success)
    <- +success_handling(Entity);
       +duration(Entity, Time);
       -phase_result(Entity, _);
       +phase_result(Entity, success).

// FAILURE

+status(Entity, Attempt, failure)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not phase_result(Entity, fail)
    <- .print("Failure observation accepted: ", Entity, " attempt ", Attempt, ".");
       +status(Entity, failure);
       -phase_result(Entity, _);
       +phase_result(Entity, fail).

+status(Entity, Attempt, cancelled)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not phase_result(Entity, fail)
    <- +status(Entity, cancelled);
       -phase_result(Entity, _);
       +phase_result(Entity, fail).

+status(Entity, Attempt, skipped)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not phase_result(Entity, fail)
    <- +status(Entity, skipped);
       -phase_result(Entity, _);
       +phase_result(Entity, fail).

+status(Entity, Attempt, timeout)
    : running(Entity)
      & run_attempt(Entity, Attempt)
      & not phase_result(Entity, fail)
    <- +status(Entity, timeout);
       -phase_result(Entity, _);
       +phase_result(Entity, fail).


// ======================
// PHASE RESULT EVENTS
// ======================

// NORMAL ENTITY SUCCESS

+phase_result(Entity, success)
    : running(Entity)
      & not recovery_entity(Entity)
    <- -running(Entity);
       -run_attempt(Entity, _);
       .print(Entity, " completed successfully.");
       !maintain(Entity);
       !check_avoidance;

       !run_pipeline.

// NORMAL ENTITY FAILURE -> RETRY

+phase_result(Entity, fail)
    : running(Entity)
      & not recovery_entity(Entity)
      & retry_allowed(Entity)
    <- -running(Entity);
       -run_attempt(Entity, _);
       -phase_result(Entity, _);
       .print(Entity, " failed; retrying within configured retry budget.");
       !run_pipeline.

// NORMAL ENTITY FAILURE -> RECOVERY

+phase_result(Entity, fail)
    : running(Entity)
      & not recovery_entity(Entity)
      & not retry_allowed(Entity)
      & recovery(Entity, Recovery)
    <- -running(Entity);
       -run_attempt(Entity, _);
       +terminal(Entity, failed);
       .print(Entity, " failed; recovery = ", Recovery, ".");
       !recover(Entity).

// NORMAL ENTITY FAILURE -> STOP

+phase_result(Entity, fail)
    : running(Entity)
      & not recovery_entity(Entity)
      & not recovery(Entity, _)
    <- -running(Entity);
       -run_attempt(Entity, _);
       +terminal(Entity, failed);
       -workflow_active;
       +workflow_stopped;
       .print(Entity, " failed; workflow stopped.");
       !check_master_goal.

// RUNTIME FAILURE AFTER A PREVIOUSLY SUCCESSFUL EXECUTION
//
// Health telemetry is normalized to status(Entity, fail).  When the entity is
// no longer running, this is a runtime degradation rather than a new attempt
// result.  Recovery remains entirely data-driven by recovery/2.
+status(Entity, fail)
    : entity(Entity)
      & not recovery_entity(Entity)
      & not running(Entity)
      & not workflow_stopped
      & recovery(Entity, Recovery)
      & not terminal(Entity, runtime_failure)
    <- +terminal(Entity, runtime_failure);
       .print("Runtime failure detected for ", Entity, "; recovery = ", Recovery, ".");
       !recover(Entity).

// ======================
// RECOVERY
// ======================

// START RECOVERY

+!recover(Entity)
    : recovery(Entity, Recovery)
      & entity(Recovery)
      & not running(Recovery)
    <- ?run_sequence(Old);
       Attempt = Old + 1;
       -run_sequence(Old);
       +run_sequence(Attempt);
       ?attempt_count(Recovery, PreviousAttempts);
       CurrentAttempts = PreviousAttempts + 1;
       -attempt_count(Recovery, PreviousAttempts);
       +attempt_count(Recovery, CurrentAttempts);
       -status(Recovery, success);
       -status(Recovery, fail);
       -status(Recovery, _, _);
       -status(Recovery, _);
       -duration(Recovery, _);
       -duration(Recovery, _, _);
       -success_handling(Recovery);
       -phase_result(Recovery, _);
       +running(Recovery);
       +run_attempt(Recovery, Attempt);
       .print("Running recovery entity: ", Recovery, " for ", Entity, "." );
       run_job(Recovery).

// RECOVERY SUCCESS

+phase_result(Recovery, success)
    : running(Recovery)
      & recovery_entity(Recovery)
    <- -running(Recovery);
       -run_attempt(Recovery, _);

       +terminal(Recovery, recovered);

       -workflow_active;
       +workflow_stopped;

       .print(
           "Recovery completed successfully: ",
           Recovery,
           "."
       );

       !check_master_goal.

// RECOVERY FAILURE

+phase_result(Recovery, fail)
    : running(Recovery)
      & recovery_entity(Recovery)
    <- -running(Recovery);
       -run_attempt(Recovery, _);

       +terminal(Recovery, failed);

       -workflow_active;
       +workflow_stopped;

       .print(
           "Recovery failed: ",
           Recovery,
           "."
       );

       !check_master_goal.


// ======================
// MAINTENANCE
// ======================

// NO MAINTENANCE GOAL

+!maintain(Entity)
    : not max_duration(Entity, _)
    <- true.

// MAINTENANCE SATISFIED

+!maintain(Entity)
    : duration_ok(Entity, Time, Max)
    <- .print(
           "Maintenance satisfied: ",
           Entity,
           " duration ",
           Time,
           " <= ",
           Max,
           "."
       ).

// MAINTENANCE VIOLATED -> RECOVERY

+!maintain(Entity)
    : duration_violation(Entity, Time, Max)
      & recovery(Entity, Recovery)
    <- .print("Maintenance violated: ", Entity, " duration ", Time, " > ", Max, ".");
       -phase_result(Entity, success);
       +terminal(Entity, maintenance_violation);
       !recover(Entity).

// MAINTENANCE VIOLATED -> STOP

+!maintain(Entity)
    : duration_violation(Entity, Time, Max)
      & not recovery(Entity, _)
    <- .print("Maintenance violated for ", Entity, "; no recovery is available.");
       -phase_result(Entity, success);
       +terminal(Entity, maintenance_violation);

       -workflow_active;
       +workflow_stopped.

// ======================
// AVOIDANCE
// ======================

// AVOIDANCE SATISFIED
+!check_avoidance
    : not avoidance_violation(_)
    <- true.

// AVOIDANCE VIOLATION -> RECOVERY
+!check_avoidance
    : avoidance_violation(Entity)
      & recovery(Entity, Recovery)
    <- .print("Avoidance violation detected for ",
           Entity, ".");
       -phase_result(Entity, success);
       +terminal(Entity, avoidance_violation);
       !recover(Entity).

// AVOIDANCE VIOLATION -> STOP
+!check_avoidance
    : avoidance_violation(Entity)
      & not recovery(Entity, _)
    <- .print("Avoidance violation detected for ", Entity, "; no recovery is available.");
       -phase_result(Entity, success);
       +terminal(Entity, avoidance_violation);
       -workflow_active;
       +workflow_stopped.

// ======================
// MASTER GOAL ASSESSMENT
// ======================

achievement_satisfied(Entity, Desired) :-
    achievement(Entity, Desired)
    & phase_result(Entity, Desired).

achievement_unsatisfied(Entity, Desired) :-
    achievement(Entity, Desired)
    & not phase_result(Entity, Desired).

all_achievements_satisfied :-
    not achievement_unsatisfied(_, _).

maintenance_violation(Entity) :-
    duration_violation(Entity, _, _).

// ALL GOALS SATISFIED

+!check_master_goal
    : all_achievements_satisfied
      & not maintenance_violation(_)
      & not avoidance_violation(_)
    <- +master_goal_achieved;
       .print("Master goal achieved.").


// MASTER GOAL NOT SATISFIED

+!check_master_goal
    : not master_goal_achieved
    <- .print("Master goal not achieved.").
