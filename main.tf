variable "UN" {}
variable "PW" {}
variable "DC" {}
variable "admin_password" {}
variable "priv_ssh_key" {
  default = "~/.ssh/id_rsa"
}
variable "pub_ssh_key" {
  default = "~/.ssh/id_rsa.pub"
}

provider "arubacloud" {
  username  = "${var.UN}"
  password  = "${var.PW}"
  dc_number = "${var.DC}"
}

locals {
  public_key = "${file(var.pub_ssh_key)}"
}

resource "arubacloud_server_smart" "openvpn" {
  smart_size       = "SMALL"
  name             = "openvpn-1"
  admin_password   = "${var.admin_password}"
  os_template_name = "Ubuntu Server 16.04 LTS 64bit"
  note             = "OpenVPN server created with arubacloud terraform provider"

  connection {
    type        = "ssh"
    host        = "${self.public_ip}"
    user        = "root"
    password    = "${var.admin_password}}"
    timeout     = "10m"
  }

  provisioner "file" {
    source      = "files/base.conf"
    destination = "client_configs/base.conf"
  }

  provisioner "file" {
    source      = "files/make_config.sh"
    destination = "client_configs/make_config.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "apt-get update",
      "apt-get install -y openvpn easy-rsa",
      "make-cadir ~/openvpn-ca",
      "sed -i 's|KEY_NAME=\"EasyRSA\"|KEY_NAME=\"server\"|g' ~/openvpn-ca/vars",
      "cd ~/openvpn-ca; source vars; ./clean-all; yes '' | ./build-ca; ./build-key-server server <<< $'\n\n\n\n\n\n\n\n\n\ny\ny\n'; ./build-dh",
      "cd ~/openvpn-ca; openvpn --genkey --secret ~/openvpn-ca/keys/ta.key",
      "cd ~/openvpn-ca; source vars; ./build-key client1 <<< $'\n\n\n\n\n\n\n\n\n\ny\ny\n'",
      "cd ~/openvpn-ca; cp ca.crt server.crt server.key ta.key dh2048.pem /etc/openvpn",
      "gunzip -c /usr/share/doc/openvpn/examples/sample-config-files/server.conf.gz | sudo tee /etc/openvpn/server.conf",
      "sed -i 's|;tls-auth ta.key 0 # This file is secret|tls-auth ta.key 0 # This file is secret\nkey-direction 0|' /etc/openvpn/server.conf",
      "sed -i 's|;cipher AES-128-CBC   # AES|cipher AES-128-CBC   # AES\nauth SHA256|' /etc/openvpn/server.conf",
      "sed -i 's|;user nobody|user nobody|' /etc/openvpn/server.conf",
      "sed -i 's|;group nogroup|group nogroup|' /etc/openvpn/server.conf",
      "sed -i 's|#net.ipv4.ip_forward=1|net.ipv4.ip_forward=1|' /etc/sysctl.conf",
      "systemctl enable openvpn@server",
      "mkdir -p ~/client-configs/files; chmod 700 ~/client-configs/files",
      "cp /usr/share/doc/openvpn/examples/sample-config-files/client.conf ~/client-configs/client1.conf",
      "mkdir -p ~/.ssh; echo \"${local.public_key}\" > ~/.ssh/authorized_keys",
      "cd ~/client_configs; bash make_config.sh client1 \"${self.public_ip}\""
    ]
  }

  provisioner "local-exec" {
    command = "ssh -i ${var.priv_ssh_key} root@${self.public_ip} cat ~/client_configs/files/client1.ovpn > client1.ovpn"
  }

  provisioner "remote-exec" {
    inline = [
      "reboot"
    ]
  }
}

output "openvpn_public_ip" {
  value = "${arubacloud_server_smart.openvpn.public_ip}"
}
