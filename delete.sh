#!/bin/sh

sudo ip netns del client1
sudo ip netns del client2
sudo ip netns del server
sudo ip netns del firewall

sudo ip link del veth-fw_hst
sudo ip link del veth-hst

sudo iptables -t nat -F


