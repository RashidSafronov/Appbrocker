
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
/*
resource "kubernetes_deployment" "sqlproxy" {
  metadata {
    name = "sqlproxy"
    namespace = kubernetes_namespace.test.metadata.0.name
    labels = {
      app = "sqlproxy"
    }
  }

  spec {
    replicas = 2
    selector {
      match_labels = {
        app = "sqlproxy"
      }
    }
    template {
      metadata {
        labels = {
          app = "sqlproxy"
        }
      }
      spec {
        container {
          image = "gcr.io/cloudsql-docker/gce-proxy:latest"
         
          name  = "sqlproxy"

          port {
            container_port = 3306
          }

          resources {
            limits = {
              cpu    = "0.5"
              memory = "2Gi"
            }
            requests = {
              cpu    = "0.5"
              memory = "512Mi"
            }
          }
        }
      }
    }
  }
}

*/
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


resource "google_filestore_instance" "instance" {
  name = "helloworld-instance"
  zone = "${var.region}-b"
  tier = "BASIC_HDD"

  file_shares {
    capacity_gb = 1260
    name        = "share1"
  }

  networks {
    network = "${var.project_id}-vpc"
    modes   = ["MODE_IPV4"]
  }
}


resource "kubernetes_persistent_volume" "persistentvolume" {
  metadata {
    name = "share1"
  }
  spec {
    capacity = {
      storage = "2Gi"
    }
    
    access_modes = ["ReadWriteMany"]
    persistent_volume_source {
      nfs {
        server = google_filestore_instance.instance.networks[0].ip_addresses[0]
        path = "/${google_filestore_instance.instance.file_shares[0].name}"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "app" {
  metadata {
    name = "app-${var.project_id}"
  }
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "2Gi"
      }
    }
    volume_name = kubernetes_persistent_volume.persistentvolume.metadata.0.name
    storage_class_name = "standard"
  }
}