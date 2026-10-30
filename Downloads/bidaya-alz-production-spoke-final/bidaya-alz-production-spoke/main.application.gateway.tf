# Application Gateway (WAF_v2) for the Bidaya hub, deployed in the Connectivity subscription.
#
# This file only adds resources. It reuses what the platform already creates:
#   - provider alias azurerm.connectivity
#   - hub VNet and subnet snet-agw-hub-conn-prd-bidaya-aen-01 (172.20.64.192/26), created by the hub module
#   - agw resource group (created by module.resource_groups)
#   - Log Analytics workspace (created by module.management_resources)
#
# Deployment gate: the subnet and its NSG are always created. The public IP, WAF policy, gateway and
# diagnostics are created only when var.appgw_enabled = true. Keep it false until the HTTPS listener,
# certificate, backend targets and (if backends use a private CA) trusted root certificate are approved.
#
# Routing: the AppGW subnet has NO firewall route table (AppGW v2 does not support 0.0.0.0/0 to an NVA).
# Spoke traffic uses peering directly. If inspection is required later, add BOTH a spoke-prefix route on the
# AppGW subnet AND the AppGW-subnet return route on the spoke route table in the same change.

locals {
  appgw_settings = {
    name            = "agw-hub-conn-prd-bidaya-aen-01"
    public_ip_name  = "pip-agw-hub-conn-prd-bidaya-aen-01"
    waf_policy_name = "waf-hub-conn-prd-bidaya-aen-01"
    diagnostic_name = "diag-agw-hub-conn-prd-bidaya-aen-01"
    nsg_name        = "nsg-agw-hub-conn-prd-bidaya-aen-01"
    zones           = ["1", "2", "3"]
    min_capacity    = 2 # production: at least 2 for zone-redundant baseline capacity
    max_capacity    = 5
    waf_mode        = "Prevention"
    http2_enabled   = true # placeholder until SolutionPlus confirms
    ssl_policy_name = "AppGwSslPolicy20220101"
    backend_fqdns   = []

    location                   = module.config.outputs.custom_replacements["starter_location_01"]
    resource_group_name        = module.config.outputs.custom_replacements["agw_resource_group_name"]
    log_analytics_workspace_id = module.config.outputs.custom_replacements["log_analytics_workspace_id"]
    tags                       = coalesce(module.config.outputs.connectivity_tags, module.config.outputs.tags)
  }

  appgw_components = {
    gateway_ip_configuration  = "gwip-agw-hub-conn-prd-bidaya-aen-01"
    frontend_ip_configuration = "feip-agw-hub-conn-prd-bidaya-aen-01"
    frontend_port             = "feport-http-agw-hub-conn-prd-bidaya-aen-01"
    backend_address_pool      = "bep-agw-hub-conn-prd-bidaya-aen-01"
    backend_http_settings     = "bes-https-agw-hub-conn-prd-bidaya-aen-01"
    probe                     = "probe-https-agw-hub-conn-prd-bidaya-aen-01"
    http_listener             = "lstn-http-agw-hub-conn-prd-bidaya-aen-01"
    request_routing_rule      = "rule-http-agw-hub-conn-prd-bidaya-aen-01"
  }
}

