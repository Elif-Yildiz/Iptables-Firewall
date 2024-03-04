#!/bin/sh

#Client1 subnetwork is 192.0.2.0/26
#Client2 subnetwork is 192.0.2.64/26
#Server subnetwork is 192.0.2.128/26
#Host-To-Firewall Subnetwork is 192.0.2.192/26

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

#------------------------------- NAMESPACE CONF -------------------------------

#Create 4 network namespaces.
#Namespaces are client1, client2, server, firewall

sudo ip netns add client1
sudo ip netns add client2
sudo ip netns add server
sudo ip netns add firewall

#Create veth for all namespaces and your host-to-firewall for network communication.

sudo ip link add veth-c1 type veth peer name veth-fw-c1
sudo ip link add veth-c2 type veth peer name veth-fw-c2
sudo ip link add veth-srv type veth peer name veth-fw-srv
sudo ip link add veth-hst type veth peer name veth-fw-hst

#assigning veths to namespaces 
sudo ip link set veth-c1 netns client1
sudo ip link set veth-c2 netns client2
sudo ip link set veth-srv netns server
sudo ip link set veth-fw-c1 netns firewall
sudo ip link set veth-fw-c2 netns firewall
sudo ip link set veth-fw-srv netns firewall
sudo ip link set veth-fw-hst netns firewall

#building up all the interfaces 
sudo ip netns exec client1 ip link set veth-c1 up
sudo ip netns exec client2 ip link set veth-c2 up
sudo ip netns exec server ip link set veth-srv up
sudo ip netns exec firewall ip link set veth-fw-c1 up
sudo ip netns exec firewall ip link set veth-fw-c2 up
sudo ip netns exec firewall ip link set veth-fw-srv up
sudo ip netns exec firewall ip link set veth-fw-hst up
sudo ip link set veth-hst up


sudo ip netns exec client1 ip link set lo up
sudo ip netns exec client2 ip link set lo up
sudo ip netns exec server ip link set lo up
sudo ip netns exec firewall ip link set lo up

#assigning ip 
sudo ip netns exec client1 ip addr add ${c1_ip}${sbn} dev veth-c1
sudo ip netns exec client2 ip addr add ${c2_ip}${sbn} dev veth-c2
sudo ip netns exec server ip addr add ${srv_ip}${sbn} dev veth-srv
sudo ip netns exec firewall ip addr add ${fw_c1_ip}${sbn} dev veth-fw-c1
sudo ip netns exec firewall ip addr add ${fw_c2_ip}${sbn} dev veth-fw-c2
sudo ip netns exec firewall ip addr add ${fw_srv_ip}${sbn} dev veth-fw-srv
sudo ip netns exec firewall ip addr add ${fw_hst_ip}${sbn} dev veth-fw-hst
sudo ip addr add ${hst_ip}${sbn} dev veth-hst

# Enable IP forwarding
sudo ip netns exec client1 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec client2 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec server sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec firewall sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.ip_forward=1

#adding default gateways(if dont know where to go use default)
sudo ip netns exec client1 ip route add default via ${fw_c1_ip} dev veth-c1
sudo ip netns exec client2 ip route add default via ${fw_c2_ip} dev veth-c2
sudo ip netns exec server ip route add default via ${fw_srv_ip} dev veth-srv
sudo ip netns exec firewall ip route add default via ${hst_ip} dev veth-fw-hst

#before going out for internet have nat table fixed
sudo route add -net 192.0.2.0 netmask 255.255.255.0 gw ${fw_hst_ip}  
sudo iptables -t nat -A POSTROUTING -s 192.0.2.0/24 -j MASQUERADE
sudo ip netns exec firewall ip route add default via ${hst_ip} dev veth-fw-hst

#------------------------------- IPTABLES -------------------------------


# Rules
# Client1 can ping the server
# Client2 can access the server for HTTP
# Client2 can ping the firewall
# Client1 doesn't have ping permission to the firewall
# Client and server networks can be accessed to the internet from the firewall namespace via your host machine.


sudo ip netns exec firewall iptables -F # flush the prev rulezzzz dummy

# set default policies to drop. If you are not prepared for unknown, it will drop so you will be safe ^^
sudo ip netns exec firewall iptables -P INPUT DROP
sudo ip netns exec firewall iptables -P OUTPUT DROP
sudo ip netns exec firewall iptables -P FORWARD DROP

# INPUT CHAIN

sudo ip netns exec firewall iptables -A INPUT -p icmp -s ${c1_ip} -i veth-fw-c1 -d ${c1_fw_ip} -j DROP #REJECT #Instead of defult policy, I wanted to make sure this rule works. That is why I used reject, normally I will use it as drop. # This rule satisfies "Client1 doesn't have ping permission to the firewall"

sudo ip netns exec firewall iptables -A INPUT -p icmp -s ${c2_ip} -i veth-fw-c1 -d ${c2_fw_ip} -j ACCEPT # Client2 can ping the firewall

# enable all firewall's trafic baby, no red lights
sudo ip netns exec firewall iptables -A INPUT -i lo -j ACCEPT 
sudo ip netns exec firewall iptables -A INPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -p udp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -i veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A INPUT -i veth-fw-hst -p tcp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

# FORWARD CHAIN
sudo ip netns exec firewall iptables -A FORWARD -s ${c2}${sbn} -d ${srv}${sbn} -i veth-fw-c2 -o veth-fw-srv -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT #Client2 can access the server for HTTP
sudo ip netns exec firewall iptables -A FORWARD -s ${srv}${sbn} -d ${c2}${sbn} -i veth-fw-srv -o veth-fw-c2 -p tcp --sport 80 -m state --state ESTABLISHED,RELATED -j ACCEPT 

sudo ip netns exec firewall iptables -A FORWARD -i veth-fw-c1 -o veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from client1 are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-c1 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from client1 are enabled

sudo ip netns exec firewall iptables -A FORWARD -s ${c2}${sbn} -i veth-fw-c2 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from client2 are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-c2 -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from client2 are enabled

sudo ip netns exec firewall iptables -A FORWARD -s ${srv}${sbn} -i veth-fw-srv -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets coming from server are enabled
sudo ip netns exec firewall iptables -A FORWARD -o veth-fw-srv -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT # packets going out from server are enabled


# OUTPUT CHAIN
# enable firewalls trafic that is going out, no red lightzzz baby
sudo ip netns exec firewall iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o lo -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -p udp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-hst -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-fw-hst -p icmp -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -o veth-fw-hst -p tcp --dport 80 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT

sudo ip netns exec server python3 -m http.server 80 #building server up

# iptables -I INPUT -p tcp --dport 22 -j REJECT # this part is for a memory of ssh wars we had, note: close the ports you do not use



