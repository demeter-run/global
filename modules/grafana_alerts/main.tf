locals {
  alert_files = fileset("${path.root}/${var.local_directory}", "*.json")
}

# Create the folder that the alert rule groups live in. Grafana requires the
# folder to exist before rule groups can be provisioned into it, so we manage it
# here with the UID defined in config.yaml (mirroring the grafana_dashboard
# module, which also creates its own folder). Only created when the directory
# actually contains alert definitions, so an empty/missing directory is a no-op.
resource "grafana_folder" "this" {
  count = length(local.alert_files) > 0 ? 1 : 0
  title = var.folder_title
  uid   = var.folder_uid
}

resource "grafana_rule_group" "this" {
  for_each = {
    for file in local.alert_files :
    file => jsondecode(templatefile("${path.root}/${var.local_directory}/${file}", {
      datasource_uid_map = var.datasource_uids
    }))
  }

  name             = each.value["groups"][0]["name"]
  folder_uid       = grafana_folder.this[0].uid
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

