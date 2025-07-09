# main.tf - Deliberately problematic for debugging dependencies and timing

resource "aws_vpc" "main_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.common_tags, { Name = "${var.project_name}-vpc" })
}

resource "aws_internet_gateway" "gw" {
  # BUG 1: Implicit dependency on vpc_id for attachment, but what if attachment itself is slow
  # and other resources try to use the IGW too soon for routing?
  # No explicit vpc_id here, relying on attachment resource, which is fine, but the problem is subtle.
  tags = merge(var.common_tags, { Name = "${var.project_name}-igw" })
}

# Attempt to attach IGW to VPC.
# This resource itself creates an explicit dependency for things using aws_internet_gateway.gw.id
# BUT the *state* of the attachment (i.e., routing being possible) is not guaranteed by this alone.
resource "aws_internet_gateway_attachment" "gw_attachment" {
  internet_gateway_id = aws_internet_gateway.gw.id # Correctly refers to the IGW
  vpc_id              = aws_vpc.main_vpc.id       # Correctly refers to the VPC
  # No explicit depends_on here, but Terraform should see the dependencies through interpolations.
  # The issue might be that downstream resources don't wait for this attachment to be "effective".
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = true
  availability_zone       = "${var.aws_region}a" # Example AZ
  tags                    = merge(var.common_tags, { Name = "${var.project_name}-public-subnet" })
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.main_vpc.id
  tags   = merge(var.common_tags, { Name = "${var.project_name}-public-rt" })
  # BUG 2: Route creation might be attempted before IGW is fully attached and ready for routing.
  # The route resource below refers to `aws_internet_gateway.gw.id`.
  # While `aws_internet_gateway_attachment.gw_attachment` depends on both,
  # there's no direct link from `aws_route.public_route_to_igw` to `gw_attachment`
  # ensuring the attachment is "complete" before the route is created.
}

resource "aws_route" "public_route_to_igw" {
  route_table_id         = aws_route_table.public_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.gw.id # Depends on IGW creation
  # This needs to implicitly wait for the IGW to be attached to the VPC.
  # If aws_internet_gateway_attachment is slow, this route creation can fail.
  # Terraform might see dependency on `aws_internet_gateway.gw` but not necessarily on `aws_internet_gateway_attachment.gw_attachment`
  # unless an output from gw_attachment is used or explicit depends_on.
}

resource "aws_route_table_association" "public_subnet_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
  # This is generally okay, but its successful operation depends on the route table and subnet existing.
}

# BUG 3: Security group created for the VPC.
# Sometimes, creating a security group immediately after VPC creation can face issues if the VPC
# isn't fully "ready" in all AWS backend systems, though this is rarer.
# The more complex issue here is if something tries to USE this security group too quickly
# in an EC2 instance definition (not part of this TF, but a common scenario).
# For this task, the problem is more about the dependencies *above* this SG.
# Let's make this SG depend on something that might be problematic or slow.
# e.g. if it had rules pointing to another SG or prefix list that itself has complex dependencies.
# For this example, the main issue is that if any of the above network resources fail,
# the SG might also fail or be orphaned. The real challenge is fixing the above.
resource "aws_security_group" "allow_http_ssh" {
  name        = "${var.project_name}-allow-http-ssh"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.main_vpc.id # Correct dependency on VPC

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1" # All protocols
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-sg-http-ssh" })

  # To make it more complex and prone to failure if things are not ready:
  # Let's add a self-referential rule, which is valid but can sometimes expose timing issues
  # if the SG itself isn't registered quickly enough for its own ID to be used.
  # (This is a bit contrived for SG self-ref, but illustrates dependency complexity).
  # This specific type of self-ref rule is usually fine.
  # The primary bugs are in the IGW attachment and route creation order.
}


# Outputs (useful for verification)
output "vpc_id" {
  value = aws_vpc.main_vpc.id
}
output "public_subnet_id" {
  value = aws_subnet.public_subnet.id
}
output "igw_id" {
  value = aws_internet_gateway.gw.id
}
output "route_table_id" {
  value = aws_route_table.public_route_table.id
}
output "security_group_id" {
  value = aws_security_group.allow_http_ssh.id
}
output "igw_attachment_status" {
  # This output might not be directly useful for dependency, but for debugging.
  # It depends on the attachment resource.
  value = aws_internet_gateway_attachment.gw_attachment.id # Using id just to show dependency
}
