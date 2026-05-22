locals {
  k8s_enabled = var.enable_k8s_resources
}

data "aws_eks_cluster" "main" {
  count      = local.k8s_enabled ? 1 : 0
  name       = module.eks_cluster.cluster_name
  depends_on = [module.eks_cluster]
}

provider "kubernetes" {
  host                   = local.k8s_enabled ? data.aws_eks_cluster.main[0].endpoint : "https://0.0.0.0"
  cluster_ca_certificate = local.k8s_enabled ? base64decode(data.aws_eks_cluster.main[0].certificate_authority[0].data) : ""

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      local.k8s_enabled ? data.aws_eks_cluster.main[0].name : "placeholder",
      "--region",
      var.aws_region,
    ]
  }
}

provider "helm" {
  kubernetes {
    host                   = local.k8s_enabled ? data.aws_eks_cluster.main[0].endpoint : "https://0.0.0.0"
    cluster_ca_certificate = local.k8s_enabled ? base64decode(data.aws_eks_cluster.main[0].certificate_authority[0].data) : ""

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks",
        "get-token",
        "--cluster-name",
        local.k8s_enabled ? data.aws_eks_cluster.main[0].name : "placeholder",
        "--region",
        var.aws_region,
      ]
    }
  }
}

provider "kubectl" {
  host                   = local.k8s_enabled ? data.aws_eks_cluster.main[0].endpoint : "https://0.0.0.0"
  cluster_ca_certificate = local.k8s_enabled ? base64decode(data.aws_eks_cluster.main[0].certificate_authority[0].data) : ""
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks",
      "get-token",
      "--cluster-name",
      local.k8s_enabled ? data.aws_eks_cluster.main[0].name : "placeholder",
      "--region",
      var.aws_region,
    ]
  }
}

resource "helm_release" "ingress_nginx" {
  count            = local.k8s_enabled ? 1 : 0
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  atomic           = false
  cleanup_on_fail  = false
  wait             = true
  timeout          = 1200

  set {
    name  = "controller.replicaCount"
    value = "1"
  }

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.resources.requests.cpu"
    value = "50m"
  }

  set {
    name  = "controller.resources.requests.memory"
    value = "90Mi"
  }
}

resource "helm_release" "cert_manager" {
  count            = local.k8s_enabled ? 1 : 0
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 1200

  set {
    name  = "crds.enabled"
    value = "true"
  }
}

resource "helm_release" "metrics_server" {
  count           = local.k8s_enabled ? 1 : 0
  name            = "metrics-server"
  repository      = "https://kubernetes-sigs.github.io/metrics-server/"
  chart           = "metrics-server"
  namespace       = "kube-system"
  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 1200

  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }
}

resource "helm_release" "external_secrets" {
  count            = local.k8s_enabled ? 1 : 0
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  atomic           = true
  cleanup_on_fail  = true
  wait             = true
  timeout          = 1200

  set {
    name  = "installCRDs"
    value = "true"
  }
}

resource "kubernetes_namespace" "rental" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name = "rental"
    labels = {
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
      "pod-security.kubernetes.io/warn"            = "restricted"
      "pod-security.kubernetes.io/warn-version"    = "latest"
      "pod-security.kubernetes.io/audit"           = "restricted"
      "pod-security.kubernetes.io/audit-version"   = "latest"
    }
  }
}

resource "kubernetes_service_account" "rental_api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-api"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_service_account" "rental_client" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-client"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }
  automount_service_account_token = false
}

resource "kubernetes_service_account" "external_secrets" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = var.external_secrets_service_account
    namespace = kubernetes_namespace.rental[0].metadata[0].name
    annotations = {
      "eks.amazonaws.com/role-arn" = module.eks_cluster.external_secrets_role_arn
    }
  }
  automount_service_account_token = true
}

resource "kubernetes_role" "api_config_reader" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-api-config-reader"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["rental-api-config"]
    verbs          = ["get"]
  }
}

resource "kubernetes_role_binding" "api_config_reader" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-api-config-reader"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role.api_config_reader[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.rental_api[0].metadata[0].name
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }
}

