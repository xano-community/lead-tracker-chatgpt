// PATCH /leads/{lead_id}/stage - move a lead to another stage.
query "leads/{lead_id}/stage" verb=PATCH {
  api_group = "LeadTracker"
  description = "Move a lead to another pipeline stage."

  input {
    int lead_id {
      description = "The lead to move"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/move_stage" {
      description = "Move the lead and record the previous stage"
      input = {lead_id: $input.lead_id, stage: $input.stage}
    } as $moved
  }

  response = $moved
  guid = "Odpsfb-513cqqSMdSUZLvfPxv1A"
}
