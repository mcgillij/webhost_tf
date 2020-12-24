##############################################################
# Data sources to get VPC, subnets and security group details
##############################################################
data "aws_vpc" "default" {
  default = true
}

data "aws_subnet_ids" "all" {
  vpc_id = data.aws_vpc.default.id
}

data "aws_security_group" "default" {
  vpc_id = data.aws_vpc.default.id
  name   = "default"
}

#########################
# S3 bucket for ELB logs
#########################
data "aws_elb_service_account" "this" {}

resource "aws_s3_bucket" "logs" {
  bucket        = "elb-logs-mcgillij"
  acl           = "private"
  policy        = data.aws_iam_policy_document.logs.json
  force_destroy = true
}

data "aws_iam_policy_document" "logs" {
  statement {
    actions = [
      "s3:PutObject",
    ]

    principals {
      type        = "AWS"
      identifiers = [data.aws_elb_service_account.this.arn]
    }

    resources = [
      "arn:aws:s3:::elb-logs-mcgillij/*",
    ]
  }
}

######
# ELB
######

module "elb_http" {
  source  = "terraform-aws-modules/elb/aws"
  version = "~> 2.0"

  name = "mcgillij-webhost-elb"

  subnets         = data.aws_subnet_ids.all.ids
  security_groups = [data.aws_security_group.default.id]
  internal        = false

  listener = [
    {
      instance_port     = "80"
      instance_protocol = "http"
      lb_port           = "443"
      lb_protocol       = "https"
      ssl_certificate_id = "arn:aws:acm:us-east-2:852654189925:certificate/dac82d11-91c4-4fb6-8195-a03485615504"
    },
  ]

  health_check = {
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
  }

  access_logs = {
    bucket = aws_s3_bucket.logs.bucket
  }

  // ELB attachments
  number_of_instances = 1
  instances           = module.ec2_instances.id
  
  tags = {
    Owner       = "mcgillij"
    Environment = "dev"
  }
}

################
# EC2 instances
################
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  # amazon linux 2
  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm*"]
  }
}
module "ec2_profile" {
  source = "../modules/ec2/instance-profile"
  name   = "webhost_instance_profile"
}

module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  instance_count = 1

  name                        = "webhost"
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [data.aws_security_group.default.id]
  subnet_id                   = element(tolist(data.aws_subnet_ids.all.ids), 0)
  associate_public_ip_address = false
  user_data = data.template_file.user_data.rendered
  iam_instance_profile = module.ec2_profile.this_iam_instance_profile_id
}

data "template_file" "user_data" {
  template = file("../modules/ec2/templates/user-data.yaml")
  vars = {
    aws_region             = "us-east-2"
    docker_compose_content = filebase64("../modules/ec2/templates/docker-compose.yml")
  }
}
