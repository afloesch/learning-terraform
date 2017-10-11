provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region = "${var.region}"
}

# import the cert into amazon for accessing the boxes
resource "aws_key_pair" "dev" {
  key_name   = "${var.aws_key_name}"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCqTct2kzoI8GR008xizhsPfg+lbnZLWlxxSBP5nu7gm0KT3W3e+wdNzoQU21f6B/PW1YAVShJZP7I/OIXLQ82bW0PnFWxzXi+f9bz+ETmiIgKzaPOEP6W2IHyygHHc6Wy5OD6aLP5yjRJcvoKJXLp2C1wvviJjsvY8+c9g7Nk1F40/MSR4QqBE+mX4QgF1saTBKwLgOrLlqgYgrDnlmi+x4837f4W1BfPT/ruFGkqhRXG2IgonSEbNtL3XZ1tuzod7CCyjyKQ83vy8sXn/U/j3t3kId4lh5JlCPO+Q67aAK1c0oAvDos6JVtmofWT14Ud+2oOcD5x4Xi9i0Z5SzwXh andrew.loesch@C02Q9FEKG8WN-L"
}