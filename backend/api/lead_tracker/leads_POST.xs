// POST /leads - add a lead.
query "leads" verb=POST {
  api_group = "LeadTracker"
  description = "Add a new lead (stage defaults to New)."

  input {
    text name? filters=trim {
      description = "Contact name (required)"
    }

    text company? filters=trim {
      description = "Company the contact works for"
    }

    decimal deal_value? {
      description = "Deal value in US dollars"
    }

    enum stage?=New {
      description = "Starting pipeline stage"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/add" {
      description = "Validate and insert the lead"
      input = {name: $input.name, company: $input.company, deal_value: $input.deal_value, stage: $input.stage}
    } as $lead
  }

  response = $lead
  guid = "0B1jrYHK8oJbLi3Ib0h2HVTYEns"
}
