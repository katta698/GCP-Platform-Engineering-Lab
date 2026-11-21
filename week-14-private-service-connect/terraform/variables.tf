variable "net_hub_project_id" {
  description = "Network hub project from Week 01. Holds the VPC and everything this week adds."
  type        = string
}

variable "region" {
  description = "Region for the subnet and the probe VM. The PSC endpoint itself is global."
  type        = string
  default     = "us-central1"
}

variable "subnet_cidr" {
  description = "Subnet for the probe VM. Must not overlap the hub's 10.20.0.0/24 or 10.20.1.0/24, or Week 13's 10.30.0.0/24."
  type        = string
  default     = "10.40.0.0/24"
}

variable "endpoint_ip" {
  description = "The Private Service Connect endpoint address. A single global internal IPv4 that must sit OUTSIDE every subnet range in this VPC - Google rejects an address inside one. Deliberately far from subnet_cidr so the distinction is visible."
  type        = string
  default     = "10.99.0.2"
}
