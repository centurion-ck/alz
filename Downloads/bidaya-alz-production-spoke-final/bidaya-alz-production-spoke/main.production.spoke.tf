# Bidaya Production spoke VNet. This is additive: the existing Platform Hub deployment is not modified.
# The approved Production /24 is a required input (production_spoke_address_space); do not guess it.

locals {
  production_spoke_resource_group_name = "rg-net-spoke-prod-bidaya-aen-01"
  production_spoke_vnet_name           = "vnet-spoke-prod-bidaya-aen-01"
  production_spoke_subnet_name         = "snet-workload-prod-bidaya-aen-01"
  production_spoke_nsg_name            = "nsg-workload-prod-bidaya-aen-01"
  production_spoke_route_table_name    = "rt-workload-prod-bidaya-aen-01"
  production_spoke_dns_servers         = ["172.20.64.164"] # hub DNS Private Resolver inbound endpoint
}

resource "azurerm_resource_group" "production_spoke" {
  provider = azurerm.production

  name     = local.production_spoke_resource_group_name
  location = module.config.outputs.management_group_settings.location
  tags     = merge(try(module.config.outputs.tags, {}), { environment = "production", landing_zone = "bidaya-prod", managed_by = "terraform" })
}

resource "azurerm_virtual_network" "production_spoke" {
  provider = azurerm.production

  name                = local.production_spoke_vnet_name
  location            = azurerm_resource_group.production_spoke.location
  resource_group_name = azurerm_resource_group.production_spoke.name
  address_space       = [var.production_spoke_address_space]
  dns_servers         = local.production_spoke_dns_servers
  tags                = azurerm_resource_group.production_spoke.tags
}

# NSG with Azure default rules (deny inbound from Internet, allow VNet). Add application rules per workload.
resource "azurerm_network_security_group" "production_workload" {
  provider = azurerm.production

  name                = local.production_spoke_nsg_name
  location            = azurerm_resource_group.production_spoke.location
  resource_group_name = azurerm_resource_group.production_spoke.name
  tags                = azurerm_resource_group.production_spoke.tags
}

# Default route to the hub Azure Firewall. Note: until firewall rules exist, workload egress is denied.
# No route is added for the Application Gateway subnet: AppGW -> spoke uses peering directly, so a
# return route via the firewall would create asymmetric routing. Add forward and return routes together
# only if inspection of AppGW traffic is approved.
resource "azurerm_route_table" "production_workload" {
  provider = azurerm.production

  name                          = local.production_spoke_route_table_name
  location                      = azurerm_resource_group.production_spoke.location
  resource_group_name           = azurerm_resource_group.production_spoke.name
  bgp_route_propagation_enabled = false
  tags                          = azurerm_resource_group.production_spoke.tags

  route {
    name                   = "default-to-hub-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.hub_firewall_private_ip
  }
}

# One initial workload subnet is created from the first /26 of the approved /24.
resource "azurerm_subnet" "production_workload" {
  provider = azurerm.production

  name                 = local.production_spoke_subnet_name
  resource_group_name  = azurerm_resource_group.production_spoke.name
  virtual_network_name = azurerm_virtual_network.production_spoke.name
  address_prefixes     = [cidrsubnet(var.production_spoke_address_space, 2, 0)]
}

resource "azurerm_subnet_network_security_group_association" "production_workload" {
  provider = azurerm.production

  subnet_id                 = azurerm_subnet.production_workload.id
  network_security_group_id = azurerm_network_security_group.production_workload.id
}

resource "azurerm_subnet_route_table_association" "production_workload" {
  provider = azurerm.production

  subnet_id      = azurerm_subnet.production_workload.id
  route_table_id = azurerm_route_table.production_workload.id
}

# Spoke -> Hub peering.
resource "azurerm_virtual_network_peering" "production_to_hub" {
  provider = azurerm.production

  name                      = "peer-prod-spoke-to-hub"
  resource_group_name       = azurerm_resource_group.production_spoke.name
  virtual_network_name      = azurerm_virtual_network.production_spoke.name
  remote_virtual_network_id = local.hub_vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = var.production_spoke_use_remote_gateway

  depends_on = [module.hub_and_spoke_vnet]
}

# Hub -> Spoke peering (Connectivity subscription).
resource "azurerm_virtual_network_peering" "hub_to_production" {
  provider = azurerm.connectivity

  name                      = "peer-hub-to-prod-spoke"
  resource_group_name       = local.hub_rg_name
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = azurerm_virtual_network.production_spoke.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = var.production_spoke_use_remote_gateway
  use_remote_gateways          = false

  depends_on = [
    module.hub_and_spoke_vnet,
    azurerm_virtual_network_peering.production_to_hub,
  ]
}
