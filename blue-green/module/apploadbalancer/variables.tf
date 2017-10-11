variable "app_name" {
    type = "string"
}
variable "vpc_id" {
    type = "string"
}
variable "subnet_ids" {
    type = "list"
}
variable "security_groups" {
    type = "list"
}