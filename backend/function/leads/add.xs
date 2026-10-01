// Shared write path for adding a lead (used by the add_lead tool, POST /leads, and the tests).
function "leads/add" {
  description = "Validate and insert a new lead, defaulting the stage to New."
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
    // A lead must have a contact name
    precondition (($input.name|first_notempty:"") != "") {
      error_type = "inputerror"
      error = "Please give the lead a name, for example \"Maya Chen\"."
    }

    // Deal values can't be negative
    precondition (($input.deal_value|first_notempty:0) >= 0) {
      error_type = "inputerror"
      error = "The deal value can't be negative. Enter an amount in US dollars, like 4800."
    }

    db.add lead {
      description = "Insert the lead"
      data = {
        name      : $input.name
        company   : $input.company
        deal_value: $input.deal_value
        stage     : $input.stage|first_notempty:"New"
        updated_at: now
      }
    } as $lead
  }

  response = $lead

  test "adds a lead in the New stage by default" {
    input = {name: "Unit Test Lead", company: "Testco", deal_value: 1200}
    expect.to_equal ($response.stage) {
      value = "New"
    }

    expect.to_equal ($response.name) {
      value = "Unit Test Lead"
    }
  }

  test "rejects a lead with no name" {
    input = {name: "", company: "Testco"}
    expect.to_throw {
      exception = "Please give the lead a name, for example \"Maya Chen\"."
    }
  }

  test "rejects a negative deal value" {
    input = {name: "Negative Nell", deal_value: -5}
    expect.to_throw {
      exception = "The deal value can't be negative. Enter an amount in US dollars, like 4800."
    }
  }
  guid = "YYGQh8E_pL3egOTQMeMQxnG_0NQ"
}
