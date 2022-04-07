terraform {
  required_version = ">= 1.0.2"
}

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}

locals {
  app_dns_name = "${var.dns_record_name}.${var.root_dns_name}"
}

module "ec2_sg" {
  source = "terraform-aws-modules/security-group/aws"

  name   = "${var.app_name}-sg"
  vpc_id = data.aws_vpc.default.id

  ingress_cidr_blocks = ["0.0.0.0/0"]
  ingress_rules       = ["http-80-tcp", "https-443-tcp", "ssh-tcp"]
  egress_rules = ["all-all"]
}

resource "aws_key_pair" "ec2_ssh_key_id" {
  key_name   = "ec2ssh"
  public_key = file(var.pub_ssh_key_path)
}

module "ec2_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 3.0"

  name = "${var.app_name}-ec2"

  ami                    = var.ec2_ami_id
  instance_type          = "t2.small"
  key_name               = aws_key_pair.ec2_ssh_key_id.id
  monitoring             = true
  vpc_security_group_ids = [module.ec2_sg.security_group_id]

# TODO: interpolation inside user_data EOF not working -> ${local.app_dns_name}
  user_data                   = <<EOF
#!/bin/bash
export PATH=/usr/local/bin:$PATH;

yum update
yum install docker -y
service docker start
usermod -a -G docker ec2-user
curl -L https://github.com/docker/compose/releases/download/1.29.2/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose
chown root:docker /usr/local/bin/docker-compose
mkdir -p /home/ec2-user/nginx.conf

cat <<EODCF >/home/ec2-user/docker-compose.yml
version: "3"

services:
  webserver:
    image: nginx:latest
    ports:
      - 80:80
      - 443:443
    restart: always
    volumes:
      - ./nginx.conf/:/etc/nginx/conf.d/:ro
      - ./certbot/www:/var/www/certbot/:ro
      - ./certbot/conf/:/etc/nginx/ssl/:ro
  certbot:
    image: certbot/certbot:latest
    volumes:
      - ./certbot/www/:/var/www/certbot/:rw
      - ./certbot/conf/:/etc/letsencrypt/:rw
EODCF

cat <<EOCONF >/home/ec2-user/nginx.conf/default.conf
server {
    listen 80;
    listen [::]:80;

    server_name ${local.app_dns_name} www.${local.app_dns_name};
    server_tokens off;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://${local.app_dns_name}$request_uri;
    }
}

server {
    listen 443 default_server ssl http2;
    listen [::]:443 ssl http2;

    server_name ${local.app_dns_name};

    ssl_certificate /etc/nginx/ssl/live/${local.app_dns_name}/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/${local.app_dns_name}/privkey.pem;
    
    location / {
    	root      html;
    }
}
EOCONF

chown ec2-user:ec2-user /home/ec2-user/docker-compose.yml
/usr/local/bin/docker-compose -f /home/ec2-user/docker-compose.yml up -d
EOF

}


resource "aws_route53_record" "www" {
  zone_id = var.r53_zone_id
  name    = var.dns_record_name
  type    = "A"
  ttl     = "300"
  records = [module.ec2_instance.public_ip]
}