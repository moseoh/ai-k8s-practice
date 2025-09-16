# outputs.tf - Ansible에서 사용할 인프라 정보 출력

# 마스터 노드 정보
output "master_external_ip" {
  value       = google_compute_instance.k8s_master.network_interface[0].access_config[0].nat_ip
  description = "마스터 노드의 외부 IP 주소"
}

output "master_internal_ip" {
  value       = google_compute_instance.k8s_master.network_interface[0].network_ip
  description = "마스터 노드의 내부 IP 주소"
}

output "master_name" {
  value       = google_compute_instance.k8s_master.name
  description = "마스터 노드 인스턴스 이름"
}

# 워커 노드 정보
output "worker_external_ips" {
  value = [
    for instance in google_compute_instance.k8s_workers : instance.network_interface[0].access_config[0].nat_ip
  ]
  description = "워커 노드들의 외부 IP 주소 목록"
}

output "worker_internal_ips" {
  value = [
    for instance in google_compute_instance.k8s_workers : instance.network_interface[0].network_ip
  ]
  description = "워커 노드들의 내부 IP 주소 목록"
}

output "worker_names" {
  value = [
    for instance in google_compute_instance.k8s_workers : instance.name
  ]
  description = "워커 노드 인스턴스 이름 목록"
}

# 네트워크 정보
output "vpc_network" {
  value       = google_compute_network.k8s_vpc.name
  description = "VPC 네트워크 이름"
}

output "subnet_cidr" {
  value       = google_compute_subnetwork.k8s_subnet.ip_cidr_range
  description = "서브넷 CIDR 범위"
}

# 프로젝트 및 리전 정보
output "project_id" {
  value       = var.project_id
  description = "GCP 프로젝트 ID"
}

output "region" {
  value       = var.region
  description = "GCP 리전"
}

output "zone" {
  value       = var.zone
  description = "GCP 존"
}

# SSH 접속 정보
output "ssh_user" {
  value       = "ubuntu"
  description = "SSH 접속 사용자 이름"
}

# Ansible 인벤토리용 통합 출력
output "ansible_inventory" {
  value = {
    masters = {
      hosts = {
        (google_compute_instance.k8s_master.name) = {
          ansible_host        = google_compute_instance.k8s_master.network_interface[0].access_config[0].nat_ip
          private_ip         = google_compute_instance.k8s_master.network_interface[0].network_ip
          ansible_user       = "ubuntu"
        }
      }
    }
    workers = {
      hosts = {
        for idx, instance in google_compute_instance.k8s_workers :
        instance.name => {
          ansible_host = instance.network_interface[0].access_config[0].nat_ip
          private_ip   = instance.network_interface[0].network_ip
          ansible_user = "ubuntu"
        }
      }
    }
  }
  description = "Ansible 동적 인벤토리용 구조화된 출력"
}