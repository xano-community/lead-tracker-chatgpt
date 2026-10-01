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