resource "kubernetes_config_map" "rental_api_config" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-api-config"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  data = {
    NODE_ENV                = "production"
    PORT                    = "4000"
    SESSION_MAX_AGE_MS      = "86400000"
    CLIENT_URL              = "http://${var.ingress_host}"
    SESSION_COOKIE_SECURE   = "false"
    SESSION_COOKIE_SAME_SITE = "lax"
  }
}

resource "kubernetes_deployment" "api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "api-deployment"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
    labels = {
      app = "api"
    }
  }

  spec {
    replicas               = 2
    revision_history_limit = 5

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        app = "api"
      }
    }

    template {
      metadata {
        labels = {
          app = "api"
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.rental_api[0].metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = 30

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              app = "api"
            }
          }
        }

        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "api"
          image             = var.api_image
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 4000
          }

          env_from {
            config_map_ref {
              name = kubernetes_config_map.rental_api_config[0].metadata[0].name
            }
          }

          env_from {
            secret_ref {
              name = "rental-api-secrets"
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          volume_mount {
            name       = "app-cache"
            mount_path = "/app/.cache"
          }

          resources {
            requests = {
              cpu    = "200m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/readyz"
              port = "http"
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            initial_delay_seconds = 20
            period_seconds        = 15
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          startup_probe {
            http_get {
              path = "/healthz"
              port = "http"
            }
            period_seconds    = 5
            failure_threshold = 12
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 10001
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "64Mi"
          }
        }

        volume {
          name = "app-cache"
          empty_dir {
            size_limit = "128Mi"
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_service_account.rental_api,
    kubernetes_config_map.rental_api_config,
    kubectl_manifest.external_secrets,
  ]
}

resource "kubernetes_deployment" "client" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "client-deployment"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
    labels = {
      app = "client"
    }
  }

  spec {
    replicas               = 2
    revision_history_limit = 5

    strategy {
      type = "RollingUpdate"
      rolling_update {
        max_surge       = 1
        max_unavailable = 0
      }
    }

    selector {
      match_labels = {
        app = "client"
      }
    }

    template {
      metadata {
        labels = {
          app = "client"
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.rental_client[0].metadata[0].name
        automount_service_account_token  = false
        termination_grace_period_seconds = 30

        topology_spread_constraint {
          max_skew           = 1
          topology_key       = "kubernetes.io/hostname"
          when_unsatisfiable = "ScheduleAnyway"
          label_selector {
            match_labels = {
              app = "client"
            }
          }
        }

        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name              = "client"
          image             = var.client_image
          image_pull_policy = "Always"

          port {
            name           = "http"
            container_port = 8080
          }

          volume_mount {
            name       = "nginx-cache"
            mount_path = "/var/cache/nginx"
          }

          volume_mount {
            name       = "nginx-run"
            mount_path = "/var/run"
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          liveness_probe {
            http_get {
              path = "/"
              port = "http"
            }
            initial_delay_seconds = 15
            period_seconds        = 20
            timeout_seconds       = 3
            failure_threshold     = 3
          }

          security_context {
            run_as_non_root            = true
            run_as_user                = 101
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }
        }

        volume {
          name = "nginx-cache"
          empty_dir {
            size_limit = "128Mi"
          }
        }

        volume {
          name = "nginx-run"
          empty_dir {
            size_limit = "16Mi"
          }
        }

        volume {
          name = "tmp"
          empty_dir {
            size_limit = "64Mi"
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_account.rental_client]
}

resource "kubernetes_service" "api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "api-service"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    selector = {
      app = "api"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 4000
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_service" "client" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "client-service"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    selector = {
      app = "client"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }

    type = "ClusterIP"
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "api-hpa"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    max_replicas = 6
    min_replicas = 2

    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.api[0].metadata[0].name
    }

    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }

    metric {
      type = "Resource"
      resource {
        name = "memory"
        target {
          type                = "Utilization"
          average_utilization = 75
        }
      }
    }

    behavior {
      scale_up {
        stabilization_window_seconds = 0
        select_policy                 = "Max"
        policy {
          type           = "Percent"
          value          = 100
          period_seconds = 60
        }
        policy {
          type           = "Pods"
          value          = 2
          period_seconds = 60
        }
      }

      scale_down {
        stabilization_window_seconds = 300
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "api-pdb"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    max_unavailable = 1
    selector {
      match_labels = {
        app = "api"
      }
    }
  }
}

resource "kubernetes_pod_disruption_budget_v1" "client" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "client-pdb"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    max_unavailable = 1
    selector {
      match_labels = {
        app = "client"
      }
    }
  }
}

resource "kubernetes_ingress_v1" "rental" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "rental-ingress"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
    annotations = {
      "nginx.ingress.kubernetes.io/proxy-body-size"   = "10m"
      "nginx.ingress.kubernetes.io/limit-rps"         = "20"
      "nginx.ingress.kubernetes.io/limit-connections" = "20"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.ingress_host
      http {
        path {
          path      = "/healthz"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.api[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/readyz"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.api[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/api"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.api[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"
          backend {
            service {
              name = kubernetes_service.client[0].metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.ingress_nginx]
}

resource "kubernetes_network_policy" "default_deny" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "default-deny-all"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress", "Egress"]
  }
}

resource "kubernetes_network_policy" "allow_api_dns" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "allow-api-dns-egress"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "api"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = 53
      }

      ports {
        protocol = "TCP"
        port     = 53
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_client_dns" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "allow-client-dns-egress"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "client"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            "k8s-app" = "kube-dns"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = 53
      }

      ports {
        protocol = "TCP"
        port     = 53
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_ingress_to_api" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "allow-ingress-to-api"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "api"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/component" = "controller"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 4000
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_ingress_to_client" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "allow-ingress-to-client"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "client"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "ingress-nginx"
          }
        }
        pod_selector {
          match_labels = {
            "app.kubernetes.io/component" = "controller"
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = 8080
      }
    }
  }
}

