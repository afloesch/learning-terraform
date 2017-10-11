output "public_subnet_ids" {
  value = ["${aws_subnet.subnet.*.id}"]
}

output "vpc_id" {
    value = "${aws_vpc.default.id}"
}