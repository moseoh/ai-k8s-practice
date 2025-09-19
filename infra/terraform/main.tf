# main.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  credentials = file(var.credentials_file)
  project     = var.project_id
  region      = var.region
  zone        = var.zone
}

# VPC 네트워크
resource "google_compute_network" "k8s_vpc" {
  name                    = "k8s-vpc"
  auto_create_subnetworks = false
}

# 서브넷
resource "google_compute_subnetwork" "k8s_subnet" {
  name          = "k8s-subnet"
  ip_cidr_range = "10.240.0.0/24"
  network       = google_compute_network.k8s_vpc.id
  region        = var.region
}

# 방화벽 - 내부 통신
resource "google_compute_firewall" "k8s_internal" {
  name    = "k8s-allow-internal"
  network = google_compute_network.k8s_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["10.240.0.0/24", "10.200.0.0/16"]
}

# 방화벽 - 외부 SSH 및 Kubernetes API
resource "google_compute_firewall" "k8s_external" {
  name    = "k8s-allow-external"
  network = google_compute_network.k8s_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "6443", "30000-32767"]
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = ["0.0.0.0/0"]
}

# 마스터 노드
resource "google_compute_instance" "k8s_master" {
  name         = "k8s-master"
  machine_type = var.master_machine_type
  zone         = var.zone

  tags = ["k8s-master", "k8s"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s_subnet.id
    network_ip = "10.240.0.10"

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_key_file)}"
  }

  service_account {
    scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
  }
}

# 워커 노드들
resource "google_compute_instance" "k8s_workers" {
  count        = var.worker_count
  name         = "k8s-worker-${count.index + 1}"
  machine_type = var.worker_machine_type
  zone         = var.zone

  tags = ["k8s-worker", "k8s"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 30
      type  = "pd-standard"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.k8s_subnet.id
    network_ip = "10.240.0.${20 + count.index}"

    access_config {
      // Ephemeral public IP
    }
  }

  metadata = {
    ssh-keys = "ubuntu:${file(var.ssh_key_file)}"
  }

  service_account {
    scopes = ["compute-rw", "storage-ro", "service-management", "service-control", "logging-write", "monitoring"]
  }
}