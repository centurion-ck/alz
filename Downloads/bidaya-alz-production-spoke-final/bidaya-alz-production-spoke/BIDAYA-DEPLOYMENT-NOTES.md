# Bidaya platform landing zone – deployment notes

## Included platform scope

- Region: UAE North (`uaenorth`), naming code `aen`.
- Environment: production (`prd`).
- No secondary/DR region is configured.
- Hub VNet, Azure Firewall Premium and policy, VPN Gateway (`VpnGw2AZ`, active-passive/active-standby with one zone-redundant public IP configuration), DNS Private Resolver, and Private Link Private DNS zones are configured.
- DDoS Protection Plan, ExpressRoute Gateway, Bastion, and DNS auto-registration are disabled/not configured.
- No Local Network Gateway or VPN Connection is configured: the on-premises gateway IP/FQDN, on-premises address prefixes, connection type, and shared key were not provided.

## Defender for Cloud selection

The `Deploy-MDFC-Config-H224` policy assignment is configured to enable:

- Defender for Servers (ALZ policy's server plan defaults to P2) and Servers Vulnerability Assessments
- Defender for Containers
- Defender for App Service
- Defender for SQL
- Defender for open-source relational databases
- Defender for Storage
- Defender for Key Vault
- Defender CSPM

The assignment explicitly disables SQL on VMs, ARM, and Cosmos DB. The Defender email contact remains a placeholder and must be replaced before deployment.

## Platform resource groups

| Resource group | Subscription | Current deployment behavior |
|---|---|---|
| `rg-net-hub-conn-prd-bidaya-aen-01` | Connectivity | Created; hub VNet and network services use this parent RG |
| `rg-agw-hub-conn-prd-bidaya-aen-01` | Connectivity | Created; subnet NSG is always deployed. Application Gateway public IP, WAF policy, WAF_v2 gateway and diagnostics are defined but only deployed when `appgw_enabled = true` (default `false`) |
| `rg-dns-hub-conn-prd-bidaya-aen-01` | Connectivity | Created; Private DNS zones are deployed here |
| `rg-ampls-hub-conn-prd-bidaya-aen-01` | Connectivity | Created; AMPLS, scoped Log Analytics service and private endpoint are defined, with five Azure Monitor private DNS zones attached |
| `rg-log-mgmt-prd-bidaya-aen-01` | Management | Created by the ALZ management module; Log Analytics, AMA identity, and its configured DCRs are deployed here |
| `rg-mon-mgmt-prd-bidaya-aen-01` | Management | Created; used as the Defender export/service-health policy RG; DCE/action groups/alert rules are not configured in this ZIP |

### Management module limitation

The pinned `Azure/avm-ptn-alz-management` module accepts one `resource_group_name` for the Log Analytics workspace, managed identity, and its DCRs. The existing module therefore deploys the configured DCRs into `rg-log-mgmt-prd-bidaya-aen-01`, not `rg-mon-mgmt-prd-bidaya-aen-01`. Splitting those DCRs into the monitoring RG requires replacing or extending the management module implementation.

## Workload resource groups

The production/UAT workload RGs from the Bidaya naming standard are not created by this platform ZIP. The supplied `terraform.tfvars.json` has only Connectivity and Management subscription IDs, and this ZIP does not define the workload resources or workload provider aliases. Add those RGs in the workload Terraform stack once the Production/UAT subscription IDs and workload codes are confirmed.

## Subscription IDs

The source `terraform.tfvars.json` subscription GUIDs were retained unchanged. Confirm they are the intended Bidaya Connectivity and Management subscriptions before planning or deployment.

## AMPLS design decision and dependencies

AMPLS is configured with `ingestion_access_mode = "Open"` and `query_access_mode = "Open"` deliberately as a transitional setting. This is not a Terraform error and does not mean the private endpoint is absent. `Open` permits access to resources in the AMPLS over private link while also allowing access to Azure Monitor resources outside the AMPLS when those resources accept public traffic. It does not provide the same data-exfiltration restriction as `PrivateOnly`.

Do not change to `PrivateOnly` until SolutionPlus confirms the security requirement and the implementation team has:

1. Added every Azure Monitor workspace/Application Insights component that the connected networks must access to this AMPLS.
2. Added any required Data Collection Endpoints (DCEs) to the AMPLS for Azure Monitor Agent data sources that use them.
3. Confirmed the five Azure Monitor private DNS zones are present in the configured DNS resource group and linked/usable from the hub and any connected networks.
4. Validated DNS resolution to private endpoint IPs and tested agent ingestion and Log Analytics queries from the actual client networks.
5. Confirmed there are no other required Azure Monitor resources that still rely on public endpoints.

The five DNS zones in `main.ampls.tf` match Microsoft's documented Azure Monitor Private Link DNS zone list: `privatelink.monitor.azure.com`, `privatelink.oms.opinsights.azure.com`, `privatelink.ods.opinsights.azure.com`, `privatelink.agentsvc.azure-automation.net`, and `privatelink.blob.core.windows.net`. The private endpoint subnet is `/27`, matching Microsoft's stated minimum for Azure Monitor Private Link.

Microsoft references: [AMPLS design and access modes](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-design) and [Configure private link for Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/fundamentals/private-link-configure).

## Application Gateway readiness and dependencies

The Application Gateway resources are defined, but the current configuration is an infrastructure skeleton, not a production ingress configuration:

- Public IP, WAF policy, WAF_v2 gateway, HTTP listener, backend pool, HTTPS backend settings/probe, routing rule and diagnostics are defined.
- Backend FQDN list is intentionally empty. Customer/workload backend FQDNs or IPs are required.
- Only an HTTP/80 frontend listener is configured. HTTPS listener, certificate (or Key Vault certificate integration), host name and redirect policy require customer approval and certificate material.
- The health probe path `/` and HTTPS backend port 443 must be confirmed against the actual application.
- Autoscale range (1–5), HTTP/2 setting, WAF prevention mode and OWASP rule set need customer/application validation.
- The configured `/26` subnet fits the current hub `/23`, but confirm capacity expectations; the prerequisites document notes `/24` as Microsoft's recommendation for Application Gateway v2.

Do not route production workload traffic to this gateway until these inputs are supplied and tested.

## Items that can be deployed independently vs. dependencies

| Component | Current state | Dependency / decision |
|---|---|---|
| Existing management group hierarchy and platform subscriptions | Defined as existing | Confirm exact IDs, parent relationships and no unexpected moves in plan |
| Connectivity/Management resource groups | Defined | Subscription permissions and region availability |
| Hub VNet and hub subnets | Defined | Customer IP allocation approval; confirm no overlap with on-premises and future spoke ranges |
| Azure Firewall and policy resource | Defined | Firewall rules are intentionally not included; rules needed before workload traffic |
| VPN Gateway | Active-passive defined | Can provision alone; site-to-site tunnel needs on-premises public IP, prefixes, shared key and IKE/BGP decisions |
| DNS Private Resolver endpoints | Defined | Outbound forwarding rules and on-premises DNS server IP/domain suffixes are pending |
| Private DNS zones | Enabled through hub module configuration | Confirm actual plan includes required workload Private Link zones and VNet links |
| AMPLS and private endpoint | Defined | Access mode decision and end-to-end DNS/agent validation; currently Open/Open |
| Log Analytics workspace | Defined, 90-day retention | Confirm workspace naming, SKU/quotas and policy contact details |
| Application Gateway | Infrastructure skeleton defined | Backend, HTTPS certificate, hostname, probe, WAF and capacity decisions |
| Production and NonProd workload VNets/resources | Not defined in this platform ZIP | Separate workload scope; exact spoke CIDRs and workload requirements required |
| Defender security contact | Placeholder remains | Customer-approved email address required before applying policy assignment |
| DDoS Protection Plan | Disabled | Confirm whether DDoS is excluded or must be enabled; if enabled, plan association/cost approval required |

## Validation

Run from this directory:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan
```

Review the plan carefully. This archive has not been deployed to Azure and no live Azure plan was run during its preparation.


## Site-to-Site VPN: Local Network Gateway and Connection

The VPN Gateway is enabled in `platform-landing-zone.auto.tfvars` and configured in **active-passive (active-standby)** mode. `vpn_active_active_enabled = false`, and the gateway has one IP configuration with one public IP. The second public IP configuration used for active-active mode has been removed. A commented
`local_network_gateways` example is included inside
`hub_virtual_networks.primary.virtual_network_gateways.vpn`.

The Local Network Gateway and its VPN Connection are intentionally left
commented until Bidaya confirms the following inputs:

- On-premises VPN device public IP address (or FQDN).
- On-premises network address prefixes (CIDR ranges).
- Customer-approved pre-shared key, exchanged securely.
- Whether BGP is required; if enabled, the on-premises ASN and BGP peer IP.

After receiving the values, populate the template and uncomment the
`local_network_gateways` block. The connection `type` is set to `IPsec` and
the protocol example is `IKEv2`; confirm compatibility with the customer VPN
device before deployment. Do not commit a real pre-shared key to source control.

## Bidaya IP address allocation

- Overall Bidaya allocation: `172.20.64.0/20` (routing/allocation scope).
- UAE North hub VNet: `172.20.64.0/23`.
- Hub subnets configured from the approved connectivity sheet and prerequisites: AzureFirewallSubnet `172.20.64.0/26`; AzureFirewallManagementSubnet `172.20.64.64/26`; GatewaySubnet `172.20.64.128/27`; DNS inbound `172.20.64.160/28` (static endpoint IP `172.20.64.164`); DNS outbound `172.20.64.176/28`; Application Gateway `172.20.64.192/26`; private endpoints `172.20.65.0/27`.
- The prerequisites document specifies a `/24` for the Production spoke but does not specify its exact CIDR. The spoke is implemented in `main.production.spoke.tf`; `production_spoke_address_space` is a required input and must be supplied only after SolutionPlus/customer confirms the exact non-overlapping prefix (supply it as a pipeline variable, e.g. `TF_VAR_production_spoke_address_space`). Do not assign `172.20.64.0/20` to the hub or spoke VNet itself. The initial workload subnet is the first `/26` of the approved `/24`.


## Existing Bidaya management-group hierarchy (customer portal)

The architecture definition is aligned to the existing hierarchy. It marks the existing management groups with `exists: true`; it is not intended to create duplicate management groups. The configured parent is the existing Tenant Root Management Group ID `9d2a14f1-858d-4d17-b1e6-ab2fa566dd02`, and the architecture root is the existing `Bidaya` management group.

- Root Management Group
  - Bidaya
    - Bidaya-Platform
      - Bidaya-Connectivity (`sub-bidaya-connectivity`)
      - Bidaya-Management (`sub-bidaya-management`)
    - Bidaya-LandingZone
      - Bidaya-Prod (`sub-bidaya-prod`)
      - Bidaya-NonProd (`sub-bidaya-nonprod`)
    - Bidaya-Sandbox (no subscription placed by this configuration)
    - Bidaya-Decommissioned (no subscription placed by this configuration)

Subscription IDs for Connectivity, Management, Prod and NonProd are taken from the customer portal screenshots supplied for this update. Identity and Security subscription placement has been removed because those subscriptions are not part of the confirmed implementation scope.

The management-group entries are marked as existing. Review the Terraform plan carefully to confirm it only manages the intended hierarchy and subscription placements; do not apply if it proposes deleting or unexpectedly moving existing customer subscriptions.


### Application Gateway subnet routing and spoke return path

The Application Gateway subnet (`snet-agw-hub-conn-prd-bidaya-aen-01`, `172.20.64.192/26`) is intentionally **not associated with the generated hub user-subnet/firewall route table**. Do not attach a route table that sends `0.0.0.0/0` to Azure Firewall to this subnet; Application Gateway v2 requires its documented control-plane connectivity and does not support forced-tunnelling of its default route to a virtual appliance.

When the Production Spoke `/24` address prefix and Azure Firewall private IP are confirmed, design and add a **specific route for the spoke prefix** on the Application Gateway subnet only if the approved traffic path requires App Gateway-to-backend traffic to traverse Azure Firewall. The route must use the approved next hop (typically the Azure Firewall private IP when firewall inspection is required); do not create it until the spoke CIDR and firewall private IP are confirmed.

For symmetric routing, add the corresponding **return route for the Application Gateway subnet (`172.20.64.192/26`) on the relevant spoke subnet route table**, with the same approved inspection path. Confirm NSG rules and Azure Firewall network/application rules allow the required backend ports and health-probe traffic. Validate effective routes in both directions before enabling the listener for production traffic.

**Dependency:** Production Spoke CIDR (`/24`), Azure Firewall private IP, backend destinations/ports, and customer approval of whether App Gateway-to-spoke traffic must be inspected. Until these are known, the App Gateway subnet route table should remain unassociated and no speculative UDRs should be added.


## Final hardening changes and required inputs (read before the first plan)

### Required before plan/apply (the plan fails or stops without these)

1. `defender_email_security_contact` in `platform-landing-zone.auto.tfvars` is still a placeholder. A guard (`terraform_data.placeholder_guard`) **fails the plan** until it is replaced with a customer-approved email.
2. `production_spoke_address_space` (approved `/24`) has no default. Supply it via pipeline variable `TF_VAR_production_spoke_address_space`.
3. Run `terraform init` once and **commit `.terraform.lock.hcl`** (it is no longer git-ignored) so provider versions are reproducible.
4. In Azure DevOps, put the apply stage behind an **environment with manual approval** (the pipeline template is external and cannot be changed from this repo).
5. Give the pipeline identity rights on the Log Analytics workspace in the Management subscription (needed by the AMPLS scoped service and Application Gateway diagnostic setting), and confirm required resource providers are registered in every subscription (`resource_provider_registrations = "none"`).

### What changed in this version

- Application Gateway subnet again has **no** generated firewall route table (`assign_generated_route_table = false`); AppGW v2 does not support `0.0.0.0/0` to a virtual appliance.
- Application Gateway subnet has an NSG (GatewayManager 65200-65535, AzureLoadBalancer, Internet 80/443). Gateway/WAF/public IP only deploy with `appgw_enabled = true`. `min_capacity` is 2, TLS policy pinned to `AppGwSslPolicy20220101`.
- Hub subnet, DNS zone and VNet IDs are built from names (`locals.ids.tf`) instead of data sources with `depends_on`, avoiding forced recreation of the AMPLS private endpoint and VNet peerings when the hub module has pending changes.
- Production spoke subnet has an NSG and a route table (`0.0.0.0/0` -> hub Azure Firewall, next hop `172.20.64.4` unless `hub_firewall_private_ip` is set; a non-blocking `check` warns if it differs from the real firewall). **Until firewall rules exist, Production workload egress is denied.**
- No spoke route for the Application Gateway subnet is created: AppGW -> spoke uses peering directly. If inspection is approved later, add the spoke-prefix route on the AppGW subnet **and** the return route (`172.20.64.192/26` -> firewall) on the spoke route table in the same change; adding only one side causes asymmetric routing and drops.
- Spoke DNS points to the hub DNS Private Resolver inbound endpoint (`172.20.64.164`), so Private Link zone resolution works through zones linked to the hub; spoke-side zone links are not needed for that path.
- NonProd subscription ID is now a variable (`nonprod_subscription_id`), like Production.
- `destroy` was removed from the CD pipeline; all AzureRM providers use `prevent_deletion_if_contains_resources = true`.

### Still open (not solved by this repository)

HTTPS listener/certificate/backends (and trusted root certificate if backends use a private CA), WAF tuning (OWASP 3.2, Prevention mode), firewall rules, GatewaySubnet route table for on-premises-to-spoke inspection, VPN Local Network Gateway details, AMPLS `PrivateOnly` decision, DDoS decision, Defender plan cost approval, and NSG rules for actual workloads. This archive has not been validated with `terraform validate` or `plan` or deployed to Azure.
