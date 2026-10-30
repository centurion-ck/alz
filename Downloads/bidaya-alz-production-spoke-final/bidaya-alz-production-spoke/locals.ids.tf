# Deterministic resource IDs for hub resources created by module.hub_and_spoke_vnet.
#
# These are built from names instead of being read with data sources that use depends_on.
# A data source with depends_on is deferred to apply time whenever the hub module has any pending
# change, which turns ForceNew attributes (private endpoint subnet_id, peering vnet names) into
# "known after apply" and can force destroy/recreate. Plain strings are always known at plan time.
# Ordering is kept with depends_on on the consuming resources.
locals {
  connectivity_subscription_id = var.subscription_ids["connectivity"]

  hub_rg_name   = module.config.outputs.custom_replacements["connectivity_hub_primary_resource_group_name"]
  hub_vnet_name = module.config.outputs.custom_replacements["primary_virtual_network_name"]
  dns_rg_name   = module.config.outputs.custom_replacements["dns_resource_group_name"]

  hub_vnet_id = "/subscriptions/${local.connectivity_subscription_id}/resourceGroups/${local.hub_rg_name}/providers/Microsoft.Network/virtualNetworks/${local.hub_vnet_name}"

  hub_subnet_ids = {
    application_gateway = "${local.hub_vnet_id}/subnets/snet-agw-hub-conn-prd-bidaya-aen-01"
    private_endpoints   = "${local.hub_vnet_id}/subnets/snet-pe-hub-conn-prd-bidaya-aen-01"
  }

  # Azure Firewall takes the first usable address (.4) of AzureFirewallSubnet.
  # Override with var.hub_firewall_private_ip if the real address differs (a check block warns).
  hub_firewall_private_ip = coalesce(
    var.hub_firewall_private_ip,
    cidrhost(module.config.outputs.custom_replacements["primary_firewall_subnet_address_prefix"], 4)
  )
}

# Placeholder guard: the plan fails while the Defender security contact is still the template value.
resource "terraform_data" "placeholder_guard" {
  lifecycle {
    precondition {
      condition     = !can(regex("replace_me", module.config.outputs.custom_replacements["defender_email_security_contact"]))
      error_message = "defender_email_security_contact is still the placeholder. Set a customer-approved email in platform-landing-zone.auto.tfvars before planning or applying."
    }
  }
}

# Non-blocking warning if the assumed firewall IP differs from the deployed firewall.
check "firewall_private_ip" {
  data "azurerm_firewall" "hub" {
    provider = azurerm.connectivity

    name                = module.config.outputs.custom_replacements["primary_firewall_name"]
    resource_group_name = local.hub_rg_name
  }

  assert {
    condition     = data.azurerm_firewall.hub.ip_configuration[0].private_ip_address == local.hub_firewall_private_ip
    error_message = "Production spoke next hop (${local.hub_firewall_private_ip}) does not match the Azure Firewall private IP. Set hub_firewall_private_ip."
  }
}
