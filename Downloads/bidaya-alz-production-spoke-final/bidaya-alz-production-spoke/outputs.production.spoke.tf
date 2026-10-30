output "production_spoke_resource_group_id" {
  description = "Resource ID of the Production spoke resource group."
  value       = azurerm_resource_group.production_spoke.id
}

output "production_spoke_vnet_id" {
  description = "Resource ID of the Production spoke VNet."
  value       = azurerm_virtual_network.production_spoke.id
}

output "production_spoke_subnet_id" {
  description = "Resource ID of the initial Production workload subnet."
  value       = azurerm_subnet.production_workload.id
}

output "production_spoke_to_hub_peering_state" {
  description = "Provisioned state of the Production-to-Hub peering."
  value       = azurerm_virtual_network_peering.production_to_hub.id
}

output "hub_to_production_spoke_peering_state" {
  description = "Provisioned state of the Hub-to-Production peering."
  value       = azurerm_virtual_network_peering.hub_to_production.id
}
