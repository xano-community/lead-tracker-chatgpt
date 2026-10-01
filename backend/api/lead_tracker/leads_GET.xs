// GET /leads - the board: every lead plus the per-stage summary.
query "leads" verb=GET {
  api_group = "LeadTracker"
  description = "Every lead, oldest first, with the per-stage pipeline summary."

  input {
  }

  stack {
    function.run "leads/list" {
      description = "Load the board"
    } as $board
  }

  response = $board
  guid = "uKSymntB0g0QtNtlCHi-kVRmQDQ"
}
