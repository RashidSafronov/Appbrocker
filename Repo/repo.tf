
resource "google_artifact_registry_repository" "my-repo" {
  provider = google-beta

  location = var.region
  repository_id = "${var.project_id}-repo"
  description = "example docker repository"
  format = "DOCKER"
	provisioner "local-exec" {    command = "docker build -f kubernetes-engine-samples\\hello-app\\Dockerfile kubernetes-engine-samples\\hello-app -t ${var.region}-docker.pkg.dev/${var.project_id}/${var.project_id}-repo/hello-app:v2 "  }
	provisioner "local-exec" {    command = "gcloud auth configure-docker ${var.region}-docker.pkg.dev"  }
	provisioner "local-exec" {    command = "docker push ${var.region}-docker.pkg.dev/${var.project_id}/${var.project_id}-repo/hello-app:v2"  }



}
