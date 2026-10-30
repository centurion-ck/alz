# Azure Monitor Private Link Scope (AMPLS) for the Bidaya platform, deployed in the Connectivity subscription.
#
# This file only adds resources. It reuses what the platform already creates:
#   - provider alias azurerm.connectivity
#   - ampls resource group (ampls_resource_group_name, created by module.resource_groups
#     from connectivity_resource_groups.ampls)
#   - hub VNet and its resource group
#   - private endpoint subnet snet-pe-hub-conn-prd-bidaya-aen-01 (172.20.65.0/27), created by the hub module
#     from hub_virtual_networks.primary.hub_virtual_network.subnets.private_endpoints
#   - Private Link private DNS zones in the dns resource group (created by module.hub_and_spoke_vnet)
#   - Log Analytics workspace in the Management subscription (log_analytics_workspace_id,
#     created by module.management_resources)
# Nothing in the existing files is changed or overridden.
#
# Bidaya specification applied here:
#   - Resource group   rg-ampls-hub-conn-prd-bidaya-aen-01
#   - AMPLS            ampls-hub-conn-prd-bidaya-aen-01
#   - Private endpoint pep-ampls-hub-conn-prd-bidaya-aen-01
#   - Access mode      to be confirmed (Open or PrivateOnly), currently Open

locals {
  ampls_settings = {
    name                  = "ampls-hub-conn-prd-bidaya-aen-01"
    scoped_service_name   = "scoped-log-mgmt-prd-bidaya-aen-01"
    private_endpoint_name = "pep-ampls-hub-conn-prd-bidaya-aen-01"
    connection_name       = "psc-ampls-hub-conn-prd-bidaya-aen-01"
    dns_zone_group_name   = "dzg-ampls-hub-conn-prd-bidaya-aen-01"
    subnet_name           = "snet-pe-hub-conn-prd-bidaya-aen-01"

    # Transitional setting pending Bidaya security approval.
    # Open allows private-link access AND access to Azure Monitor resources outside this AMPLS
    # when those resources accept public traffic. It is not a private-only boundary.
    # Change to PrivateOnly only after all required workspaces/components and required DCEs
    # are linked to this AMPLS and DNS, AMA ingestion, and Log Analytics query paths are tested.
    ingestion_access_mode = "Open"
    query_access_mode     = "Open"

    dns_zone_names = [
      "privatelink.monitor.azure.com",
      "privatelink.oms.opinsights.azure.com",
      "privatelink.ods.opinsights.azure.com",
      "privatelink.agentsvc.azure-automation.net",
      "privatelink.blob.core.windows.net",
    ]

    resource_group_name        = module.config.outputs.custom_replacements["ampls_resource_group_name"]
    dns_resource_group_name    = module.config.outputs.custom_replacements["dns_resource_group_name"]
    location                   = module.config.outputs.custom_replacements["starter_location_01"]
    vnet_resource_group_name   = module.config.outputs.custom_replacements["connectivity_hub_primary_resource_group_name"]
    vnet_name                  = module.config.outputs.custom_replacements["primary_virtual_network_name"]
    log_analytics_workspace_id = module.config.outputs.custom_replacements["log_analytics_workspace_id"]
    tags                       = coalesce(module.config.outputs.connectivity_tags, module.config.outputs.tags)
  }
}

# Private DNS zone and subnet IDs are built deterministically (see locals.ids.tf) instead of read with
# data sources that use depends_on, which can force the private endpoint to be recreated.
locals {
  ampls_dns_zone_ids = [
    for name in local.ampls_settings.dns_zone_names :
    "/subscriptions/${local.connectivity_subscription_id}/resourceGroups/${local.ampls_settings.dns_resource_group_name}/providers/Microsoft.Network/privateDnsZones/${name}"
  ]
}

resource "azurerm_monitor_private_link_scope" "ampls" {
  provider = azurerm.connectivity

  name                  = local.ampls_settings.name
  resource_group_name   = local.ampls_settings.resource_group_name
  ingestion_access_mode = local.ampls_settings.ingestion_access_mode
  query_access_mode     = local.ampls_settings.query_access_mode
  tags                  = local.ampls_settings.tags

  depends_on = [module.resource_groups]
}

# Attach the platform Log Analytics workspace (Management subscription) to the scope.
resource "azurerm_monitor_private_link_scoped_service" "log_analytics" {
  provider = azurerm.connectivity

  name                = local.ampls_settings.scoped_service_name
  resource_group_name = local.ampls_settings.resource_group_name
  scope_name          = azurerm_monitor_private_link_scope.ampls.name
  linked_resource_id  = local.ampls_settings.log_analytics_workspace_id

  depends_on = [module.management_resources]
}

resource "azurerm_private_endpoint" "ampls" {
  provider = azurerm.connectivity

  name                = local.ampls_settings.private_endpoint_name
  resource_group_name = local.ampls_settings.resource_group_name
  location            = local.ampls_settings.location
  subnet_id           = local.hub_subnet_ids.private_endpoints
  tags                = local.ampls_settings.tags

  private_service_connection {
    name                           = local.ampls_settings.connection_name
    private_connection_resource_id = azurerm_monitor_private_link_scope.ampls.id
    subresource_names              = ["azuremonitor"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = local.ampls_settings.dns_zone_group_name
    private_dns_zone_ids = local.ampls_dns_zone_ids
  }

  depends_on = [
    azurerm_monitor_private_link_scoped_service.log_analytics,
    module.hub_and_spoke_vnet,
  ]
}

output "ampls_resource_id" {
  value = azurerm_monitor_private_link_scope.ampls.id
}

output "ampls_private_endpoint_resource_id" {
  value = azurerm_private_endpoint.ampls.id
}
