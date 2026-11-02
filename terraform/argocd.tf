# ==============================================================================
# Layer 2: ArgoCD & GitOps Bootstrap
# ==============================================================================

locals {
  argocd_domain = var.argocd_domain != "" ? var.argocd_domain : "argocd.${var.base_domain}"
  traefik_lb_ip = var.traefik_lb_ip != "" ? var.traefik_lb_ip : var.metallb_ip_pool_start

  argocd_projects = yamldecode(templatefile("${path.module}/../gitops/projects/app-projects.yaml.tftpl", {
    argocd_namespace = var.argocd_namespace
    gitops_repo_url  = var.gitops_repo_url
  }))

  argocd_core_services_appset = yamldecode(templatefile("${path.module}/../gitops/appsets/core-services-appset.yaml.tftpl", {
    argocd_namespace           = var.argocd_namespace
    gitops_repo_url            = var.gitops_repo_url
    gitops_repo_revision       = var.gitops_repo_revision
    core_services_path         = var.gitops_core_services_path
    base_domain                = var.base_domain
    metallb_ip_pool_start      = var.metallb_ip_pool_start
    metallb_ip_pool_end        = var.metallb_ip_pool_end
    traefik_lb_ip              = local.traefik_lb_ip
    tls_mode                   = var.tls_mode
    tls_issuer_name            = var.tls_issuer_name
    tls_ca_secret_name         = var.tls_ca_secret_name
    tls_wildcard_secret_name   = var.tls_wildcard_secret_name
    acme_email                 = var.acme_email
    acme_server                = var.acme_server
    acme_cloudflare_api_token  = var.acme_cloudflare_api_token
    vault_kv_path              = var.vault_kv_path
    vault_cluster_secret_store = var.vault_cluster_secret_store
    grafana_admin_user         = var.grafana_admin_user
    grafana_admin_password     = var.grafana_admin_password
    alloy_active_token         = var.alloy_active_token
    victoria_active_token      = var.victoria_active_token
    postgres_app_user          = var.postgres_app_user
    postgres_app_password      = var.postgres_app_password
    longhorn_s3_backup_enabled = var.longhorn_s3_backup_enabled
    longhorn_s3_backup_target  = var.longhorn_s3_backup_target
    longhorn_s3_endpoint       = var.longhorn_s3_endpoint
    longhorn_s3_access_key     = var.longhorn_s3_access_key
    longhorn_s3_secret_key     = var.longhorn_s3_secret_key
  }))

  argocd_observability_appset = yamldecode(templatefile("${path.module}/../gitops/appsets/observability-appset.yaml.tftpl", {
    argocd_namespace           = var.argocd_namespace
    gitops_repo_url            = var.gitops_repo_url
    gitops_repo_revision       = var.gitops_repo_revision
    observability_path         = var.gitops_observability_path
    base_domain                = var.base_domain
    cluster_name               = var.cluster_name
    cluster_environment        = var.cluster_environment
    cluster_region             = var.cluster_region
    cluster_owner              = var.cluster_owner
    tls_wildcard_secret_name   = var.tls_wildcard_secret_name
    vault_cluster_secret_store = var.vault_cluster_secret_store
    alloy_active_token         = var.alloy_active_token
    victoria_active_token      = var.victoria_active_token
  }))

  argocd_workloads_appset = yamldecode(templatefile("${path.module}/../gitops/appsets/workloads-appset.yaml.tftpl", {
    argocd_namespace           = var.argocd_namespace
    gitops_repo_url            = var.gitops_repo_url
    gitops_repo_revision       = var.gitops_repo_revision
    workloads_path             = var.gitops_workloads_path
    vault_cluster_secret_store = var.vault_cluster_secret_store
  }))

  argocd_bootstrap_resources = concat(
    local.argocd_projects,
    var.enable_argocd_appsets ? local.argocd_core_services_appset : [],
    var.enable_argocd_appsets ? local.argocd_observability_appset : [],
    var.enable_argocd_appsets && var.enable_workloads_appset ? local.argocd_workloads_appset : [],
  )
}

# 1. Install ArgoCD and its CRDs (Application, ApplicationSet, AppProject)
resource "helm_release" "argocd" {
  count = var.enable_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = true
  cleanup_on_fail  = true

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      global = {
        domain = local.argocd_domain
      }

      redis-ha = {
        enabled = var.argocd_ha_enabled
      }

      controller = {
        replicas = 1
      }

      configs = {
        params = {
          # TLS is terminated at Traefik Ingress
          "server.insecure" = true
        }
        secret = var.argocd_admin_password != "" ? {
          argocdServerAdminPassword = bcrypt(var.argocd_admin_password)
        } : {}
      }

      server = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        autoscaling = {
          enabled     = var.argocd_ha_enabled
          minReplicas = 2
        }
        ingress = {
          enabled          = true
          ingressClassName = "traefik"
          controller       = "generic"
          extraTls = [
            {
              hosts = [local.argocd_domain]
            }
          ]
        }
        resources = {
          requests = {
            cpu    = "100m"
            memory = "192Mi"
          }
          limits = {
            cpu    = "300m"
            memory = "384Mi"
          }
        }
      }

      repoServer = {
        replicas = var.argocd_ha_enabled ? 2 : 1
        autoscaling = {
          enabled     = var.argocd_ha_enabled
          minReplicas = 2
        }
        resources = {
          requests = {
            cpu    = "200m"
            memory = "512Mi"
          }
          limits = {
            cpu    = "800m"
            memory = "768Mi"
          }
        }
      }

      applicationSet = {
        replicas = 1
        resources = {
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
        }
      }
    })
  ]

  depends_on = [
    terraform_data.wait_for_k8s_api,
    helm_release.cilium,
  ]
}

# 2. Deploy AppProjects and ApplicationSets AFTER ArgoCD CRDs are registered
resource "helm_release" "argocd_bootstrap" {
  count = var.enable_argocd ? 1 : 0

  name            = "argocd-bootstrap"
  chart           = "${path.module}/../gitops/bootstrap"
  namespace       = var.argocd_namespace
  cleanup_on_fail = true

  wait    = true
  timeout = 120

  values = [
    yamlencode({
      resources = local.argocd_bootstrap_resources
    })
  ]

  depends_on = [
    helm_release.argocd,
  ]
}

data "kubernetes_secret_v1" "argocd_initial_admin" {
  count = var.enable_argocd && var.argocd_admin_password == "" ? 1 : 0

  metadata {
    name      = "argocd-initial-admin-secret"
    namespace = var.argocd_namespace
  }

  depends_on = [
    helm_release.argocd,
  ]
}

# Export the cluster Root CA certificate to generated/homelab-root-ca.crt for browser/OS trust import
resource "local_file" "root_ca_cert" {
  count = var.tls_mode == "internal-ca" ? 1 : 0

  content         = base64decode(yamldecode(file("${path.module}/../core_services/cert-manager/values.yaml")).rootCA.crt)
  filename        = "${path.module}/generated/homelab-root-ca.crt"
  file_permission = "0644"
}
