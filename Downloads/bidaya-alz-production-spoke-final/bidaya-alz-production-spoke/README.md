# Azure Landing Zones Accelerator Starter Module for Terraform - Azure Verified Modules Complete Multi-Region

This module is part of the Azure Landing Zones Accelerator solution. It is a complete multi-region implementation of the Azure Landing Zones Platform Landing Zone for Terraform.

It deploys a hub and spoke virtual network or Virtual WAN architecture across multiple regions.

The module deploys the following resources:

- Management group hierarchy
- Azure Policy definitions and assignments
- Role definitions
- Management resources, including Log Analytics workspace and Automation account
- Hub and spoke virtual network or Virtual WAN architecture across multiple regions
- DDOS protection plan
- Private DNS zones

## Usage

The module is intended to be used with the [Azure Landing Zones Accelerator](https://aka.ms/alz/acc). Head over there to get started.

>NOTE: The module can be used independently if needed. Example `tfvars` files can be found in the `examples` directory for that use case.

### Running Directly

#### Run the local examples

Create a `terraform.tfvars` file in the root of the module directory with the following content, replacing the placeholders with the actual values:

```hcl
starter_locations            = ["uksouth", "ukwest"]
subscription_id_connectivity = "00000000-0000-0000-0000-000000000000"
subscription_id_identity     = "00000000-0000-0000-0000-000000000000"
subscription_id_management   = "00000000-0000-0000-0000-000000000000"
```

##### Hub and Spoke Virtual Networks Multi Region

```powershell
terraform init
terraform apply -var-file ./examples/full-multi-region/hub-and-spoke-vnet.tfvars
```

##### Virtual WAN Multi Region

```powershell
terraform init
terraform apply -var-file ./examples/full-multi-region/virtual-wan.tfvars
```


## Bidaya-specific configuration notes

- Primary region is UAE North (`uaenorth`) with short code `aen`. No DR/secondary region is configured.
- DDoS Protection Plan, ExpressRoute gateway, Bastion, and DNS auto-registration are disabled/removed from the deployment configuration.
- VPN Gateway SKU is set to `VpnGw2AZ` in active-passive (active-standby) mode with one zone-redundant public IP. This is an Azure AZ-capable SKU; confirm regional SKU availability and the required gateway generation before deployment.
- Defender for Cloud policy parameters enable only Servers (including vulnerability assessment), Containers, App Service, SQL, OSS relational databases, Storage, Key Vault, and CSPM. SQL on VM, ARM, and Cosmos DB are explicitly disabled.
- Platform resource groups configured: `rg-net-hub-conn-prd-bidaya-aen-01`, `rg-agw-hub-conn-prd-bidaya-aen-01`, `rg-dns-hub-conn-prd-bidaya-aen-01`, `rg-ampls-hub-conn-prd-bidaya-aen-01` (Connectivity subscription), `rg-log-mgmt-prd-bidaya-aen-01`, and `rg-mon-mgmt-prd-bidaya-aen-01`. The AGW and AMPLS resource groups are created, and this configuration also defines the Application Gateway/WAF resources and the Azure Monitor Private Link Scope (AMPLS), scoped Log Analytics service, private endpoint, and five Azure Monitor private DNS zone associations.
- The current ALZ management module accepts one resource group for its Log Analytics workspace, managed identity, and configured DCRs. Therefore the configured DCRs remain in `rg-log-mgmt-prd-bidaya-aen-01`; `rg-mon-mgmt-prd-bidaya-aen-01` is created for monitoring resources that require a separate implementation. The DCE, action groups, and alert rules are not deployed by the current ZIP.
- Local Network Gateway and VPN Connection are not configured because on-premises gateway address, address prefixes, and shared-key inputs were not supplied. The VPN Gateway alone does not establish an on-premises tunnel.
- `terraform.tfvars.json` retains the source ZIP's Connectivity and Management subscription IDs. Verify these IDs and the tenant/root management-group ID before running a plan.
- Defender email security contact remains a placeholder (`replace_me@replace_me.com`) and must be replaced with the customer's approved contact.

AMPLS access modes are currently `Open` for both ingestion and queries as a transitional setting. This allows private-link access while retaining public access to resources outside the scope; it is not a private-only security boundary. Confirm the customer security decision before changing either mode to `PrivateOnly`. Before doing so, onboard every required Azure Monitor workspace/component and required DCE, validate private DNS resolution and agent ingestion/query paths, and confirm no other monitoring resources depend on public endpoints.

The Application Gateway is infrastructure-only at this stage: the backend pool is empty and only an HTTP listener is configured. HTTPS certificate, hostname, backend targets, probe path, and routing must be supplied/approved before workload traffic is directed to it. Do not treat this as production ingress.

Run `terraform fmt -recursive`, `terraform init`, `terraform validate`, and inspect `terraform plan` before deployment. This archive has not been deployed to Azure.


### Application Gateway subnet routing and spoke return path

The Application Gateway subnet (`snet-agw-hub-conn-prd-bidaya-aen-01`, `172.20.64.192/26`) is intentionally **not associated with the generated hub user-subnet/firewall route table**. Do not attach a route table that sends `0.0.0.0/0` to Azure Firewall to this subnet; Application Gateway v2 requires its documented control-plane connectivity and does not support forced-tunnelling of its default route to a virtual appliance.

When the Production Spoke `/24` address prefix and Azure Firewall private IP are confirmed, design and add a **specific route for the spoke prefix** on the Application Gateway subnet only if the approved traffic path requires App Gateway-to-backend traffic to traverse Azure Firewall. The route must use the approved next hop (typically the Azure Firewall private IP when firewall inspection is required); do not create it until the spoke CIDR and firewall private IP are confirmed.

For symmetric routing, add the corresponding **return route for the Application Gateway subnet (`172.20.64.192/26`) on the relevant spoke subnet route table**, with the same approved inspection path. Confirm NSG rules and Azure Firewall network/application rules allow the required backend ports and health-probe traffic. Validate effective routes in both directions before enabling the listener for production traffic.

**Dependency:** Production Spoke CIDR (`/24`), Azure Firewall private IP, backend destinations/ports, and customer approval of whether App Gateway-to-spoke traffic must be inspected. Until these are known, the App Gateway subnet route table should remain unassociated and no speculative UDRs should be added.


## Production spoke and final hardening

See `PRODUCTION-SPOKE-IMPLEMENTATION.md` and the "Final hardening changes and required inputs" section of `BIDAYA-DEPLOYMENT-NOTES.md`. The plan fails until the Defender security contact placeholder is replaced and `production_spoke_address_space` is supplied. The Application Gateway/WAF/public IP are not deployed unless `appgw_enabled = true`.
