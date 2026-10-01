// Opens the Lead Tracker panel in ChatGPT, pre-loaded with every saved lead.
tool "open_lead_tracker" {
  description = "Open the Lead Tracker board in ChatGPT with every saved lead."
  instructions = "Open the Lead Tracker CRM panel and show every saved lead by stage (New, Qualified, Proposal, Won). Use when the user wants to see, open, or set up their CRM or lead tracker. The panel renders the board; summarize it in one short sentence."

  input {
  }

  stack {
    function.run "leads/list" {
      description = "Load the board the panel renders"
    } as $board
  }

  response = {action: "list", saved: false, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "dPxvinHOvszotXq1CGdfrSoMN20"
}
