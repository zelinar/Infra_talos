# `infra_talos` — Zero-Touch Talos Linux + Proxmox + GitOps Stack

This project provisions an immutable, API-driven **Talos Linux Kubernetes cluster** on **Proxmox VE** using **Terraform** (eliminating Packer and Ansible), installs **Cilium CNI**, bootstraps **ArgoCD**, and manages **Core Cluster Services** and a **VictoriaMetrics + VictoriaLogs + Grafana Alloy + Grafana Observability Stack** via Sync-Wave ordered GitOps.

---

## Architecture Layers

1. **Layer 1: Basic Infrastructure & Cluster Bootstrap (`terraform/`)** *(Implemented)*
   * **Talos Image Factory (`talos-image.tf`)**: Dynamically generates a Talos schematic with `siderolabs/qemu-guest-agent` (Proxmox integration) and `siderolabs/iscsi-tools` + `siderolabs/util-linux-tools` (Longhorn prerequisites), then downloads the ISO directly to Proxmox storage.
   * **Proxmox VM Provisioning (`vms.tf`)**: Uses `bpg/proxmox` to create Control Plane and Worker VMs with per-node CPU/RAM/Disk sizing and Cloud-Init static IP injection.
   * **Talos Cluster Bootstrap (`talos-cluster.tf`)**: Generates Talos machine secrets and configs, applies them via the Talos API (`50000/tcp`), installs Talos to `/dev/sda`, bootstraps `etcd` & Kubernetes, and writes `generated/kubeconfig` and `generated/talosconfig`.
   * **CNI Layer (`cni.tf`)**: Deploys **Cilium** (with `kube-proxy` replacement, KubePrism `localhost:7445` integration, and Hubble UI) via Helm so nodes become `Ready`.
2. **Layer 2: ArgoCD Bootstrap & Root ApplicationSets (`terraform/argocd.tf` & `gitops/`)** *(Implemented)*
   * **ArgoCD Helm Deployment (`argocd.tf`)**: Automatically installs ArgoCD into the `argocd` namespace via Terraform's Helm provider once Cilium is healthy, configures Traefik Ingress (`argocd-mgmt.homelab.cloud`), and outputs the admin password via `terraform output -raw argocd_initial_admin_password`.
   * **AppProjects (`gitops/projects/app-projects.yaml.tftpl`)**: Creates `core-services`, `observability`, and `workloads` `AppProject`s at sync-wave `-10`.
   * **Sync-Wave Ordered ApplicationSets (`gitops/appsets/`)**: Defines `core-services` and `observability` `ApplicationSet`s with strict Sync Waves (`Wave 1` through `Wave 6`) and Talos `PodSecurity` (`privileged`) namespace labels controlled by `var.enable_argocd_appsets`.
3. **Layer 3: Core Cluster Services (`core_services/`)** *(Implemented)*
   * **Wave 1**: `cert-manager` (`v1.20.1`), `metallb` (`0.15.2`), `metrics-server` (`3.13.0` with `--kubelet-insecure-tls`).
   * **Wave 2**: `homelab-tls` (`ClusterIssuer` + `wildcard-homelab-secret` for `*.homelab.cloud` in `traefik` and `monitoring`), `metallb-custom-ip-pool` (`10.10.20.125-10.10.20.129`), `longhorn` (`1.11.1` + `longhorn-mgmt.homelab.cloud` Ingress), `cnpg-operator` (`0.23.2`).
   * **Wave 3**: `traefik` (`39.0.7` on `10.10.20.125`, HTTPS redirect, default wildcard certificate, and syslog TCP/UDP entrypoints).
4. **Layer 4: VictoriaMetrics + VictoriaLogs + Grafana Alloy Observability (`observability/`)** *(Implemented)*
   * **Wave 4 (Operators & Exporters)**:
     * `victoria-metrics-operator` (`0.67.2` + `prometheus-operator-crds` `32.0.2`)
     * `kube-state-metrics` (`8.5.0` with `ServiceMonitor`)
   * **Wave 5 (Core Storage Clusters)**:
     * `victoria-metrics` (`VMCluster` with `vmstorage`, `vmselect`, `vminsert` on Longhorn PVCs)
     * `victoria-logs` (`VLCluster` with `vlstorage`, `vlselect`, `vlinsert` on Longhorn PVCs)
   * **Wave 6 (Auth Gateway, Agents, Scrapers, Alerting & UI)**:
     * `victoria-common` (`VMAuth` gateway, `VMUser` token auth, `VMAgent`, `VLAgent`, `VMAlert`, `VMAlertmanager`, `VMRule` recording/alerting rules, and built-in auth secrets)
     * `grafana-alloy` (Clustered `alloy-external` Deployment for Kubernetes Pod logs, `ServiceMonitor` scraping, Blackbox probing, and Prometheus/Loki/Syslog push receivers)
     * `alloy-daemonset` (Talos-compatible `alloy-linux-ds` DaemonSet for node Unix metrics and kubelet/cAdvisor scraping)
     * `grafana` (`12.3.2` with `victoriametrics-metrics-datasource` & `victoriametrics-logs-datasource` plugins and pre-provisioned `Prometheus`, `VictoriaMetrics`, and `VictoriaLogs` datasources at `grafana.homelab.cloud`)

---

