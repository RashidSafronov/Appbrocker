
data "terraform_remote_state" "gke" {
  backend = "local"

  config = {
    path = "../gk/terraform.tfstate"
  }
}

# Retrieve GKE cluster information
provider "google" {
  project = data.terraform_remote_state.gke.outputs.project_id
  region  = data.terraform_remote_state.gke.outputs.region
}

# Configure kubernetes provider with Oauth2 access token.
# https://registry.terraform.io/providers/hashicorp/google/latest/docs/data-sources/client_config
# This fetches a new token, which will expire in 1 hour.
data "google_client_config" "default" {}

data "google_container_cluster" "my_cluster" {
  name     = data.terraform_remote_state.gke.outputs.kubernetes_cluster_name
  location = data.terraform_remote_state.gke.outputs.region
}

provider "kubernetes" {
  host = data.terraform_remote_state.gke.outputs.kubernetes_cluster_host

  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(data.google_container_cluster.my_cluster.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "test" {
  metadata {
    name = "helloworld-namespace"
  }
}
resource "kubernetes_deployment" "helloworld" {
  metadata {
    name = "helloworld"
    namespace = kubernetes_namespace.test.metadata.0.name
    labels = {
      app = "hello-app"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "hello-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "hello-app"
        }
      }
      spec {
        container {
          image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.project_id}-repo/hello-app:v2"
         
          name  = "example"

          port {
            container_port = 8080
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "512Mi"
            }
            requests = {
              cpu    = "250m"
              memory = "50Mi"
            }
          }
        }
      }
    }
  }
}
resource "kubernetes_service" "test" {
  metadata {
    name      = "helloworld"
    namespace = kubernetes_namespace.test.metadata.0.name
      }
  spec {
    selector = {
      app = kubernetes_deployment.helloworld.spec.0.template.0.metadata.0.labels.app
    }
    type = "LoadBalancer"
    session_affinity = "ClientIP"
    port {
      
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_horizontal_pod_autoscaler" "helloworldhpa" {
  metadata {
    name = "helloworldhpa"
  }
  spec {
    max_replicas = 3
    min_replicas = 2
    target_cpu_utilization_percentage = 50
    scale_target_ref {
      kind = "Deployment"
      name = "helloworld"
    }
  }
}