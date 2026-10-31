# ==============================================================================
# Layer 2: ArgoCD & GitOps Bootstrap
# ==============================================================================

locals {
  argocd_projects = yamldecode(templatefile("${path.module}/../gitops/projects/app-projects.yaml.tftpl", {
    argocd_namespace = var.argocd_namespace
    gitops_repo_url  = var.gitops_repo_url
  }))

  argocd_core_services_appset = yamldecode(templatefile("${path.module}/../gitops/appsets/core-services-appset.yaml.tftpl", {
    argocd_namespace     = var.argocd_namespace
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
    core_services_path   = var.gitops_core_services_path
  }))

  argocd_observability_appset = yamldecode(templatefile("${path.module}/../gitops/appsets/observability-appset.yaml.tftpl", {
    argocd_namespace     = var.argocd_namespace
    gitops_repo_url      = var.gitops_repo_url
    gitops_repo_revision = var.gitops_repo_revision
    observability_path   = var.gitops_observability_path
  }))

  argocd_bootstrap_resources = concat(
    local.argocd_projects,
    var.enable_argocd_appsets ? local.argocd_core_services_appset : [],
    var.enable_argocd_appsets ? local.argocd_observability_appset : [],
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
        domain = var.argocd_domain
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
              hosts = [var.argocd_domain]
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
