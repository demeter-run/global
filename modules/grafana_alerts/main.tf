resource "grafana_folder" "this" {
  for_each = { for folder in var.folders : folder.title => folder if folder.uid == "" }
  title    = each.key
}

resource "grafana_rule_group" "this" {
  for_each = {
    for file in fileset("${path.root}/../${var.local_directory}", "*.json") :
    file => jsondecode(templatefile("${path.root}/../${var.local_directory}/${file}", {
      datasource_uid_map = var.datasource_uids
    }))
  }

  name             = each.value["groups"][0]["name"]
  folder_uid       = var.folder_uid
  interval_seconds = var.default_interval_seconds

  dynamic "rule" {
    for_each = flatten([
      for group in each.value["groups"] : group["rules"]
    ])

    content {
      name      = rule.value["title"]
      condition = rule.value["condition"]
      for       = try(rule.value["for"], "0s")
      dynamic "data" {
        for_each = rule.value["data"]
        content {
          ref_id         = data.value["refId"]
          datasource_uid = data.value["datasourceUid"]
          model          = jsonencode(data.value["model"])
          relative_time_range {
            from = data.value["relativeTimeRange"]["from"]
            to   = data.value["relativeTimeRange"]["to"]
          }
        }
      }
      no_data_state  = rule.value["noDataState"]
      exec_err_state = rule.value["execErrState"]
      annotations    = rule.value["annotations"]
      labels         = lookup(rule.value, "labels", {})
      notification_settings {
        contact_point = rule.value["notification_settings"]["receiver"]
      }
    }
  }
}

