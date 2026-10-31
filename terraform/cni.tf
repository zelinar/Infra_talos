# ==============================================================================
# CNI Layer (Cilium)
# ==============================================================================

resource "helm_release" "cilium" {
  count = var.cni_provider == "cilium" ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      ipam = {
        mode = "kubernetes"
      }
      kubeProxyReplacement = true
      # Talos KubePrism local API server proxy on every node
      k8sServiceHost = "localhost"
      k8sServicePort = 7445
      cgroup = {
        autoMount = {
          enabled = false
        }
        hostRoot = "/sys/fs/cgroup"
      }
      securityContext = {
        capabilities = {
          ciliumAgent = [
            "CHOWN",
            "KILL",
            "NET_ADMIN",
            "NET_RAW",
            "IPC_LOCK",
            "SYS_ADMIN",
            "SYS_RESOURCE",
            "DAC_OVERRIDE",
            "FOWNER",
            "SETGID",
            "SETUID"
          ]
          cleanCiliumState = [
            "NET_ADMIN",
            "SYS_ADMIN",
            "SYS_RESOURCE"
          ]
        }
      }
      hubble = {
        enabled = true
        relay = {
          enabled = true
        }
        ui = {
          enabled = true
        }
      }
      operator = {
        replicas = 1
      }
    })
  ]

  depends_on = [
    terraform_data.wait_for_k8s_api,
  ]
}
