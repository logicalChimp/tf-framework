terraform {
  required_version = ">= 0.11.8"
  backend          "gcs"            {}
}

provider "google" {
  version = "~> 1.17.1"
  project = "${var.project}"
  region  = "${var.region}"
}

data "google_project" "project" {
  project_id = "${var.project}"
}
