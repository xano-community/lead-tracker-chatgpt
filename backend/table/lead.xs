// A sales lead tracked on the Lead Tracker board.
table lead {
  auth = false
  description = "A sales lead: contact, company, deal value, and its pipeline stage."

  schema {
    int id
    timestamp created_at?=now

    text name filters=trim {
      description = "Contact name, e.g. Maya Chen"
    }

    text company? filters=trim {
      description = "Company the contact works for"
    }

    decimal deal_value? {
      description = "Opportunity size in US dollars"
    }

    enum stage?=New {
      description = "Where the deal sits in the pipeline"
      values = ["New", "Qualified", "Proposal", "Won"]
    }

    timestamp updated_at?=now {
      description = "When the lead was last added or moved"
    }
  }

  index = [
    {type: "primary", field: [{name: "id"}]}
    {type: "btree", field: [{name: "stage"}]}
    {type: "btree", field: [{name: "name"}]}
    {type: "btree", field: [{name: "created_at", op: "desc"}]}
  ]
  guid = "jr-_UBTzB43JlQJZlfJnd4qH5i8"
}
