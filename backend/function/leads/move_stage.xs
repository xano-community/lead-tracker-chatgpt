// Shared write path for moving a lead between stages, found by id or by (part of) its name.
function "leads/move_stage" {
  description = "Move a lead (matched by id or name) to another pipeline stage."
  input {
    int lead_id? {
      description = "The lead's id, if known"
    }

    text lead_name? filters=trim {
      description = "The lead's name or part of it, e.g. Maya"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    // The caller has to say which lead to move
    precondition ($input.lead_id != null || ($input.lead_name|first_notempty:"") != "") {
      error_type = "inputerror"
      error = "Tell me which lead to move, by name or id."
    }

    db.query lead {
      description = "Find the lead by id and/or name; the most recently updated match wins"
      where = $db.lead.id ==? $input.lead_id && $db.lead.name includes? $input.lead_name
      sort = {updated_at: "desc"}
      return = {type: "single"}
    } as $current

    // Stop with a helpful message when nothing matches
    precondition ($current != null) {
      error_type = "notfound"
      error = "No matching lead was found. List the leads to see who is on the board."
    }

    db.patch lead {
      description = "Save the new stage and bump updated_at"
      field_name = "id"
      field_value = $current.id
      data = {stage: $input.stage, updated_at: now}
    } as $lead
  }

  response = {lead: $lead, from_stage: $current.stage}

  test "needs a lead id or name" {
    input = {stage: "Won"}
    expect.to_throw {
      exception = "Tell me which lead to move, by name or id."
    }
  }

  test "unknown lead is not found" {
    input = {lead_name: "Nobody Matches This Name", stage: "Won"}
    expect.to_throw {
      exception = "No matching lead was found. List the leads to see who is on the board."
    }
  }
  guid = "pWBui07Ct6U-IDQVjT6UR8zHWWM"
}