## Project Structure

```text
infra_talos/
├── .gitignore
├── README.md
├── core_services/                         # Layer 3: Core Cluster Services Helm Charts
│   ├── cert-manager/                      # Wave 1: Cert-Manager + Homelab Root CA Secret
│   ├── metallb/                           # Wave 1: MetalLB Controller & Speaker
│   ├── metrics-server/                    # Wave 1: Kubernetes Metrics Server
│   ├── homelab-tls/                       # Wave 2: ClusterIssuer & *.homelab.cloud Certificates
│   ├── metallb-custom-ip-pool/            # Wave 2: MetalLB L2 Pool (10.10.20.125-10.10.20.129)
│   ├── longhorn/                          # Wave 2: Longhorn Distributed Block Storage
│   ├── cnpg-operator/                     # Wave 2: CloudNativePG Operator
│   └── traefik/                           # Wave 3: Traefik Ingress Controller (10.10.20.125)
├── observability/                         # Layer 4: VictoriaMetrics + Alloy + Grafana Stack
│   ├── victoria-metrics-operator/         # Wave 4: VictoriaMetrics Operator + Prometheus CRDs
│   ├── kube-state-metrics/                # Wave 4: Kube-State-Metrics + ServiceMonitor
│   ├── victoria-metrics/                  # Wave 5: VMCluster (vmstorage, vmselect, vminsert)
│   ├── victoria-logs/                     # Wave 5: VLCluster (vlstorage, vlselect, vlinsert)
│   ├── victoria-common/                   # Wave 6: VMAuth, VMUser, VMAgent, VLAgent, VMAlert, VMRule
│   ├── grafana-alloy/                     # Wave 6: Clustered Alloy (Pod logs, ServiceMonitors, Blackbox)
│   ├── alloy-daemonset/                   # Wave 6: Node DaemonSet Alloy (Unix exporter, Kubelet/cAdvisor)
│   └── grafana/                           # Wave 6: Grafana UI + VictoriaMetrics/VictoriaLogs datasources
├── gitops/
│   ├── bootstrap/                         # Local Helm chart for AppProjects & ApplicationSets
│   ├── projects/
│   │   └── app-projects.yaml.tftpl        # ArgoCD AppProjects (core-services, observability, workloads)
│   └── appsets/
│       ├── core-services-appset.yaml.tftpl # Sync-wave ordered Core Services ApplicationSet (Waves 1-3)
│       └── observability-appset.yaml.tftpl # Sync-wave ordered Observability ApplicationSet (Waves 4-6)
└── terraform/
    ├── versions.tf                        # Provider requirements (bpg/proxmox, siderolabs/talos, helm, kubernetes)
    ├── providers.tf                       # Provider configurations
    ├── variables.tf                       # Input variables and validation rules
    ├── talos-image.tf                     # Talos Image Factory schematic & Proxmox ISO download
    ├── vms.tf                             # Proxmox VM definitions (Control Plane & Workers)
    ├── talos-cluster.tf                   # Talos machine configs, bootstrap, kubeconfig/talosconfig generation
    ├── cni.tf                             # Cilium CNI Helm release
    ├── argocd.tf                          # ArgoCD Helm release, AppProjects & ApplicationSets bootstrap
    ├── outputs.tf                         # Cluster endpoints, schematic ID, and credential paths
    ├── terraform.tfvars.example           # Example variable values
    └── templates/
        ├── controlplane-patch.yaml.tftpl  # Control plane machine config patch
        └── worker-patch.yaml.tftpl        # Worker machine config patch (with Longhorn mounts)
```

---

## Ingress Endpoints (`*.homelab.cloud` via Traefik `10.10.20.125`)

| Service | FQDN | Description |
| :--- | :--- | :--- |
| **ArgoCD UI** | `https://argocd-mgmt.homelab.cloud` | GitOps Continuous Delivery UI |
| **Longhorn UI** | `https://longhorn-mgmt.homelab.cloud` | Distributed Block Storage UI |
| **Grafana UI** | `https://grafana.homelab.cloud` | Dashboards & Logs Explorer (VictoriaMetrics + VictoriaLogs) |
| **VictoriaMetrics (`VMAuth`)** | `https://vm.homelab.cloud` | `VMSelect` UI (`/select/0/vmui/`), `VMAgent`, `VMAlert`, `VMAlertmanager` |
| **VictoriaLogs (`VMAuth`)** | `https://vl.homelab.cloud` | `VLSelect` UI (`/select/vmui/`), `VLAgent` |
| **Alloy Logs Push** | `https://alloy-logs.homelab.cloud` | External Loki push endpoint (`/loki/api/v1/push`) |
| **Alloy Metrics Push** | `https://alloy-metrics.homelab.cloud` | External Prometheus remote-write receiver (`/api/v1/write`) |

---

## Quick Start

```bash
cd infra_talos/terraform

# 1. Copy the example variables file and set your Proxmox token secret
cp terraform.tfvars.example terraform.tfvars

# 2. Initialize Terraform providers
terraform init

# 3. Review and apply
terraform plan
terraform apply

# 4. Export generated credentials
export KUBECONFIG="$(pwd)/generated/kubeconfig"
export TALOSCONFIG="$(pwd)/generated/talosconfig"

kubectl get nodes -o wide
```
