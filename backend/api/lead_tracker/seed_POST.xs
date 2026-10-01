// POST /seed - load the demo board. Idempotent: each demo lead is matched by name and only
// inserted when missing, so calling it twice never duplicates rows.
query "seed" verb=POST {
  api_group = "LeadTracker"
  description = "Load six demo leads across every stage. Safe to call more than once."

  input {
  }

  stack {
    var $demo {
      description = "Demo leads: at least one in every stage so the board and totals look real"
      value = [
        {name: "Sam Okafor", company: "Harbor Labs", deal_value: 3100, stage: "New"}
        {name: "Priya Shah", company: "Cedar & Pine Interiors", deal_value: 1800, stage: "New"}
        {name: "Leo Park", company: "Brightline Dental", deal_value: 2200, stage: "Qualified"}
        {name: "Maya Chen", company: "Northwind Analytics", deal_value: 4800, stage: "Proposal"}
        {name: "Tom Becker", company: "Fieldstone Logistics", deal_value: 9200, stage: "Proposal"}
        {name: "Ana Ruiz", company: "Kiln & Co", deal_value: 6500, stage: "Won"}
      ]
    }

    var $inserted {
      description = "How many demo leads this call added"
      value = 0
    }

    foreach ($demo) {
      description = "Insert each demo lead unless one with the same name already exists"
      each as $d {
        db.query lead {
          description = "Look for an existing lead with this exact name"
          where = $db.lead.name == $d.name
          return = {type: "exists"}
        } as $exists

        // Only add the lead when it's missing
        conditional {
          if ($exists == false) {
            db.add lead {
              description = "Insert the demo lead"
              data = {
                name      : $d.name
                company   : $d.company
                deal_value: $d.deal_value
                stage     : $d.stage
                updated_at: now
              }
            }

            var.update $inserted {
              description = "Count the insert"
              value = $inserted + 1
            }
          }
        }
      }
    }

    db.query lead {
      description = "Total leads on the board after seeding"
      return = {type: "count"}
    } as $total
  }

  response = {seeded: true, inserted: $inserted, total: $total}
  guid = "Snb3eJZ9Z6zQUm1PIadFMkgTZXc"
}
