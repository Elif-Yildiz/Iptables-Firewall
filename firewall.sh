#!/bin/sh

# Client1 subnetwork is 192.0.2.0/26
# Client2 subnetwork is 192.0.2.64/26
# Server subnetwork is 192.0.2.128/26
# Host-To-Firewall Subnetwork is 192.0.2.192/26

sbn="/26"

c1="192.0.2.0"
c2="192.0.2.64"
srv="192.0.2.128"
fw="192.0.2.192"

fw_c1_ip="192.0.2.1"
fw_c2_ip="192.0.2.65"
fw_srv_ip="192.0.2.129"
fw_hst_ip="192.0.2.193"

c1_ip="192.0.2.2"
c2_ip="192.0.2.66"
srv_ip="192.0.2.130"
hst_ip="192.0.2.194"

#------------------------------- IPTABLES -------------------------------

sudo ip netns exec firewall iptables -F

# set default policies to drop. if you are not prepared for unknown ,it will drop so you will be safe ^^
sudo ip netns exec firewall iptables -P INPUT DROP
sudo ip netns exec firewall iptables -P OUTPUT DROP
sudo ip netns exec firewall iptables -P FORWARD DROP

# INPUT CHAIN

sudo ip netns exec firewall iptables -A INPUT -p icmp -s ${c1_ip} -i veth-fw-c1 -d ${c1_fw_ip} -j REJECT #default policye değilde bu kurala takıldığının anlamak için reject yaptım, normalde drop olarak kullanacağım

sudo ip netns exec firewall iptables -A INPUT -p icmp -s ${c2_ip} -i veth-fw-c1 -d ${c2_fw_ip} -j ACCEPT

sudo ip netns exec firewall iptables -A INPUT -i lo -j ACCEPT # enable all firewall's trafic baby, no red lights
sudo ip netns exec firewall iptables -A INPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -p udp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -i veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -i veth-fw-hst -p tcp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# FORWARD CHAIN
sudo ip netns exec firewall iptables -A FORWARD -s ${c2}${sbn} -d ${srv}${sbn} -i veth-fw-c2 -o veth-fw-srv -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A FORWARD -s ${srv}${sbn} -d ${c2}${sbn} -i veth-fw-srv -o veth-fw-c2 -p tcp --sport 80 -m state --state ESTABLISHED,RELATED -j ACCEPT

sudo ip netns exec firewall iptables -A FORWARD -i veth-fw-c1 -o veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from client1 are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-c1 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from client1 are enabled

sudo ip netns exec firewall iptables -A FORWARD -s ${c2}${sbn} -i veth-fw-c2 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from client2 are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-c2 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from client2 are enabled

sudo ip netns exec firewall iptables -A FORWARD -s ${srv}${sbn} -i veth-fw-srv -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from server are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-srv -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from server are enabled


# OUTPUT CHAIN
sudo ip netns exec firewall iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -p udp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-hst -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-fw-hst -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT



# iptables -I INPUT -p tcp --dport 22 -j REJECT
