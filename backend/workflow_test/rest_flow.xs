// User flow, as the web board drives it: add a lead over REST, move it by id, and reject a
// move for a lead that doesn't exist.
workflow_test "lead_tracker_chatgpt_rest_flow" {
  tags = ["lead-tracker", "rest", "e2e"]
  stack {
    api.call leads verb=POST {
      api_group = "LeadTracker"
      input = {name: "Riley Rest Test", company: "Resty LLC", deal_value: 700}
    } as $lead
    expect.to_equal ($lead.stage) {
      value = "New"
    }

    function.call "leads/move_stage" {
      input = {lead_id: $lead.id, stage: "Won"}
    } as $moved
    expect.to_equal ($moved.lead.stage) {
      value = "Won"
    }

    expect.to_throw {
      stack {
        function.call "leads/move_stage" {
          input = {lead_name: "Definitely Not A Lead", stage: "Won"}
        } as $missing
      }
      exception = "No matching lead was found. List the leads to see who is on the board."
    }
  }
  guid = "Ug7lG0nQbilPQKvoPMRWaaiuiZk"
}
