variable "starter_locations" {
  type        = list(string)
  description = "The default for Azure resources. (e.g 'uksouth')"
  validation {
    condition     = length(var.starter_locations) > 0
    error_message = "You must provide at least one starter location region."
  }
  validation {
    condition     = alltrue([for location in var.starter_locations : can(regex("^[a-z][a-z0-9]+$", location))])
    error_message = "All starter locations must be valid Azure region names (lowercase letters and numbers only, e.g. 'uksouth', 'eastus2'). Check for typos, spaces, or uppercase characters."
  }
  validation {
    condition     = var.connectivity_type == "none" || ((length(var.virtual_hubs) <= length(var.starter_locations)) || (length(var.hub_virtual_networks) <= length(var.starter_locations)))
    error_message = "The number of regions supplied in `starter_locations` must match the number of regions specified for connectivity."
  }
}

variable "starter_locations_short" {
  type        = map(string)
  default     = {}
  description = <<DESCRIPTION
Optional overrides for the starter location short codes.

Keys should match the built-in replacement names used in the examples, for example:
- starter_location_01_short
- starter_location_02_short

If not provided, short codes are derived from the regions module using geo_code when available, falling back to short_name when no geo_code is published.
DESCRIPTION
}

variable "required_subscription_keys" {
  description = "The list of subscription keys that are required to have valid GUIDs. Keys not in this list may be null or empty."
  type        = list(string)
  default     = ["connectivity", "management"]
  nullable    = false
}

variable "subscription_ids" {
  description = "The list of subscription IDs to deploy the Platform Landing Zones into"
  type        = map(string)
  default     = {}
  nullable    = false
  validation {
    condition     = length(var.subscription_ids) == 0 || alltrue([for key, id in var.subscription_ids : contains(var.required_subscription_keys, key) ? can(regex("^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$", id)) : (id == null || id == "" || can(regex("^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$", id)))])
    error_message = "Required subscription IDs must be valid GUIDs. Optional subscription IDs must be valid GUIDs, null, or empty."
  }
  validation {
    condition     = length(var.subscription_ids) == 0 || alltrue([for id in keys(var.subscription_ids) : contains(["management", "connectivity", "identity", "security"], id)])
    error_message = "The keys of the subscription_ids map must be one of 'management', 'connectivity', 'identity' or 'security'"
  }
  validation {
    condition     = alltrue([for key in var.required_subscription_keys : contains(keys(var.subscription_ids), key)])
    error_message = "All required subscription keys must be present in subscription_ids."
  }
}

variable "root_parent_management_group_id" {
  type        = string
  default     = ""
  description = "This is the id of the management group that the ALZ hierarchy will be nested under, will default to the Tenant Root Group"
}

variable "enable_telemetry" {
  type        = bool
  default     = true
  description = "Flag to enable/disable telemetry"
}

variable "custom_replacements" {
  type = object({
    names                      = optional(map(string), {})
    resource_group_identifiers = optional(map(string), {})
    resource_identifiers       = optional(map(string), {})
  })
  default = {
    names                      = {}
    resource_group_identifiers = {}
    resource_identifiers       = {}
  }
  description = "Custom replacements"
}

variable "tags" {
  type        = map(string)
  default     = null
  description = "(Optional) Tags of the resource."
}

variable "telemetry_additional_content" {
  type        = map(string)
  default     = null
  description = <<DESCRIPTION
Additional content to add to the telemetry tags. This can be used to add custom tags to the telemetry data.
To add array / object values, serialize them as JSON strings using `jsonencode()`.

Any information entered here will be sent to Microsoft as part of the telemetry data collected. Do not include any personal or sensitive information.

e.g.

```hcl
telemetry_additional_content = {
  custom_tag_1 = "value1"
  custom_tag_2 = "value2"
  custom_array_tag = jsonencode(["value1", "value2"])
}
DESCRIPTION
}


variable "production_subscription_id" {
  description = "Existing Bidaya Production subscription ID. Keep this aligned with subscription_placement.prod."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.production_subscription_id))
    error_message = "production_subscription_id must be a valid subscription GUID."
  }
}

variable "production_spoke_address_space" {
  description = "SolutionPlus/customer-approved non-overlapping /24 CIDR for the Bidaya Production spoke. Do not guess this value."
  type        = string

  validation {
    condition     = can(cidrhost(var.production_spoke_address_space, 0)) && can(regex("/24$", var.production_spoke_address_space))
    error_message = "production_spoke_address_space must be a valid IPv4 /24 CIDR approved for the Production spoke."
  }
}

variable "production_spoke_use_remote_gateway" {
  description = "Set true only when Production must use the Connectivity Hub VPN gateway. Enables gateway transit on the Hub and remote gateway on the Spoke."
  type        = bool
  default     = false
}

variable "nonprod_subscription_id" {
  description = "Existing Bidaya NonProd subscription ID. Keep aligned with subscription_placement.nonprod."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.nonprod_subscription_id))
    error_message = "nonprod_subscription_id must be a valid subscription GUID."
  }
}

variable "appgw_enabled" {
  description = "Deploy the Application Gateway, WAF policy and public IP. Keep false until the HTTPS listener, certificate and backends are approved; the subnet and NSG are always created."
  type        = bool
  default     = false
}

variable "hub_firewall_private_ip" {
  description = "Azure Firewall private IP used as next hop for the Production spoke. Null = first usable address of the firewall subnet (x.x.x.4). A check block warns if this differs from the real firewall IP."
  type        = string
  default     = null
}
