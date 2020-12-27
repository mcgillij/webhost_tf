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

## Security Groups

resource "aws_security_group" "allow_http_and_https" {
  name        = "allow_http_and_https"
  description = "Allow https inbound traffic"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from VPC"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

#  egress {
#    from_port       = 80
#    to_port         = 80
#    protocol        = "tcp"
#    security_groups = [data.aws_security_group.default.id]
#  }

  tags = {
    Name = "allow_http_and_https"
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
  name   = "webhost_instance_profile2"
}

module "ec2_instances" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "~> 2.0"

  instance_count = 1

  name                        = "webhost2"
  ami                         = data.aws_ami.amazon_linux_2.id
  instance_type               = "t2.micro"
  vpc_security_group_ids      = [data.aws_security_group.default.id, aws_security_group.allow_http_and_https.id]
  subnet_id                   = element(tolist(data.aws_subnet_ids.all.ids), 0)
  associate_public_ip_address = true
  user_data                   = data.template_file.user_data.rendered
  iam_instance_profile        = module.ec2_profile.this_iam_instance_profile_id
}

data "template_file" "user_data" {
  template = file("../modules/ec2/templates/user-data.yaml")
  vars = {
    aws_region             = "us-east-2"
    docker_compose_content = filebase64("../modules/ec2/templates/docker-compose.yml")
  }
}
