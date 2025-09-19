# variables.tf
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "asia-northeast3"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "asia-northeast3-a"
}

variable "credentials_file" {
  description = "Path to service account key file"
  type        = string
  default     = "./terraform-key.json"
}

variable "master_machine_type" {
  description = "Machine type for master node"
  type        = string
  default     = "e2-small"
}

variable "worker_machine_type" {
  description = "Machine type for worker nodes"
  type        = string
  default     = "e2-small"
}

variable "worker_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 3
}

variable "ssh_key_file" {
  description = "Path to SSH public key file"
  type        = string
  default     = "~/.ssh/ai-k8s-practice.pub"
}
