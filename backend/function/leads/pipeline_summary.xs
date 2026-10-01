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