resource "kubernetes_network_policy" "allow_api_egress_external" {
  count = local.k8s_enabled ? 1 : 0
  metadata {
    name      = "allow-api-egress-external"
    namespace = kubernetes_namespace.rental[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        app = "api"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        ip_block {
          cidr = "50.17.212.222/32"
        }
      }

      to {
        ip_block {
          cidr = "182.176.170.78/32"
        }
      }

      to {
        ip_block {
          cidr = "3.224.67.210/32"
        }
      }

      ports {
        protocol = "TCP"
        port     = 443
      }

      ports {
        protocol = "TCP"
        port     = 27017
      }
    }
  }
}

resource "kubectl_manifest" "cluster_issuer" {
  count = local.k8s_enabled ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = "platform@rental.example.com"
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [helm_release.cert_manager]
}

resource "kubectl_manifest" "secret_store" {
  count = local.k8s_enabled ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "SecretStore"
    metadata = {
      name      = "rental-aws-secrets"
      namespace = kubernetes_namespace.rental[0].metadata[0].name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.aws_region
          auth = {
            jwt = {
              serviceAccountRef = {
                name = kubernetes_service_account.external_secrets[0].metadata[0].name
              }
            }
          }
        }
      }
    }
  })

  depends_on = [
    helm_release.external_secrets,
    kubernetes_service_account.external_secrets,
  ]
}

resource "kubectl_manifest" "external_secrets" {
  count = local.k8s_enabled ? 1 : 0
  yaml_body = yamlencode({
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = "rental-api-secrets"
      namespace = kubernetes_namespace.rental[0].metadata[0].name
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef = {
        name = "rental-aws-secrets"
        kind = "SecretStore"
      }
      target = {
        name           = "rental-api-secrets"
        creationPolicy = "Owner"
      }
      data = [
        {
          secretKey = "MONGODB_URI"
          remoteRef = {
            key = "${var.secret_prefix}/mongodb_uri"
          }
        },
        {
          secretKey = "SESSION_SECRET"
          remoteRef = {
            key = "${var.secret_prefix}/session_secret"
          }
        },
        {
          secretKey = "JWT_SECRET"
          remoteRef = {
            key = "${var.secret_prefix}/jwt_secret"
          }
        },
      ]
    }
  })

  depends_on = [
    kubectl_manifest.secret_store,
    helm_release.external_secrets,
  ]
}
