// Lead Tracker for ChatGPT: a lead pipeline stored in Xano, served to ChatGPT over MCP.
workspace "Lead Tracker for ChatGPT" {
  acceptance = {ai_terms: false}
  preferences = {
    internal_docs    : false
    track_performance: true
    sql_names        : false
    sql_columns      : true
  }
}
---
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
---
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
---
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
---
// Shared write path for moving a lead between stages, found by id or by (part of) its name.
function "leads/move_stage" {
  description = "Move a lead (matched by id or name) to another pipeline stage."
  input {
    int lead_id? {
      description = "The lead's id, if known"
    }

    text lead_name? filters=trim {
      description = "The lead's name or part of it, e.g. Maya"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    // The caller has to say which lead to move
    precondition ($input.lead_id != null || ($input.lead_name|first_notempty:"") != "") {
      error_type = "inputerror"
      error = "Tell me which lead to move, by name or id."
    }

    db.query lead {
      description = "Find the lead by id and/or name; the most recently updated match wins"
      where = $db.lead.id ==? $input.lead_id && $db.lead.name includes? $input.lead_name
      sort = {updated_at: "desc"}
      return = {type: "single"}
    } as $current

    // Stop with a helpful message when nothing matches
    precondition ($current != null) {
      error_type = "notfound"
      error = "No matching lead was found. List the leads to see who is on the board."
    }

    db.patch lead {
      description = "Save the new stage and bump updated_at"
      field_name = "id"
      field_value = $current.id
      data = {stage: $input.stage, updated_at: now}
    } as $lead
  }

  response = {lead: $lead, from_stage: $current.stage}

  test "needs a lead id or name" {
    input = {stage: "Won"}
    expect.to_throw {
      exception = "Tell me which lead to move, by name or id."
    }
  }

  test "unknown lead is not found" {
    input = {lead_name: "Nobody Matches This Name", stage: "Won"}
    expect.to_throw {
      exception = "No matching lead was found. List the leads to see who is on the board."
    }
  }
  guid = "pWBui07Ct6U-IDQVjT6UR8zHWWM"
}
---
// Pure rollup of a list of leads: totals overall and per stage. No database access.
function "leads/pipeline_summary" {
  description = "Count leads and sum deal value overall and per pipeline stage."
  input {
    json leads? {
      description = "Array of lead records (each with stage and deal_value)"
    }
  }

  stack {
    var $stages {
      description = "Per-stage buckets in pipeline order"
      value = {
        New      : {count: 0, value: 0}
        Qualified: {count: 0, value: 0}
        Proposal : {count: 0, value: 0}
        Won      : {count: 0, value: 0}
      }
    }

    var $total_value {
      description = "Running sum of every lead's deal value"
      value = 0
    }

    foreach ($input.leads|first_notempty:[]) {
      description = "Add each lead to its stage bucket and the overall total"
      each as $l {
        var $bucket {
          description = "The stage bucket this lead belongs to (New if missing)"
          value = $l.stage|first_notempty:"New"
        }

        var $amount {
          description = "This lead's deal value, treating a blank value as 0"
          value = $l.deal_value|first_notempty:0
        }

        var.update $stages {
          description = "Increment the bucket's count and value"
          value = $stages
            |set:$bucket:{count: ($stages|get:$bucket|get:"count") + 1, value: ($stages|get:$bucket|get:"value") + $amount}
        }

        var.update $total_value {
          description = "Add the deal value to the overall total"
          value = $total_value + $amount
        }
      }
    }
  }

  response = {
    total_leads: $input.leads|first_notempty:[]|count
    total_value: $total_value
    won_value  : $stages.Won.value
    open_value : $total_value - $stages.Won.value
    by_stage   : $stages
  }

  test "empty board sums to zero" {
    input = {leads: []}
    expect.to_equal ($response.total_leads) {
      value = 0
    }

    expect.to_equal ($response.total_value) {
      value = 0
    }
  }

  test "rolls leads up by stage" {
    input = {
      leads: [
        {stage: "New", deal_value: 3100}
        {stage: "New", deal_value: 900}
        {stage: "Proposal", deal_value: 4800}
        {stage: "Won", deal_value: 6500}
      ]
    }

    expect.to_equal ($response.total_leads) {
      value = 4
    }

    expect.to_equal ($response.total_value) {
      value = 15300
    }

    expect.to_equal ($response.won_value) {
      value = 6500
    }

    expect.to_equal ($response.open_value) {
      value = 8800
    }

    expect.to_equal ($response.by_stage.New.count) {
      value = 2
    }

    expect.to_equal ($response.by_stage.Qualified.count) {
      value = 0
    }
  }

  test "blank deal value counts as zero" {
    input = {leads: [{stage: "Qualified", deal_value: null}]}
    expect.to_equal ($response.by_stage.Qualified.count) {
      value = 1
    }

    expect.to_equal ($response.total_value) {
      value = 0
    }
  }
  guid = "x6qSNTEuI-rDMo8SNnDXUheCj3M"
}
---
// REST access to the same leads the ChatGPT app reads and writes.
api_group LeadTracker {
  description = "REST API for the Lead Tracker: read the board, add and move leads, load demo data."
  tags = ["crm", "chatgpt"]
  guid = "HH7XAFgux9zXv4mXL-BeqNow9VM"
}
---
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
---
// POST /leads - add a lead.
query "leads" verb=POST {
  api_group = "LeadTracker"
  description = "Add a new lead (stage defaults to New)."

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
    function.run "leads/add" {
      description = "Validate and insert the lead"
      input = {name: $input.name, company: $input.company, deal_value: $input.deal_value, stage: $input.stage}
    } as $lead
  }

  response = $lead
  guid = "0B1jrYHK8oJbLi3Ib0h2HVTYEns"
}
---
// PATCH /leads/{lead_id}/stage - move a lead to another stage.
query "leads/{lead_id}/stage" verb=PATCH {
  api_group = "LeadTracker"
  description = "Move a lead to another pipeline stage."

  input {
    int lead_id {
      description = "The lead to move"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/move_stage" {
      description = "Move the lead and record the previous stage"
      input = {lead_id: $input.lead_id, stage: $input.stage}
    } as $moved
  }

  response = $moved
  guid = "Odpsfb-513cqqSMdSUZLvfPxv1A"
}
---
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
---
// Lead Tracker: a CRM inside ChatGPT. Data, logic, and the MCP server all run on Xano.
mcp_server "Lead Tracker" {
  description = "ChatGPT app: tools and the board panel for the lead table"
  instructions = """
    Lead Tracker is a simple CRM. Leads have a name, company, deal value and a stage: New, Qualified, Proposal or Won.
    - To show or set up the CRM, call open_lead_tracker.
    - To add a lead, call add_lead. To move one, call update_lead_stage with the lead's name.
    - Only say a lead was saved after the tool returns saved=true.
    - The open Lead Tracker panel updates itself from Xano, so after add_lead or update_lead_stage just confirm in one short sentence. Do not reopen the panel.
    """
  tags = ["chatgpt", "crm"]
  tools = [
    {name: "open_lead_tracker", tool_meta: "{\"ui\":{\"resourceUri\":\"ui://lead-tracker/panel-v1.html\"},\"openai/outputTemplate\":\"ui://lead-tracker/panel-v1.html\",\"openai/widgetAccessible\":true}"}
    {name: "list_leads", tool_meta: "{\"openai/widgetAccessible\":true}"}
    {name: "add_lead", tool_meta: "{\"openai/widgetAccessible\":true}"}
    {name: "update_lead_stage", tool_meta: "{\"openai/widgetAccessible\":true}"}
    {name: "lead_tracker_panel", type: "resource", resource_uri: "ui://lead-tracker/panel-v1.html"}
  ]
  guid = "plFJfcxcqaAZxw2fb5jGGALucMs"
}
---
// Saves a new lead. Text-only (no output template): an open panel picks the change up on its next poll.
tool "add_lead" {
  description = "Add a new lead to the Lead Tracker."
  instructions = "Add a new lead to the Lead Tracker. Use when the user names a person or company to track. Stage defaults to New. The lead is only saved once this tool returns saved=true."

  input {
    text name filters=trim {
      description = "Contact name, e.g. Maya Chen"
    }

    text company? filters=trim {
      description = "Company the contact works for"
    }

    decimal deal_value? {
      description = "Deal value in US dollars, e.g. 4800"
    }

    enum stage?=New {
      description = "Pipeline stage"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/add" {
      description = "Validate and insert the lead"
      input = {name: $input.name, company: $input.company, deal_value: $input.deal_value, stage: $input.stage}
    } as $lead

    function.run "leads/list" {
      description = "Return the updated board so a host can re-render it"
    } as $board
  }

  response = {action: "add", saved: true, lead: $lead, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "m58icxnwjlHhQuH4CRmahi1M1tg"
}
---
// The Lead Tracker panel, served to ChatGPT as an MCP App resource. The HTML is fetched from
// PANEL_URL (any public URL serving frontend/panel.html); it defaults to this template's GitHub copy.
tool "lead_tracker_panel" {
  description = "MCP resource: the Lead Tracker panel HTML ChatGPT renders in the conversation."
  instructions = "The Lead Tracker panel (HTML) that ChatGPT renders next to the conversation."

  input {
  }

  stack {
    var $panel_url {
      description = "Where to fetch the built panel from: PANEL_URL if set, else the template's public copy"
      value = $env.PANEL_URL
        |first_notempty:"https://raw.githubusercontent.com/xano-community/lead-tracker-chatgpt/main/frontend/panel.html"
    }

    api.request {
      description = "Fetch the panel HTML"
      url = $panel_url
      method = "GET"
      timeout = 15
    } as $page

    // Tell the operator what to fix rather than returning a broken resource
    precondition ($page.response.status == 200) {
      error_type = "standard"
      error = "The Lead Tracker panel couldn't be loaded. Check that PANEL_URL points to a public copy of panel.html."
    }

    var $panel {
      description = "The MCP App resource: URI, MIME type, HTML, and display hints"
      value = {
        uri     : "ui://lead-tracker/panel-v1.html"
        mimeType: "text/html;profile=mcp-app"
        text    : $page.response.result
        _meta   : {ui: {prefersBorder: true}, "openai/widgetPrefersBorder": true, "openai/widgetDescription": "Lead Tracker board: every lead by stage, saved in Xano."}
      }
    }
  }

  response = $panel
  guid = "pDBw3Ia_p3RnPqTJMBXXwW5o6jc"
}
---
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
---
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
---
// Moves a lead to another stage, found by name (or id). The panel's stage dropdown calls this too.
tool "update_lead_stage" {
  description = "Move an existing lead to another pipeline stage."
  instructions = "Move an existing lead to another stage (New, Qualified, Proposal, Won). Pass the lead's name as the user said it, e.g. 'Maya'. The move is only saved once this tool returns saved=true."

  input {
    text lead_name? filters=trim {
      description = "Name of the lead to move, e.g. Maya or Maya Chen"
    }

    int lead_id? {
      description = "Optional: the lead's id, if known"
    }

    enum stage {
      description = "The stage to move the lead to"
      values = ["New", "Qualified", "Proposal", "Won"]
    }
  }

  stack {
    function.run "leads/move_stage" {
      description = "Find the lead and save its new stage"
      input = {lead_id: $input.lead_id, lead_name: $input.lead_name, stage: $input.stage}
    } as $moved

    function.run "leads/list" {
      description = "Return the updated board so a host can re-render it"
    } as $board
  }

  response = {action: "move", saved: true, lead: $moved.lead, from_stage: $moved.from_stage, leads: $board.leads, summary: $board.summary, source: "xano"}
  guid = "0qb66npXmAPpDYj9IZNSr_57BRc"
}
---
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
---
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
---
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
