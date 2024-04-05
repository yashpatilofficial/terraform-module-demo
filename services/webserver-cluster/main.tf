terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"

    }
  }

  backend "s3" {
    #bucket data
    bucket = "learn-terraform-state-bucket-0"
    key = "stage/services/webserver-cluster"
    region = "ap-south-1"
    profile = "lspl_power_user"

    #dynamoDB data
    dynamodb_table = "terraform-state-locks"
    encrypt = true
  }

  required_version = ">= 1.2.0"
}

locals {
  http_port = 80
  any_port = 0
  any_protocol = -1
  tcp_protocol = "tcp"
  all_ips = ["0.0.0.0/0"]
}

# resource "aws_vpc" "vpc_main" {
#   cidr_block = "190.10.0.0/24"

#   tags = {
#     Name = "vpc_main"
#   }
# }

# resource "aws_subnet" "subnet_0" {
#   vpc_id            = aws_vpc.vpc_main.id
#   cidr_block        = "190.10.0.0/26"
#   availability_zone = "ap-south-1a"

#   tags = {
#     Name = "subnet_0"
#   }
# }

resource "aws_security_group" "sg_0" {
  name = "${var.cluster_name}-instance"
  # vpc_id = aws_vpc.vpc_main.id
}

resource "aws_security_group_rule" "allow_http_inbound" {
  type = "ingress"
  security_group_id = aws_autoscaling_group.asg_0.id

  from_port   = var.server_port
  to_port     = var.server_port
  protocol    = local.tcp_protocol
  cidr_blocks = local.all_ips
}

resource "aws_launch_configuration" "app_server" {
  image_id      = "ami-007020fd9c84e18c7"
  instance_type = "t2.micro"
  # subnet_id              = aws_subnet.subnet_0.id
  security_groups             = [aws_security_group.sg_0.id]
  associate_public_ip_address = true

  # user_data = <<EOF
  #                   #!/bin/bash
  #                   echo "Hello World" >> index.html
  #                   echo "${data.terraform_remote_state.db.outputs.address}" >> index.html
  #                   echo "${data.terraform_remote_state.db.outputs.port}" >> index.html
  #                   nohup busybox httpd -f -p ${var.server_port} &
  #               EOF

  user_data = templatefile("${path.module}/user-data.sh",{
    server_port = var.server_port
    db_address = data.terraform_remote_state.db.outputs.address
    db_port = data.terraform_remote_state.db.outputs.port

  })


  lifecycle {
    create_before_destroy = true
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_autoscaling_group" "asg_0" {
  launch_configuration = aws_launch_configuration.app_server.name
  # vpc_zone_identifier  = [aws_subnet.subnet_0.id]
  vpc_zone_identifier = data.aws_subnets.default_subnets.ids

  target_group_arns = [aws_lb_target_group.asg.arn]
  health_check_type = "ELB"

  min_size = 2
  max_size = 10

  desired_capacity = 2

  tag {
    key                 = "Name"
    value               = "${var.cluster_name}-asg"
    propagate_at_launch = true
  }
}

resource "aws_lb" "example" {
  name = "${var.cluster_name}-lb"
  load_balancer_type = "application"
  subnets            = data.aws_subnets.default_subnets.ids
  security_groups    = [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.example.arn
  port              = local.http_port
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "404:not found"
      status_code  = 404
    }
  }
}

resource "aws_security_group" "alb" {
  name = "${var.cluster_name}-alb"
}

#defining the rules seperately to make sure addition of rules afterwards stays easy
resource "aws_security_group_rule" "allow_http_inbound_alb" {
  type = "ingress"
  security_group_id = aws_security_group.alb.id

    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
}

resource "aws_security_group_rule" "allow_http_inbound_alb" {
  type = "egress"
  security_group_id = aws_security_group.alb.id

    from_port   = local.http_port
    to_port     = local.http_port
    protocol    = local.tcp_protocol
    cidr_blocks = local.all_ips
}

resource "aws_lb_target_group" "asg" {
  name     = "terraform-asg-example"
  port     = var.server_port
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener_rule" "asg" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  condition {
    path_pattern {
      values = ["*"]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.asg.arn
  }
}

data "terraform_remote_state" "db" {
  backend = "s3"

  config = {
    bucket = var.db_remote_state_bucket
    key = var.db_remote_state_key
    region = "ap-south-1"
    profile = "lspl_power_user"
  }
}
