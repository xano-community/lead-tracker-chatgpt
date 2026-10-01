// Read the whole board: every lead (oldest first) plus the per-stage rollup.
function "leads/list" {
  description = "Return every lead, oldest first, with the per-stage pipeline summary."
  input {
  }

  stack {
    db.query lead {
      description = "Load every lead, oldest first, so cards keep a stable order"
      sort = {created_at: "asc"}
      return = {type: "list"}
    } as $leads

    function.run "leads/pipeline_summary" {
      description = "Roll the leads up into counts and dollar totals per stage"
      input = {leads: $leads}
    } as $summary
  }

  response = {leads: $leads, summary: $summary}
  guid = "n8ix_mLBdO_1hAovyxQeEEcTpSU"
}
