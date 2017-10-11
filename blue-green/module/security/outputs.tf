output "web" {
    value = "${aws_security_group.web.id}"
}

output "ssh" {
    value = "${aws_security_group.ssh.id}"
}