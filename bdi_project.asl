// Generated from 03_workflow_model.yaml; do not edit.

entity(build).
entity(test).
entity(security).
entity(staging).
entity(production).
entity(rollback_production).
recovery_entity(rollback_production).

depends(build, []).
depends(test, [build]).
depends(security, [test]).
depends(staging, [security]).
depends(production, [staging]).

recovery(production, rollback_production).
final_phase(production).

achievement(production, success).
achievement(staging, success).
max_duration(production, 100000).
avoid_missing(production, test).
avoid_missing(production, staging).

duration_unit(milliseconds).
max_retries(1).

// Controller-derived attempt counters.
attempt_count(build, 0).
attempt_count(test, 0).
attempt_count(security, 0).
attempt_count(staging, 0).
attempt_count(production, 0).
attempt_count(rollback_production, 0).
