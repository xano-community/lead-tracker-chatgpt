// Outcome: loading the demo data produces a populated board with every stage represented and
// correct dollar totals, and the seed is idempotent.
workflow_test "lead_tracker_chatgpt_seeded_board" {
  tags = ["lead-tracker", "seed", "e2e"]
  stack {
    api.call seed verb=POST {
      api_group = "LeadTracker"
    } as $first
    expect.to_be_true ($first.seeded)

    api.call seed verb=POST {
      api_group = "LeadTracker"
    } as $second
    expect.to_equal ($second.inserted) {
      value = 0
    }
    expect.to_equal ($second.total) {
      value = $first.total
    }

    api.call leads verb=GET {
      api_group = "LeadTracker"
    } as $board
    expect.to_be_greater_than ($board.summary.total_leads) {
      value = 5
    }
    expect.to_be_greater_than ($board.summary.by_stage.New.count) {
      value = 0
    }
    expect.to_be_greater_than ($board.summary.by_stage.Qualified.count) {
      value = 0
    }
    expect.to_be_greater_than ($board.summary.by_stage.Proposal.count) {
      value = 0
    }
    expect.to_be_greater_than ($board.summary.by_stage.Won.value) {
      value = 6499
    }
  }
  guid = "qA1Rvnvjvq72cVb440xw6eOBFtg"
}
