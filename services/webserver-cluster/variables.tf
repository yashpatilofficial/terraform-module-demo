variable "server_port" {
  description = "Port number for serving http request"
  type        = number
  default = 8080
}

variable "cluster_name" {
  description = "The name to be used for all the cluster resources"
  type = string
}

variable "db_remote_state_bucket" {
  description = "The name S3 bucket for remote state storage"
  type = string
}

variable "db_remote_state_key" {
  description = "The path of database's remote state"
  type = string
}
