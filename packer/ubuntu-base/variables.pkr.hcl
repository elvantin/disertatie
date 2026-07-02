// ============================================================
// Variables — Packer Ubuntu 22.04 Base Image
// ============================================================

// ----- Azure Authentication -----

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
  default     = "swedencentral"
  description = "Azure region for the build VM and resources"
}

variable "vm_size" {
  type        = string
  default     = "Standard_D2s_v3"
  description = "VM size for the Packer build process"
}

// ----- Source Image -----

variable "image_publisher" {
  type        = string
  default     = "canonical"
  description = "Marketplace image publisher"
}

variable "image_offer" {
  type        = string
  default     = "ubuntu-22_04-lts"
  description = "Marketplace image offer"
}

variable "image_sku" {
  type        = string
  default     = "server"
  description = "Marketplace image SKU"
}

// ----- Azure Compute Gallery Destination -----

variable "gallery_resource_group" {
  type        = string
  default     = "rg-mediasrl-packer-swedencentral"
  description = "Resource group containing the Azure Compute Gallery"
}

variable "gallery_name" {
  type        = string
  default     = "gal_mediasrl"
  description = "Azure Compute Gallery name"
}

variable "image_definition" {
  type        = string
  default     = "imgdef-ubuntu2204"
  description = "Image definition name in the gallery"
}

variable "image_version" {
  type        = string
  default     = "1.0.0"
  description = "Image version (semantic versioning: major.minor.patch)"
}

variable "replication_regions" {
  type        = list(string)
  default     = ["swedencentral"]
  description = "Regions to replicate the gallery image to"
}
