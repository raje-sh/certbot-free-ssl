variable "aws_region" {
  type = string
}
variable "app_name" {
  type = string
}
variable "pub_ssh_key_path" {
  type = string
}
variable "ec2_ami_id" {
  type = string
}
variable "root_dns_name" {
  type = string
  default = "example.com"
}
variable "r53_zone_id" {
  type = string
}
variable "dns_record_name" {
  type = string
  default = "test"
}

