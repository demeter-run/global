resource "grafana_data_source" "this" {
  for_each                               = var.data_sources
  name                                   = each.value.name
  type                                   = each.value.type
  url                                    = each.value.url
  private_data_source_connect_network_id = each.value.pdc
}
