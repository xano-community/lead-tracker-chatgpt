// Saves a new lead. Text-only (no output template): an open panel picks the change up on its next poll.
tool "add_lead" {
  description = "Add a new lead to the Lead Tracker."
  instructions = "Add a new lead to the Lead Tracker. Use when the user names a person or company to track. Stage defaults to New. The lead is only saved once this tool returns saved=true."

  input {
    text name filters=trim {
      description = "Contact name, e.g. Maya Chen"
    }

    text company? filters=trim {
      description = "Company the contact works for"
    }

    decimal deal_value? {
      description = "Deal value in US dollars, e.g. 4800"
    }

    enum stage?=New {
      description = "Pipeline stage"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/add" {
      description = "Validate and insert the lead"
      input = {name: $input.name, company: $input.company, deal_value: $input.deal_value, stage: $input.stage}
    } as $lead

    function.run "leads/list" {
      description = "Return the updated board so a host can re-render it"
    } as $board
  }

  response = {action: "add", saved: true, lead: $lead, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "m58icxnwjlHhQuH4CRmahi1M1tg"
}
