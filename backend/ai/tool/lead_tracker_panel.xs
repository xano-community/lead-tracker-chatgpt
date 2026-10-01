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
