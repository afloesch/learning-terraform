variable "region" {
	default = "us-west-1"
}
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "ssh_key" {}
variable "aws_ami" {
	default = "ami-3a674d5a"
}
variable "bucket_name" {}

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "us-west-1"
}

resource "aws_s3_bucket" "b" {
  bucket = "${var.bucket_name}"
  acl = "public-read"
}

resource "aws_s3_bucket_object" "config" {
  bucket = "${aws_s3_bucket.b.bucket}"
  key = "my.cnf"
  source = "config/my.cnf"
  content_type = "plain/text"
  etag = "${md5(file("config/my.cnf"))}"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "aws.test"
  public_key = "${file(var.ssh_key)}"
}

# create bastion host to access application boxes
resource "aws_instance" "bastion" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.bastion.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"
    tags {
        Name = "Bastion"
    }
}

resource "aws_instance" "db" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.public.id}"]
    subnet_id = "${aws_subnet.us-west-1a-private.id}"
    depends_on = ["aws_nat_gateway.default", "aws_s3_bucket_object.config"]

    tags {
      Name = "MySQL"
    }

    ebs_block_device {
      device_name = "/dev/sdh"
      volume_type = "standard"
      iops = "150"
      volume_size = "50"
      delete_on_termination = false
    }

    ebs_block_device {
      device_name = "/dev/sdj"
      volume_type = "standard"
      iops = "150"
      volume_size = "50"
      delete_on_termination = false
    }

    user_data =  <<HEREDOC
    #!/bin/bash
    sudo su

    mdadm --create --verbose /dev/md0 --level=0 --name=MY_RAID --raid-devices=2 /dev/sdh /dev/sdj
    mkfs -t ext4 -L bigdisk /dev/md0
    mkdir -p /mysql
    mount /dev/md0 /mysql

    yum update -y
    yum install -y mysql57-server
    export AWS_ACCESS_KEY_ID=${var.aws_access_key}
    export AWS_SECRET_ACCESS_KEY=${var.aws_secret_key}
    aws s3 cp --region ${var.region} s3://${aws_s3_bucket.b.bucket}/${aws_s3_bucket_object.config.key} /etc/my.cnf
    service mysqld start
    mysql -e "USE mysql; CREATE USER 'admin'@'%' IDENTIFIED BY 'password'; GRANT ALL PRIVILEGES ON * . * TO 'admin'@'%';"
    HEREDOC
}

# create phpmyadmin application
resource "aws_instance" "node" {
    ami = "${var.aws_ami}"
    availability_zone = "us-west-1a"
    instance_type = "t2.micro"
    key_name = "${aws_key_pair.dev.key_name}"
    vpc_security_group_ids = ["${aws_security_group.web.id}"]
    subnet_id = "${aws_subnet.us-west-1a-public.id}"

    tags {
        Name = "SQL Admin"
    }

    user_data = <<HEREDOC
    #!/bin/bash
    sudo su
    yum update -y
    yum install -y docker
    service docker start
    docker run --name myadmin -d -e PMA_HOST=${aws_instance.db.private_ip} -p 80:80 phpmyadmin/phpmyadmin
    HEREDOC
}