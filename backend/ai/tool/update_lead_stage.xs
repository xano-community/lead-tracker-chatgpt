// Moves a lead to another stage, found by name (or id). The panel's stage dropdown calls this too.
tool "update_lead_stage" {
  description = "Move an existing lead to another pipeline stage."
  instructions = "Move an existing lead to another stage (New, Qualified, Proposal, Won). Pass the lead's name as the user said it, e.g. 'Maya'. The move is only saved once this tool returns saved=true."

  input {
    text lead_name? filters=trim {
      description = "Name of the lead to move, e.g. Maya or Maya Chen"
    }

    int lead_id? {
      description = "Optional: the lead's id, if known"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/move_stage" {
      description = "Find the lead and save its new stage"
      input = {lead_id: $input.lead_id, lead_name: $input.lead_name, stage: $input.stage}
    } as $moved

    function.run "leads/list" {
      description = "Return the updated board so a host can re-render it"
    } as $board
  }

  response = {action: "move", saved: true, lead: $moved.lead, from_stage: $moved.from_stage, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "0qb66npXmAPpDYj9IZNSr_57BRc"
}
