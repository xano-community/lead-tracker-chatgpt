// User flow, as ChatGPT drives it: add a lead from the chat, move it by name, then see it on
// the board the panel reads.
workflow_test "lead_tracker_chatgpt_chat_flow" {
  tags = ["lead-tracker", "mcp", "e2e"]
  stack {
    tool.call add_lead {
      input = {name: "Jordan Flow Test", company: "Flowtest Inc", deal_value: 2500}
    } as $added
    expect.to_be_true ($added.saved)
    expect.to_equal ($added.lead.stage) {
      value = "New"
    }

    tool.call update_lead_stage {
      input = {lead_name: "Jordan Flow", stage: "Proposal"}
    } as $moved
    expect.to_be_true ($moved.saved)
    expect.to_equal ($moved.from_stage) {
      value = "New"
    }
    expect.to_equal ($moved.lead.stage) {
      value = "Proposal"
    }

    tool.call list_leads as $board
    expect.to_be_greater_than ($board.summary.by_stage.Proposal.value) {
      value = 2499
    }
  }
  guid = "ryy8ImoByesk1RrLtuJfwnIVSpY"
}
