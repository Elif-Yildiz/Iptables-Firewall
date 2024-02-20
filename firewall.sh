#!/bin/sh

#Elif Yildiz


#Client1 subnetwork is 192.0.2.0/26
#Client2 subnetwork is 192.0.2.64/26
#Server subnetwork is 192.0.2.128/26
#Host-To-Firewall Subnetwork is 192.0.2.192/26


#vars
client1_s="192.0.2.0/26"
client2_s="192.0.2.64/26"
server_s="192.0.2.128/26"
firewall_s="192.0.2.192/26"

c1="192.0.2.0"
c2="192.0.2.64"
s="192.0.2.128"
f="192.0.2.192"


scope="/26"

client1_ip="192.0.2.1"
client2_ip="192.0.2.65"
server_ip="192.0.2.129"

c1_fw_ip="192.0.2.2"
c2_fw_ip="192.0.2.66"
server_fw_ip="192.0.2.130"

host_ip="192.0.2.193"
host_fw_ip="192.0.2.194"


#--------------------------------------NAMESPACE CREATION-------------------------------------------------------------


#Create 4 network namespaces.
#Namespaces are client1, client2, server, firewall
sudo ip netns add client1
sudo ip netns add client2
sudo ip netns add server
sudo ip netns add firewall

#Create veth for all namespaces and your host-to-firewall for network communication

#veth peering
sudo ip link add veth-client1 type veth peer name veth-c1-fw
sudo ip link add veth-client2 type veth peer name veth-c2-fw
sudo ip link add veth-server type veth peer name veth-server-fw

sudo ip link add veth-host type veth peer name veth-host-fw

#assigning veths to namespaces 
sudo ip link set veth-client1 netns client1
sudo ip link set veth-client2 netns client2
sudo ip link set veth-server netns server
sudo ip link set veth-c1-fw netns firewall
sudo ip link set veth-c2-fw netns firewall
sudo ip link set veth-server-fw netns firewall

sudo ip link set veth-host-fw netns firewall


#assigning ip 
sudo ip netns exec client1 ip addr add ${client1_ip}${scope} dev veth-client1
sudo ip netns exec client2 ip addr add ${client2_ip}${scope} dev veth-client2 
sudo ip netns exec  server ip addr add ${server_ip}${scope} dev veth-server

sudo ip netns exec firewall ip addr add ${c1_fw_ip}${scope} dev veth-c1-fw
sudo ip netns exec firewall ip addr add ${c2_fw_ip}${scope} dev veth-c2-fw
sudo ip netns exec firewall ip addr add ${server_fw_ip}${scope} dev veth-server-fw  

sudo ip addr add ${host_ip}${scope} dev veth-host
sudo ip netns exec firewall ip addr add ${host_fw_ip}${scope} dev veth-host-fw

#building up all the interfaces 
sudo ip netns exec client1 ip link set veth-client1 up
sudo ip netns exec client2 ip link set veth-client2 up
sudo ip netns exec server ip link set veth-server up
sudo ip netns exec firewall ip link set veth-c1-fw up
sudo ip netns exec firewall ip link set veth-c2-fw up
sudo ip netns exec firewall ip link set veth-server-fw up

sudo ip netns exec client1 ip link set lo up
sudo ip netns exec client2 ip link set lo up
sudo ip netns exec server ip link set lo up
sudo ip netns exec firewall ip link set lo up


sudo ip link set veth-host up
sudo ip netns exec firewall ip link set veth-host-fw up  


# Enable IP forwarding
sudo ip netns exec firewall sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.ip_forward=1

#adding default gateways
sudo ip netns exec client1 ip route add default via ${c1_fw_ip}
sudo ip netns exec client2 ip route add default via ${c2_fw_ip}
sudo ip netns exec server ip route add default via ${server_fw_ip}

sudo ip netns exec firewall ip route add default via ${host_ip}



#sudo ip route add ${client1_s} via 192.0.2.194 dev veth-host # client1
#sudo ip route add 192.2.0.64/26 via 192.0.2.194 dev veth-host # client2
#sudo ip route add 192.2.0.128/26 via 192.0.2.194 dev veth-host # server

#-----------------access to the internet from firewall namespace via your host machine------------------------------------------------------------------------------


sudo route add -net 192.0.2.0 netmask 255.255.255.0 gw 192.0.2.194
sudo iptables -t nat -A POSTROUTING -s $client1_s -j MASQUERADE

sudo iptables -t nat -A POSTROUTING -s $client2_s -j MASQUERADE

sudo iptables -t nat -A POSTROUTING -s $server_s -j MASQUERADE


#----------------------FIREWALL--------------------------------------------------------------------------


#Rules
#Client1 can ping to server
#Client2 can access to server for http
#Client2 can ping to firewall
#Client1 doesn't have ping permission to firewall
#Client and server networks are can be access to the internet from firewall namespace via your host machine.


 
sudo ip netns exec firewall iptables -F #flush all the rules

sudo ip netns exec firewall iptables -P INPUT DROP #default policy
sudo ip netns exec firewall iptables -P FORWARD DROP #default policy
sudo ip netns exec firewall iptables -P OUTPUT DROP #default policy


#INPUT CHAIN
sudo ip netns exec firewall iptables -A INPUT -p icmp --icmp-type echo-reques -s $client1_s -j LOG --log-prefix "MY LOGS" #my optional logging preference
sudo ip netns exec firewall iptables -A INPUT -p icmp --icmp-type echo-reques -s $client1_s -d $firewall_s -j REJECT #Client1 doesn't have ping permission to firewall
sudo ip netns exec firewall iptables -A INPUT -p icmp --icmp-type echo-reques -s $client2_s -d $firewall_s -j ACCEPT #Client2 can ping to firewall

#FORWARD CHAIN
sudo ip netns exec firewall iptables -A FORWARD -p icmp --icmp-type echo-reques -s $client1_s -d $firewall_s -j REJECT #Client1 doesn't have ping permission to firewall
sudo ip netns exec firewall iptables -A FORWARD -p icmp --icmp-type echo-reques -s $client2_s -d $firewall_s -j ACCEPT #Client2 can ping to firewall
sudo ip netns exec firewall iptables -A FORWARD -p icmp --icmp-type echo-reques -s $client1_s -d $server_s -j ACCEPT #Client1 can ping to server
sudo ip netns exec firewall iptables -A FORWARD -p tcp -s $client2_s --dport 80 -d $server_s -j ACCEPT #Client2 can access to server for http




#OUTPUT CHAIN
sudo ip netns exec firewall iptables -A OUTPUT -p icmp -j ACCEPT
sudo ip netns exec firewall iptables -A OUTPUT -p tcp -j ACCEPT

#htpp(80) server
sudo ip netns exec server python3 -m http.server 80

#------------------------------------------------------unrelated/extra---------------------------------------


#trace route (dummy spy note hehe)
#iptables-save > /etc/iptables/rules.v4 #save your rules for ipv4 :3
#iptables -L --line-numbers #rulezzz numbered
#iptables -I INPUT -p icmp --icmp-type 8 -m limit --limit 10/minute -j ACCEPT #limit ping amount
#iptables -A INPUT -p icmp --icmp-type 8 -j LOG --log-prefix "MY LOGS" #log for ping pong
#grep "MY LOGS" /var/log/syslog #look at your logs for anything sus!
#iptables -D <chain> <number>

#--------------------------------------------RESOURCES I USED--------------------------------------------------------

#-----------------------------------------------THE END-------------------------------------------------------------









