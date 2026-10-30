# Bidaya Production spoke implementation

This implementation extends the existing Bidaya ALZ Accelerator root module. It reuses the existing `azurerm.connectivity` provider and the existing Hub VNet created by `module.hub_and_spoke_vnet`. It adds an `azurerm.production` provider alias and creates the Production spoke resources in the already-onboarded Production subscription.

## Files changed (this version also adds `locals.ids.tf`, spoke NSG/route table, `nonprod_subscription_id`, `appgw_enabled`, `hub_firewall_private_ip`)

- `terraform.tf`: adds the Production AzureRM provider alias.
- `variables.tf`: adds the Production subscription ID, approved spoke CIDR and optional remote-gateway switch.
- `main.config.tf`, `modules/config-templating/variables.tf`, `modules/config-templating/locals.config.tf`: expose the Production subscription ID as a template replacement.
- `platform-landing-zone.auto.tfvars`: uses that replacement for the existing `prod` management-group placement.
- `terraform.tfvars.json`: supplies the Production subscription ID already present in the source configuration.
- `main.production.spoke.tf`: creates the spoke RG, VNet, initial workload subnet and both peering directions.
- `outputs.production.spoke.tf`: exports the spoke resource IDs.

## Required input before plan/apply

Set `production_spoke_address_space` to the exact customer/SolutionPlus-approved IPv4 `/24`. The original deployment notes explicitly say the Production spoke CIDR has not yet been confirmed. Do not assume `172.20.66.0/24` or any other range without approval. The Bidaya overall allocation is `172.20.64.0/20`; the Hub VNet is `172.20.64.0/23`. The selected spoke range must be inside the approved allocation and must not overlap the Hub, on-premises networks, other spokes, or any connected networks.

Example local input (only after approval):

```hcl
production_spoke_address_space = "<APPROVED-PRODUCTION-SPOKE-CIDR>/24"
production_spoke_use_remote_gateway = false
```

The initial workload subnet is calculated as the first `/26` within the approved `/24`; the remaining `/26` blocks are left unused for future subnet planning.

## Gateway transit

The Hub configuration in this repository includes a VPN Gateway. `production_spoke_use_remote_gateway` defaults to `false`. Set it to `true` only if the Production spoke must use the Hub VPN Gateway for on-premises connectivity. This enables `allow_gateway_transit` on the Hub peering and `use_remote_gateways` on the Spoke peering. Do not enable it if the spoke has its own gateway or if the network design does not require it.

## Routing and DNS notes

- The spoke VNet uses the Hub DNS Private Resolver inbound endpoint `172.20.64.164`. Confirm it is deployed and reachable before applying. Private Link names resolve through the zones linked to the hub, so no separate spoke zone links are required for that path.
- The workload subnet has an NSG (Azure default rules) and a route table with `0.0.0.0/0` -> Azure Firewall private IP (default `172.20.64.4`, override with `hub_firewall_private_ip`). **Until firewall rules are created, workload egress is denied.**
- Spoke -> hub traffic uses the peering system route and does not traverse the firewall. No route is added for the Application Gateway subnet (see the notes file for the symmetric-routing rule).
- Hub-side IDs are built from names (`locals.ids.tf`), not data sources with `depends_on`, so hub changes do not force the peerings to be recreated.

## State and deployment safety

This change is in the same Terraform root and backend as the supplied Platform Landing Zone. It will therefore use the existing root state. Before applying, inspect the plan and confirm it contains only the intended new Production resources plus the expected templated subscription placement value. If the Production subscription is already placed under `BidayaProd` in state, do not force a second placement operation. Do not import or recreate the existing Hub VNet.

Run `terraform fmt -recursive`, `terraform init`, `terraform validate`, and `terraform plan`. Review all changes before apply. The archive has not been deployed or validated against live Azure.
