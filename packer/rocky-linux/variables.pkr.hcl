// ============================================================
// Variables — Packer Rocky Linux 10 Golden Image
// ============================================================

// ----- Azure Authentication -----
// Use Azure CLI auth for local development, Service Principal for CI/CD.
// Set use_azure_cli_auth = false and provide client_id/secret/tenant for SP auth.

variable "subscription_id" {
  type        = string
  description = "Azure Subscription ID"
}

variable "tenant_id" {
  type        = string
  default     = ""
  description = "Azure AD Tenant ID (required for Service Principal auth)"
}

variable "client_id" {
  type        = string
  default     = ""
  description = "Service Principal App ID (leave empty for Azure CLI auth)"
}

variable "client_secret" {
  type        = string
  default     = ""
  sensitive   = true
  description = "Service Principal Password (leave empty for Azure CLI auth)"
}

variable "use_azure_cli_auth" {
  type        = bool
  default     = true
  description = "Use Azure CLI authentication (recommended for local dev)"
}

// ----- Build Location -----

variable "location" {
  type        = string
  default     = "westeurope"
  description = "Azure region for the build VM and resources"
}

variable "vm_size" {
  type        = string
  default     = "Standard_B2s"
  description = "VM size for the Packer build process"
}

// ----- Source Image -----
// NOTE: Verify Rocky Linux 10 availability in Azure Marketplace.
// Run: az vm image list --publisher erockyenterprisesoftwarefoundation --output table --all
// If Rocky Linux 10 is not yet available, use Rocky Linux 9 (sku = "9-lvm-gen2").

variable "image_publisher" {
  type        = string
  default     = "erockyenterprisesoftwarefoundation"
  description = "Marketplace image publisher"
}

variable "image_offer" {
  type        = string
  default     = "rockylinux-x86_64"
  description = "Marketplace image offer"
}

variable "image_sku" {
  type        = string
  default     = "10-lvm-gen2"
  description = "Marketplace image SKU"
}

// ----- Azure Compute Gallery Destination -----

variable "gallery_resource_group" {
  type        = string
  default     = "rg-media-prod-westeurope"
  description = "Resource group containing the Azure Compute Gallery"
}

variable "gallery_name" {
  type        = string
  default     = "gal_media"
  description = "Azure Compute Gallery name"
}

variable "image_definition" {
  type        = string
  default     = "imgdef-rockylinux10"
  description = "Image definition name in the gallery"
}

variable "image_version" {
  type        = string
  default     = "1.0.0"
  description = "Image version (semantic versioning: major.minor.patch)"
}

variable "replication_regions" {
  type        = list(string)
  default     = ["westeurope"]
  description = "Regions to replicate the gallery image to"
}
