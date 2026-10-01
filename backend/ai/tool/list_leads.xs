// Returns every saved lead. The panel calls this when it opens, refreshes, and polls.
tool "list_leads" {
  description = "List every saved lead with the per-stage pipeline summary."
  instructions = "List every lead saved in the Lead Tracker, oldest first, with name, company, deal value and stage, plus pipeline totals per stage."

  input {
  }

  stack {
    function.run "leads/list" {
      description = "Load every lead and the stage rollup"
    } as $board
  }

  response = {action: "list", saved: false, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "35fY1uLyIuZUhBWDTkmpt2kM2fo"
}