# NSG required for a public Application Gateway v2 subnet.
resource "azurerm_network_security_group" "appgw" {
  provider = azurerm.connectivity

  name                = local.appgw_settings.nsg_name
  resource_group_name = local.appgw_settings.resource_group_name
  location            = local.appgw_settings.location
  tags                = local.appgw_settings.tags

  # Azure control plane for v2 (mandatory).
  security_rule {
    name                       = "Allow-GatewayManager-Inbound"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-AzureLoadBalancer-Inbound"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  # Client traffic. Restrict source_address_prefix if the application is not public.
  security_rule {
    name                       = "Allow-Internet-HTTP-HTTPS-Inbound"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }

  depends_on = [module.resource_groups]
}

resource "azurerm_subnet_network_security_group_association" "appgw" {
  provider = azurerm.connectivity

  subnet_id                 = local.hub_subnet_ids.application_gateway
  network_security_group_id = azurerm_network_security_group.appgw.id

  depends_on = [module.hub_and_spoke_vnet]
}

resource "azurerm_public_ip" "appgw" {
  provider = azurerm.connectivity
  count    = var.appgw_enabled ? 1 : 0

  name                = local.appgw_settings.public_ip_name
  resource_group_name = local.appgw_settings.resource_group_name
  location            = local.appgw_settings.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = local.appgw_settings.zones
  tags                = local.appgw_settings.tags

  depends_on = [module.resource_groups]
}

resource "azurerm_web_application_firewall_policy" "appgw" {
  provider = azurerm.connectivity
  count    = var.appgw_enabled ? 1 : 0

  name                = local.appgw_settings.waf_policy_name
  resource_group_name = local.appgw_settings.resource_group_name
  location            = local.appgw_settings.location
  tags                = local.appgw_settings.tags

  policy_settings {
    enabled = true
    mode    = local.appgw_settings.waf_mode
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }

  depends_on = [module.resource_groups]
}

resource "azurerm_application_gateway" "appgw" {
  provider = azurerm.connectivity
  count    = var.appgw_enabled ? 1 : 0

  name                = local.appgw_settings.name
  resource_group_name = local.appgw_settings.resource_group_name
  location            = local.appgw_settings.location
  zones               = local.appgw_settings.zones
  firewall_policy_id  = azurerm_web_application_firewall_policy.appgw[0].id
  http2_enabled       = local.appgw_settings.http2_enabled
  tags                = local.appgw_settings.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = local.appgw_settings.min_capacity
    max_capacity = local.appgw_settings.max_capacity
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = local.appgw_settings.ssl_policy_name
  }

  gateway_ip_configuration {
    name      = local.appgw_components.gateway_ip_configuration
    subnet_id = local.hub_subnet_ids.application_gateway
  }

  frontend_ip_configuration {
    name                 = local.appgw_components.frontend_ip_configuration
    public_ip_address_id = azurerm_public_ip.appgw[0].id
  }

  frontend_port {
    name = local.appgw_components.frontend_port
    port = 80
  }

  # The pool is created empty until backend_fqdns is filled in appgw_settings.
  backend_address_pool {
    name  = local.appgw_components.backend_address_pool
    fqdns = length(local.appgw_settings.backend_fqdns) > 0 ? local.appgw_settings.backend_fqdns : null
  }

  probe {
    name                                      = local.appgw_components.probe
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true
  }

  backend_http_settings {
    name                                = local.appgw_components.backend_http_settings
    protocol                            = "Https"
    port                                = 443
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.appgw_components.probe
  }

  http_listener {
    name                           = local.appgw_components.http_listener
    frontend_ip_configuration_name = local.appgw_components.frontend_ip_configuration
    frontend_port_name             = local.appgw_components.frontend_port
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.appgw_components.request_routing_rule
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.appgw_components.http_listener
    backend_address_pool_name  = local.appgw_components.backend_address_pool
    backend_http_settings_name = local.appgw_components.backend_http_settings
  }

  depends_on = [
    module.hub_and_spoke_vnet,
    azurerm_subnet_network_security_group_association.appgw,
  ]
}

# Send Application Gateway and WAF logs and metrics to the platform Log Analytics workspace.
resource "azurerm_monitor_diagnostic_setting" "appgw" {
  provider = azurerm.connectivity
  count    = var.appgw_enabled ? 1 : 0

  name                       = local.appgw_settings.diagnostic_name
  target_resource_id         = azurerm_application_gateway.appgw[0].id
  log_analytics_workspace_id = local.appgw_settings.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
  }

  depends_on = [module.management_resources]
}

output "appgw_resource_id" {
  value = one(azurerm_application_gateway.appgw[*].id)
}

output "appgw_public_ip_address" {
  value = one(azurerm_public_ip.appgw[*].ip_address)
}
